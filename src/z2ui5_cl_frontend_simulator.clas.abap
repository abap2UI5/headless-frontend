"! Headless browser simulator for abap2UI5 apps.
"!
"! Drives an app through the same request/response JSON protocol the UI5
"! frontend uses (see abap2UI5 app/webapp/core/Server.js), but entirely on the
"! server - no browser required. Each call to start( )/click( ) is one
"! roundtrip: the request struct is filled, z2ui5_cl_ui5_handler runs the
"! app, and the response (view XML, model, messages) is parsed and kept.
"!
"! Typical use in an ABAP Unit test:
"!   DATA(sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_EXAMPLE` ).
"!   sim->set_value( name = `MV_NAME` value = `World` ).
"!   sim->click( `GREET` ).
"!   cl_abap_unit_assert=>assert_equals( exp = `Hello World!`
"!                                       act = sim->get_message( ) ).
"!
"! set_value / click / get_value address the app by the names the app author
"! already coded: the bound attribute name ( client->_bind( mv_name ) -> model
"! path /MV_NAME ) and the event id ( client->_event( `GREET` ) ). No view XML
"! parsing is involved - the XML is available via get_view( ) for inspection or
"! assertions. See z2ui5_cl_frontend_sim_example for a worked example.
CLASS z2ui5_cl_frontend_simulator DEFINITION PUBLIC FINAL CREATE PRIVATE.

  PUBLIC SECTION.

    "! One message the frontend would have shown - a toast or a message box.
    "! roundtrip counts the roundtrips of this instance (1 = start( )), so a
    "! test can tell the messages of the last click( ) from older ones.
    "! type is the severity in the vocabulary agents and UIs share - success,
    "! info, warning or error; method is the raw sap.m.MessageBox display
    "! method the backend asked for (show for a toast).
    TYPES:
      BEGIN OF ty_s_message,
        roundtrip TYPE i,
        source    TYPE string,
        type      TYPE string,
        method    TYPE string,
        text      TYPE string,
        title     TYPE string,
        details   TYPE string,
      END OF ty_s_message.
    TYPES ty_t_message TYPE STANDARD TABLE OF ty_s_message WITH EMPTY KEY.

    "! Start an app - one roundtrip without an id, mirroring the browser's
    "! first POST with ?app_start=&lt;class name&gt;.
    "! @parameter app    | Global class name of the app to start (e.g. `Z2UI5_CL_FRONTEND_SIM_EXAMPLE`).
    "! @parameter result | The simulator instance, holding the first response.
    CLASS-METHODS start
      IMPORTING
        app           TYPE clike
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_frontend_simulator.

    "! Set a value into the model delta of the NEXT roundtrip - the equivalent
    "! of typing into a bound input. No roundtrip happens yet; the value is sent
    "! on the following click( ).
    "! @parameter name   | Bound attribute / model path (e.g. `MV_NAME` or `/MS_DATA/FIELD`).
    "! @parameter value  | The value to send.
    "! @parameter result | The simulator instance (for fluent chaining).
    METHODS set_value
      IMPORTING
        name          TYPE clike
        value         TYPE clike
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_frontend_simulator.

    "! Fire an event - the equivalent of clicking a button. Sends the pending
    "! model delta together with the event and parses the response.
    "! @parameter event  | Event id as registered via client->_event( ).
    "! @parameter t_arg  | Optional event arguments (client->get_event_arg( )).
    "! @parameter result | The simulator instance (for fluent chaining).
    METHODS click
      IMPORTING
        event         TYPE clike
        t_arg         TYPE string_table OPTIONAL
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_frontend_simulator.

    "! The current view XML (last non-empty S_VIEW/XML from the server).
    METHODS get_view
      RETURNING
        VALUE(result) TYPE string.

    "! Read a value from the last server model. Reflects the model as of the
    "! last roundtrip that updated the view - it is not an echo of set_value( ).
    "! @parameter name | Bound attribute / model path (e.g. `MV_NAME`).
    METHODS get_value
      IMPORTING
        name          TYPE clike
      RETURNING
        VALUE(result) TYPE string.

    "! Text of the last message toast or message box of the last response
    "! (empty if the last roundtrip produced none) - the convenience
    "! accessor over get_messages( ).
    METHODS get_message
      RETURNING
        VALUE(result) TYPE string.

    "! Every message of this session, oldest first, with source (toast / box),
    "! severity and roundtrip number.
    "! @parameter only_last | abap_true: only the messages of the last roundtrip.
    METHODS get_messages
      IMPORTING
        only_last     TYPE abap_bool DEFAULT abap_false
      RETURNING
        VALUE(result) TYPE ty_t_message.

    "! Number of roundtrips this instance performed (start( ) is the first).
    METHODS get_roundtrip
      RETURNING
        VALUE(result) TYPE i.

    "! Current draft id - the id the frontend would send with the next request.
    METHODS get_id
      RETURNING
        VALUE(result) TYPE string.

    "! Raw response JSON of the last roundtrip (for debugging / assertions).
    METHODS get_response_json
      RETURNING
        VALUE(result) TYPE string.

  PROTECTED SECTION.

  PRIVATE SECTION.

    DATA mo_handler   TYPE REF TO z2ui5_cl_ui5_handler.
    DATA mo_pending   TYPE REF TO z2ui5_if_ajson.
    DATA mo_model     TYPE REF TO z2ui5_if_ajson.
    DATA mv_id        TYPE string.
    DATA mv_view_xml  TYPE string.
    DATA mt_message   TYPE ty_t_message.
    DATA mv_roundtrip TYPE i.
    DATA mv_resp_json TYPE string.

    METHODS roundtrip
      IMPORTING
        event  TYPE clike        OPTIONAL
        search TYPE clike        OPTIONAL
        t_arg  TYPE string_table OPTIONAL.

    METHODS build_request
      IMPORTING
        event         TYPE clike        OPTIONAL
        search        TYPE clike        OPTIONAL
        t_arg         TYPE string_table OPTIONAL
      RETURNING
        VALUE(result) TYPE string.

    METHODS parse_response
      IMPORTING
        json TYPE string.

    METHODS message_add
      IMPORTING
        source TYPE string
        method TYPE string
        text   TYPE string
        opt    TYPE REF TO z2ui5_if_ajson OPTIONAL.

    METHODS conv_name_to_path
      IMPORTING
        name          TYPE clike
      RETURNING
        VALUE(result) TYPE string.

ENDCLASS.


CLASS z2ui5_cl_frontend_simulator IMPLEMENTATION.

  METHOD start.

    result = NEW #( ).
    result->roundtrip( search = |?app_start={ app }| ).

  ENDMETHOD.

  METHOD set_value.

    IF mo_pending IS NOT BOUND.
      mo_pending = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>create_empty( ) ).
    ENDIF.

    TRY.
        mo_pending->set( iv_path         = conv_name_to_path( name )
                         iv_val          = value
                         iv_ignore_empty = abap_false ).
      CATCH cx_root INTO DATA(lx).
        RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error EXPORTING val = lx.
    ENDTRY.

    result = me.

  ENDMETHOD.

  METHOD click.

    roundtrip( event = event
               t_arg = t_arg ).
    result = me.

  ENDMETHOD.

  METHOD roundtrip.

    DATA(lv_request) = build_request( event  = event
                                      search = search
                                      t_arg  = t_arg ).

    " Reuse the handler for sticky apps, create a fresh one otherwise -
    " the same distinction z2ui5_cl_ui5_http_handler=>_http_post makes. Draft
    " based apps chain their state through the persisted id in the request.
    IF mo_handler IS BOUND.
      mo_handler->mv_request_json = lv_request.
      mo_handler->mv_session_sticky = abap_true.
    ELSE.
      mo_handler = NEW z2ui5_cl_ui5_handler( lv_request ).
      mo_handler->mv_session_sticky = abap_false.
    ENDIF.

    TRY.
        DATA(ls_response) = mo_handler->main( ).
      CATCH cx_root INTO DATA(lx).
        " the handler does not render app exceptions itself (that is the job
        " of _main in the http handler) - surface the real text to the test
        CLEAR mo_handler.
        RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error EXPORTING val = lx.
    ENDTRY.

    TRY.
        IF mo_handler->mo_action->mo_app->mv_check_sticky = abap_false.
          CLEAR mo_handler.
        ENDIF.
      CATCH cx_root.
        CLEAR mo_handler.
    ENDTRY.

    parse_response( ls_response-body ).
    CLEAR mo_pending.

  ENDMETHOD.

  METHOD build_request.

    TRY.
        DATA(lo_req) = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>create_empty( ) ).

        IF mv_id IS NOT INITIAL.
          lo_req->set( iv_path = `/value/S_FRONT/ID`
                       iv_val  = mv_id ).
        ENDIF.

        IF event IS NOT INITIAL.
          lo_req->set( iv_path = `/value/S_FRONT/EVENT`
                       iv_val  = event ).
        ENDIF.

        lo_req->set( iv_path = `/value/S_FRONT/ORIGIN`
                     iv_val  = `SIMULATOR` ).
        lo_req->set( iv_path = `/value/S_FRONT/PATHNAME`
                     iv_val  = `/sim` ).

        IF search IS NOT INITIAL.
          lo_req->set( iv_path = `/value/S_FRONT/SEARCH`
                       iv_val  = search ).
        ENDIF.

        IF t_arg IS NOT INITIAL.
          lo_req->set( iv_path = `/value/S_FRONT/T_EVENT_ARG`
                       iv_val  = t_arg ).
        ENDIF.

        IF mo_pending IS BOUND AND mo_pending->is_empty( ) = abap_false.
          lo_req->set( iv_path = `/value/MODEL`
                       iv_val  = mo_pending ).
        ENDIF.

        result = lo_req->stringify( ).

      CATCH cx_root INTO DATA(lx).
        RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error EXPORTING val = lx.
    ENDTRY.

  ENDMETHOD.

  METHOD parse_response.

    mv_resp_json = json.
    mv_roundtrip = mv_roundtrip + 1.

    TRY.
        DATA(lo_resp) = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>parse( json ) ).

        IF lo_resp->exists( `/S_FRONT/ID` ).
          mv_id = lo_resp->get_string( `/S_FRONT/ID` ).
        ENDIF.

        " every view build travels as a VIEW_SLOTS system action - the view
        " XML is only sent when the view changed, so keep the last one
        DATA(lv_index) = 1.
        DO.
          DATA(lv_path) = |/S_FRONT/S_ACTION/T_SYSTEM/{ lv_index }|.
          IF lo_resp->exists( lv_path ) = abap_false.
            EXIT.
          ENDIF.
          IF lo_resp->get_string( |{ lv_path }/1| ) = `VIEW_SLOTS`
              AND lo_resp->get_string( |{ lv_path }/2| ) = `display`
              AND lo_resp->get_string( |{ lv_path }/3| ) = `MAIN`.
            mv_view_xml = lo_resp->get_string( |{ lv_path }/4| ).
          ENDIF.
          lv_index = lv_index + 1.
        ENDDO.

        " messages are app follow-up actions, in the order the app queued
        " them: [ MESSAGE_TOAST, show, text, opt? ] and
        " [ MESSAGE_BOX, method, text, opt? ]
        lv_index = 1.
        DO.
          lv_path = |/S_FRONT/S_ACTION/T_CUSTOM/{ lv_index }|.
          IF lo_resp->exists( lv_path ) = abap_false.
            EXIT.
          ENDIF.
          DATA(lv_target) = lo_resp->get_string( |{ lv_path }/1| ).
          IF lv_target = `MESSAGE_TOAST` OR lv_target = `MESSAGE_BOX`.
            DATA(lo_opt) = COND #( WHEN lo_resp->get_node_type( |{ lv_path }/4| ) = z2ui5_if_ajson_types=>node_type-object
                                   THEN lo_resp->slice( |{ lv_path }/4| ) ).
            message_add( source = COND #( WHEN lv_target = `MESSAGE_TOAST` THEN `toast` ELSE `box` )
                         method = lo_resp->get_string( |{ lv_path }/2| )
                         text   = lo_resp->get_string( |{ lv_path }/3| )
                         opt    = lo_opt ).
          ENDIF.
          lv_index = lv_index + 1.
        ENDDO.

        " the full model is only sent when something bound changed - keep
        " the last populated one so get_value stays meaningful
        IF lo_resp->exists( `/MODEL` ).
          DATA(lo_model) = lo_resp->slice( `/MODEL` ).
          IF lo_model IS BOUND AND lo_model->is_empty( ) = abap_false.
            mo_model = lo_model.
          ENDIF.
        ENDIF.

      CATCH cx_root INTO DATA(lx).
        RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error EXPORTING val = lx.
    ENDTRY.

  ENDMETHOD.

  METHOD get_view.
    result = mv_view_xml.
  ENDMETHOD.

  METHOD get_value.

    DATA(lv_path) = conv_name_to_path( name ).
    IF mo_model IS BOUND AND mo_model->exists( lv_path ).
      result = mo_model->get_string( lv_path ).
    ENDIF.

  ENDMETHOD.

  METHOD get_message.

    " the last message of the LAST roundtrip - empty when it produced none.
    " READ TABLE, not a table expression in the condition: the 7.02 downport
    " hoists the expression in front of the IF, where the guard no longer
    " protects it from an empty table
    READ TABLE mt_message INTO DATA(ls_message) INDEX lines( mt_message ).
    IF sy-subrc = 0 AND ls_message-roundtrip = mv_roundtrip.
      result = ls_message-text.
    ENDIF.

  ENDMETHOD.

  METHOD get_messages.

    IF only_last = abap_false.
      result = mt_message.
      RETURN.
    ENDIF.

    LOOP AT mt_message INTO DATA(ls_message) WHERE roundtrip = mv_roundtrip. "#EC CI_SORTSEQ
      INSERT ls_message INTO TABLE result.
    ENDLOOP.

  ENDMETHOD.

  METHOD get_roundtrip.
    result = mv_roundtrip.
  ENDMETHOD.

  METHOD message_add.

    DATA(ls_message) = VALUE ty_s_message( roundtrip = mv_roundtrip
                                           source    = source
                                           method    = to_lower( method )
                                           text      = text ).

    " sap.m.MessageBox display methods - a toast carries no severity
    ls_message-type = SWITCH #( ls_message-method
                                WHEN `error`   THEN `error`
                                WHEN `warning` THEN `warning`
                                WHEN `success` THEN `success`
                                ELSE `info` ).

    IF opt IS BOUND.
      ls_message-title   = opt->get_string( `/title` ).
      ls_message-details = opt->get_string( `/details` ).
    ENDIF.

    INSERT ls_message INTO TABLE mt_message.

  ENDMETHOD.

  METHOD get_id.
    result = mv_id.
  ENDMETHOD.

  METHOD get_response_json.
    result = mv_resp_json.
  ENDMETHOD.

  METHOD conv_name_to_path.

    result = to_upper( condense( name ) ).
    IF result IS INITIAL OR result(1) <> `/`.
      result = |/{ result }|.
    ENDIF.

  ENDMETHOD.

ENDCLASS.
