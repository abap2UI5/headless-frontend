"! Headless browser simulator for abap2UI5 apps.
"!
"! Drives an app through the same request/response JSON protocol the UI5
"! frontend uses (see abap2UI5 app/webapp/core/Server.js), but entirely on the
"! server - no browser required. Each call to start( )/click( ) is one
"! roundtrip: the request struct is filled, z2ui5_cl_ui5_handler runs the
"! app, and the response is replayed the way the frontend replays it - view
"! layers built and torn down, models pushed, messages shown, follow-up
"! actions and the browser-history intent recorded.
"!
"! Typical use in an ABAP Unit test:
"!   DATA(sim) = z2ui5_cl_frontend_simulator=&gt;start( `Z2UI5_CL_FRONTEND_SIM_EXAMPLE` ).
"!   sim-&gt;set_value( name = `MV_NAME` value = `World` ).
"!   sim-&gt;click( `GREET` ).
"!   cl_abap_unit_assert=&gt;assert_equals( exp = `Hello World!`
"!                                       act = sim-&gt;get_message( ) ).
"!
"! set_value / click / get_value address the app by the names the app author
"! already coded: the bound attribute name ( client-&gt;_bind( mv_name ) - model
"! path /MV_NAME ) and the event id ( client-&gt;_event( `GREET` ) ).
"!
"! The view layers are the five slots of the frontend: MAIN, the nested
"! views NEST and NEST2 (inserted into MAIN, sharing its model), and the
"! standalone POPUP and POPOVER (each with a model of its own). get_view( )
"! answers the topmost open one, get_layers( ) all of them.
"!
"! Each instance is one browser tab. resume( ) continues a draft-based
"! session from its draft id in a new instance - a new HTTP request, a new
"! work process - which is what a stateless driver (an MCP endpoint, a
"! batch replay) needs. Sticky apps keep no draft and cannot be resumed.
CLASS z2ui5_cl_frontend_simulator DEFINITION PUBLIC FINAL CREATE PRIVATE.

  PUBLIC SECTION.

    "! The wire protocol this simulator reads (S_FRONT.PROTOCOL of the
    "! response, z2ui5_if_ui5_types=&gt;c_protocol in the core). A response
    "! that names another one is refused, as the frontend refuses it.
    CONSTANTS c_protocol TYPE i VALUE 2.

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

    "! One open view layer. layer is a z2ui5_if_client=&gt;cs_view value
    "! (MAIN, NEST, NEST2, POPUP, POPOVER). model is the JSON model the layer
    "! is bound against - a nested view answers the MAIN model it inherits.
    "! app is the class that displayed it. anchor_id is the control a popover
    "! opens by, or the control a nested view is inserted into. roundtrip is
    "! the roundtrip that displayed the layer.
    TYPES:
      BEGIN OF ty_s_layer,
        layer     TYPE string,
        xml       TYPE string,
        model     TYPE string,
        app       TYPE string,
        anchor_id TYPE string,
        roundtrip TYPE i,
      END OF ty_s_layer.
    TYPES ty_t_layer TYPE STANDARD TABLE OF ty_s_layer WITH EMPTY KEY.

    "! One follow-up action of the last response - what the app queued with
    "! follow_up_action( ), message_toast_display( ) and friends, run by the
    "! frontend after rendering. name is the first array element (SET_FOCUS,
    "! MESSAGE_TOAST, CONTROL_GLOBAL, ...), t_arg the further elements as
    "! text (an object or array argument as its JSON), json the raw entry.
    TYPES:
      BEGIN OF ty_s_action,
        name  TYPE string,
        t_arg TYPE string_table,
        json  TYPE string,
      END OF ty_s_action.
    TYPES ty_t_action TYPE STANDARD TABLE OF ty_s_action WITH EMPTY KEY.

    "! The browser-history intent - read-only, nothing is navigated. All
    "! fields but routing describe the LAST response only: the options of its
    "! ROUTER/sync action (empty when it carried no nav intent) and whether
    "! its MAIN display played as a way back. routing is the hash-routing
    "! mode the frontend currently holds (KEEP / FRESH / DEFAULT, empty for
    "! none), kept across roundtrips the way the frontend keeps it.
    TYPES:
      BEGIN OF ty_s_nav,
        routing               TYPE string,
        set_nav_routing       TYPE string,
        set_app_state_active  TYPE abap_bool,
        set_push_state        TYPE string,
        hash_replace          TYPE string,
        set_hash_event        TYPE string,
        check_nav_app_call    TYPE abap_bool,
        nav_app_call_prev_app TYPE string,
        nav_app_call_prev_id  TYPE string,
        nav_back              TYPE abap_bool,
        transition            TYPE string,
      END OF ty_s_nav.

    "! Start an app - one roundtrip without an id, mirroring the browser's
    "! first POST with ?app_start=&lt;class name&gt;.
    "! @parameter app    | Global class name of the app to start (e.g. `Z2UI5_CL_FRONTEND_SIM_EXAMPLE`).
    "! @parameter result | The simulator instance, holding the first response.
    CLASS-METHODS start
      IMPORTING
        app           TYPE clike
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_frontend_simulator.

    "! Continue a draft-based session in a new instance - typically in a new
    "! request. The draft must exist for the current user; it does not for a
    "! sticky app (stateful sessions keep no draft), an expired id or another
    "! user's id, and the call raises then.
    "!
    "! No roundtrip happens by default: the next click( ) sends the id, the
    "! pending delta and the event, exactly what the browser sends. What the
    "! browser still knows and the backend does not - the view XML of each
    "! layer - comes from state, the string get_state( ) returned at the end
    "! of the previous request. Without state the instance knows the app
    "! class and the model of the draft, but no view and no layer.
    "! @parameter id      | Draft id to continue from (get_id( ) of the previous request).
    "! @parameter state   | Optional: get_state( ) of the previous request - restores the layers.
    "! @parameter refresh | abap_true: re-request the view with a restore roundtrip (the request a
    "!                       browser reload sends for a routed app). The app runs check_on_navigated( )
    "!                       and, written the canonical way, displays its main view again. A popup
    "!                       is only back if the app re-opens it there. Mints a new draft id.
    "! @parameter result  | The simulator instance.
    CLASS-METHODS resume
      IMPORTING
        id            TYPE clike
        state         TYPE clike     OPTIONAL
        refresh       TYPE abap_bool DEFAULT abap_false
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

    "! Set one cell of a bound table into the delta of the NEXT roundtrip - the
    "! equivalent of typing into an input of a table row. Sent the way the
    "! frontend sends it, as a row delta (TABLE.__delta.row.COLUMN).
    "! @parameter table  | Bound table attribute (e.g. `MT_ITEM`).
    "! @parameter row    | Row index, 1-based as in ABAP.
    "! @parameter column | Column name (e.g. `QTY`).
    "! @parameter value  | The value to send.
    "! @parameter result | The simulator instance (for fluent chaining).
    METHODS set_cell
      IMPORTING
        table         TYPE clike
        row           TYPE i
        column        TYPE clike
        value         TYPE clike
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_frontend_simulator.

    "! Fire an event - the equivalent of clicking a button. Sends the pending
    "! model delta together with the event and parses the response. With
    "! set_check_events( ) on, an event that is not wired in the active layer
    "! raises instead (see check_event_exists( )).
    "! @parameter event  | Event id as registered via client->_event( ).
    "! @parameter t_arg  | Optional event arguments (client->get_event_arg( )).
    "! @parameter result | The simulator instance (for fluent chaining).
    METHODS click
      IMPORTING
        event         TYPE clike
        t_arg         TYPE string_table OPTIONAL
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_frontend_simulator.

    "! Opt-in validation of click( ): with abap_true, an event that is not
    "! wired in the active layer raises z2ui5_cx_ui5_util_error naming the
    "! events that are - a test (or an agent) cannot drive a flow no user
    "! could perform. Off by default, so tests that exercise the protocol
    "! directly keep working.
    "! @parameter val    | abap_true switches the check on.
    "! @parameter result | The simulator instance (for fluent chaining).
    METHODS set_check_events
      IMPORTING
        val           TYPE abap_bool DEFAULT abap_true
      RETURNING
        VALUE(result) TYPE REF TO z2ui5_cl_frontend_simulator.

    "! Whether the event is wired (client->_event( )) in the active layer -
    "! the topmost one: an open popover, else an open popup, else the MAIN view
    "! together with its nested views. A heuristic on the view XML, not a
    "! control tree: visibility and enablement are not evaluated, and events
    "! fired by timers or keyboard shortcuts are not wired in a view.
    "! @parameter event | Event id.
    METHODS check_event_exists
      IMPORTING
        event         TYPE clike
      RETURNING
        VALUE(result) TYPE abap_bool.

    "! The events wired in the active layer (see check_event_exists( )), in
    "! view order, each once.
    METHODS get_events
      RETURNING
        VALUE(result) TYPE string_table.

    "! View XML of the topmost open layer (popover, else popup, else the MAIN
    "! view), or of the given layer. Empty when the layer is not open.
    "! @parameter layer | Optional: a z2ui5_if_client=>cs_view value (MAIN, NEST, NEST2, POPUP, POPOVER).
    METHODS get_view
      IMPORTING
        layer         TYPE clike OPTIONAL
      RETURNING
        VALUE(result) TYPE string.

    "! View XML of the open popup - empty when none is open.
    METHODS get_popup
      RETURNING
        VALUE(result) TYPE string.

    "! View XML of the open popover - empty when none is open.
    METHODS get_popover
      RETURNING
        VALUE(result) TYPE string.

    "! Name of the topmost open layer (POPOVER, POPUP or MAIN); empty when
    "! nothing is displayed.
    METHODS get_layer
      RETURNING
        VALUE(result) TYPE string.

    "! Every open layer with view XML and model, in slot order (MAIN, NEST,
    "! NEST2, POPUP, POPOVER).
    METHODS get_layers
      RETURNING
        VALUE(result) TYPE ty_t_layer.

    "! The JSON model of the topmost open layer, or of the given one - the
    "! last model the response carried when no layer is open.
    "! @parameter layer | Optional: a z2ui5_if_client=>cs_view value.
    METHODS get_model
      IMPORTING
        layer         TYPE clike OPTIONAL
      RETURNING
        VALUE(result) TYPE string.

    "! Read a value from the model of the topmost open layer (or the given
    "! one), falling back to the last model the server sent. Reflects the
    "! server's model - it is not an echo of set_value( ).
    "! @parameter name  | Bound attribute / model path (e.g. `MV_NAME`).
    "! @parameter layer | Optional: a z2ui5_if_client=>cs_view value.
    METHODS get_value
      IMPORTING
        name          TYPE clike
        layer         TYPE clike OPTIONAL
      RETURNING
        VALUE(result) TYPE string.

    "! Text of the last message toast or message box of the last response
    "! (empty if the last roundtrip produced none) - the convenience
    "! accessor over get_messages( ).
    METHODS get_message
      RETURNING
        VALUE(result) TYPE string.

    "! Every message of this instance, oldest first, with source (toast /
    "! box), severity and roundtrip number.
    "! @parameter only_last | abap_true: only the messages of the last roundtrip.
    METHODS get_messages
      IMPORTING
        only_last     TYPE abap_bool DEFAULT abap_false
      RETURNING
        VALUE(result) TYPE ty_t_message.

    "! The follow-up actions of the last response, in the order the frontend
    "! runs them.
    METHODS get_actions
      RETURNING
        VALUE(result) TYPE ty_t_action.

    "! The browser-history intent - see ty_s_nav.
    METHODS get_nav
      RETURNING
        VALUE(result) TYPE ty_s_nav.

    "! The app class that answered the last roundtrip (upper case) - after a
    "! nav_app_call( ) the called one.
    METHODS get_app
      RETURNING
        VALUE(result) TYPE string.

    "! Current draft id - the id the frontend would send with the next request.
    METHODS get_id
      RETURNING
        VALUE(result) TYPE string.

    "! Whether the app runs in a held (sticky) session: the handler is kept
    "! in this instance, and no draft backs the current id - such a session
    "! ends with the instance and cannot be resumed.
    METHODS is_sticky
      RETURNING
        VALUE(result) TYPE abap_bool.

    "! What the browser knows and the draft does not, as a JSON string - the
    "! open layers with their view XML and model, the app and the draft id.
    "! Hand it to resume( ) in the next request. Pending values, messages and
    "! actions are not part of it.
    METHODS get_state
      RETURNING
        VALUE(result) TYPE string.

    "! Number of roundtrips this instance performed (start( ) is the first).
    METHODS get_roundtrip
      RETURNING
        VALUE(result) TYPE i.

    "! Raw response JSON of the last roundtrip (for debugging / assertions).
    METHODS get_response_json
      RETURNING
        VALUE(result) TYPE string.

  PROTECTED SECTION.

  PRIVATE SECTION.

    TYPES:
      BEGIN OF ty_s_state,
        version    TYPE i,
        id         TYPE string,
        app        TYPE string,
        routing    TYPE string,
        model_last TYPE string,
        t_layer    TYPE ty_t_layer,
      END OF ty_s_state.

    DATA mo_handler      TYPE REF TO z2ui5_cl_ui5_handler.
    DATA mo_pending      TYPE REF TO z2ui5_if_ajson.
    DATA mv_id           TYPE string.
    DATA mv_app          TYPE string.
    DATA mv_model_last   TYPE string.
    DATA mt_layer        TYPE ty_t_layer.
    DATA mt_message      TYPE ty_t_message.
    DATA mt_action       TYPE ty_t_action.
    DATA ms_nav          TYPE ty_s_nav.
    DATA mv_roundtrip    TYPE i.
    DATA mv_check_events TYPE abap_bool.
    DATA mv_resp_json    TYPE string.

    METHODS roundtrip
      IMPORTING
        event  TYPE clike        OPTIONAL
        search TYPE clike        OPTIONAL
        hash   TYPE clike        OPTIONAL
        t_arg  TYPE string_table OPTIONAL.

    METHODS build_request
      IMPORTING
        event         TYPE clike        OPTIONAL
        search        TYPE clike        OPTIONAL
        hash          TYPE clike        OPTIONAL
        t_arg         TYPE string_table OPTIONAL
      RETURNING
        VALUE(result) TYPE string.

    METHODS parse_response
      IMPORTING
        json TYPE string.

    METHODS parse_system_action
      IMPORTING
        resp  TYPE REF TO z2ui5_if_ajson
        path  TYPE string
        model TYPE string.

    METHODS parse_custom_action
      IMPORTING
        resp TYPE REF TO z2ui5_if_ajson
        path TYPE string.

    METHODS parse_nav
      IMPORTING
        resp TYPE REF TO z2ui5_if_ajson
        path TYPE string.

    METHODS json_args
      IMPORTING
        resp          TYPE REF TO z2ui5_if_ajson
        path          TYPE string
      RETURNING
        VALUE(result) TYPE string_table.

    METHODS message_add
      IMPORTING
        source TYPE string
        method TYPE string
        text   TYPE string
        opt    TYPE REF TO z2ui5_if_ajson OPTIONAL.

    METHODS layer_display
      IMPORTING
        layer     TYPE string
        xml       TYPE string
        model     TYPE string
        anchor_id TYPE string.

    METHODS layer_destroy
      IMPORTING
        layer TYPE string.

    METHODS layer_top
      RETURNING
        VALUE(result) TYPE string.

    METHODS layer_read
      IMPORTING
        layer         TYPE string
      RETURNING
        VALUE(result) TYPE ty_s_layer.

    METHODS model_of_layer
      IMPORTING
        layer         TYPE string
      RETURNING
        VALUE(result) TYPE string.

    METHODS events_of_xml
      IMPORTING
        xml           TYPE string
      CHANGING
        ct_event      TYPE string_table.

    METHODS restore_state
      IMPORTING
        state TYPE clike.

    METHODS restore_draft.

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

  METHOD resume.

    DATA lv_id TYPE string.
    lv_id = id.
    lv_id = condense( lv_id ).

    " the draft is what the next request is restored from - checked here,
    " so a session that cannot be continued fails on resume( ) with a reason
    " instead of on the next click( ) with a restore error
    IF lv_id IS INITIAL
        OR z2ui5_cl_ui5_srv_draft=>get_instance( )->check_exists( lv_id ) = abap_false.
      RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error
        EXPORTING
          val = |RESUME_NO_DRAFT - no draft { lv_id } for this user. It expired, belongs to another user, | &&
                |or the app runs sticky (a stateful session keeps no draft and cannot be resumed across requests)|.
    ENDIF.

    result = NEW #( ).
    result->mv_id = lv_id.

    IF state IS NOT INITIAL.
      result->restore_state( state ).
    ELSE.
      result->restore_draft( ).
    ENDIF.

    IF refresh = abap_true.
      IF result->mv_app IS INITIAL.
        RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error
          EXPORTING val = |RESUME_NO_APP - the app class of draft { lv_id } is unknown, it cannot be refreshed|.
      ENDIF.
      " the request a browser reload sends for a routed app: no id, the
      " route #/app/<class>/<draft> in the hash - the backend restores the
      " draft (z2ui5_cl_ui5_action=>factory_first_start) and runs main( )
      " with check_on_navigated( ) set
      CLEAR result->mv_id.
      result->roundtrip( hash = |#/app/{ result->mv_app }/{ lv_id }| ).
    ENDIF.

  ENDMETHOD.

  METHOD restore_state.

    DATA ls_state TYPE ty_s_state.
    TRY.
        z2ui5_cl_ajson=>parse( CONV string( state ) )->to_abap( IMPORTING ev_container = ls_state ).
      CATCH cx_root INTO DATA(lx).
        RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error
          EXPORTING
            val      = `RESUME_STATE_INVALID - the state is not what get_state( ) returns`
            previous = lx.
    ENDTRY.

    IF ls_state-id <> mv_id.
      RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error
        EXPORTING val = |RESUME_STATE_STALE - the state belongs to draft { ls_state-id }, not to { mv_id }|.
    ENDIF.

    mv_app         = ls_state-app.
    mv_model_last  = ls_state-model_last.
    mt_layer       = ls_state-t_layer.
    ms_nav-routing = ls_state-routing.

  ENDMETHOD.

  METHOD restore_draft.

    " the app class and the model as the client was left holding it - the
    " draft carries both; the view XML it does not
    TRY.
        DATA(lo_app) = z2ui5_cl_ui5_app_cont=>db_load( mv_id ).
        mv_app = z2ui5_cl_ui5_util_context=>rtti_get_classname_by_ref( lo_app->mo_app ).
        mv_model_last = lo_app->mv_model_client.
        IF mv_model_last IS INITIAL.
          mv_model_last = lo_app->model_json_stringify( ).
        ENDIF.
      CATCH cx_root ##NO_HANDLER.
        " the next roundtrip restores the draft itself and reports what is
        " wrong with it - this is only the read-ahead for get_value( )
    ENDTRY.

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

  METHOD set_cell.

    IF row < 1.
      RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error
        EXPORTING val = |SET_CELL_ROW_INVALID - row { row } of { table }, rows count from 1|.
    ENDIF.

    IF mo_pending IS NOT BOUND.
      mo_pending = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>create_empty( ) ).
    ENDIF.

    " the frontend's row delta (Lib.buildDeltaFromPaths): row keys are the
    " 0-based model indices, the backend adds one (srv_model delta_row_index)
    DATA(lv_row) = row - 1.
    DATA(lv_path) = |{ conv_name_to_path( table ) }/__delta/{ lv_row }/{ to_upper( condense( column ) ) }|.

    TRY.
        mo_pending->set( iv_path         = lv_path
                         iv_val          = value
                         iv_ignore_empty = abap_false ).
      CATCH cx_root INTO DATA(lx).
        RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error EXPORTING val = lx.
    ENDTRY.

    result = me.

  ENDMETHOD.

  METHOD click.

    IF mv_check_events = abap_true AND check_event_exists( event ) = abap_false.
      RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error
        EXPORTING
          val = |EVENT_NOT_WIRED - event { event } is not wired in layer { layer_top( ) }; | &&
                |wired: { concat_lines_of( table = get_events( )
                                           sep   = `, ` ) }|.
    ENDIF.

    roundtrip( event = event
               t_arg = t_arg ).
    result = me.

  ENDMETHOD.

  METHOD set_check_events.

    mv_check_events = val.
    result = me.

  ENDMETHOD.

  METHOD roundtrip.

    DATA(lv_request) = build_request( event  = event
                                      search = search
                                      hash   = hash
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

    " like _http_post: a held handler answers the next request from the
    " action it holds, so a failed roundtrip must leave the one it started
    " with - not a half-navigated one - and none of its queues
    DATA(lo_action_before) = mo_handler->mo_action.
    TRY.
        DATA(ls_response) = mo_handler->main( ).
      CATCH cx_root INTO DATA(lx).
        IF mo_handler->mv_session_sticky = abap_true.
          mo_handler->mo_action = lo_action_before.
          CLEAR mo_handler->mo_action->ms_next.
        ELSE.
          CLEAR mo_handler.
        ENDIF.
        " the handler does not render app exceptions itself (that is the job
        " of _main in the http handler) - surface the real text to the caller
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

        IF hash IS NOT INITIAL.
          lo_req->set( iv_path = `/value/S_FRONT/HASH`
                       iv_val  = hash ).
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

    DATA lo_resp TYPE REF TO z2ui5_if_ajson.

    TRY.
        lo_resp = z2ui5_cl_ajson=>parse( json ).
      CATCH cx_root INTO DATA(lx).
        RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error EXPORTING val = lx.
    ENDTRY.

    " the frontend refuses a wire it was not written for (Server.js), and so
    " does this simulator - a response WITHOUT the field is let through
    IF lo_resp->exists( `/S_FRONT/PROTOCOL` ) = abap_true
        AND lo_resp->get_integer( `/S_FRONT/PROTOCOL` ) <> c_protocol.
      RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error
        EXPORTING
          val = |PROTOCOL_MISMATCH - the backend speaks wire protocol { lo_resp->get_integer( `/S_FRONT/PROTOCOL` ) }, | &&
                |this simulator reads { c_protocol }|.
    ENDIF.

    mv_resp_json = json.
    mv_roundtrip = mv_roundtrip + 1.
    CLEAR mt_action.
    ms_nav = VALUE #( routing = ms_nav-routing ).

    mv_id = lo_resp->get_string( `/S_FRONT/ID` ).

    " An APP SWITCH kills the two standalone layers - they live outside the
    " MAIN control tree, and the switch is visible here because the response
    " names its app (View1 _processAfterRendering, before the system actions)
    DATA(lv_app) = lo_resp->get_string( `/S_FRONT/APP` ).
    IF lv_app IS NOT INITIAL AND mv_app IS NOT INITIAL AND lv_app <> mv_app.
      layer_destroy( z2ui5_if_client=>cs_view-popup ).
      layer_destroy( z2ui5_if_client=>cs_view-popover ).
    ENDIF.
    IF lv_app IS NOT INITIAL.
      mv_app = lv_app.
    ENDIF.

    " An unchanged model is not sent at all; a display builds its layer with
    " the response's model, an empty one when the key is missing
    DATA(lv_model_present) = lo_resp->exists( `/MODEL` ).
    DATA(lv_model) = `{}`.
    IF lv_model_present = abap_true.
      TRY.
          lv_model = lo_resp->slice( `/MODEL` )->stringify( ).
        CATCH cx_root INTO lx.
          RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error EXPORTING val = lx.
      ENDTRY.
      mv_model_last = lv_model.
    ENDIF.

    " Phase 1: the SYSTEM actions - view lifecycle and history - in order
    DATA(lv_index) = 1.
    DO.
      DATA(lv_path) = |/S_FRONT/S_ACTION/T_SYSTEM/{ lv_index }|.
      IF lo_resp->exists( lv_path ) = abap_false.
        EXIT.
      ENDIF.
      parse_system_action( resp  = lo_resp
                           path  = lv_path
                           model = lv_model ).
      lv_index = lv_index + 1.
    ENDDO.

    " A MODEL key IS the model push: into every open layer that owns a model
    " and belongs to the app that answered (Slots updateModelIfRequired) -
    " a popup of a called app does not receive the caller's model, nor the
    " other way round. A layer built in this response already holds it
    IF lv_model_present = abap_true.
      LOOP AT mt_layer REFERENCE INTO DATA(lr_layer)
           WHERE layer = z2ui5_if_client=>cs_view-main
              OR layer = z2ui5_if_client=>cs_view-popup
              OR layer = z2ui5_if_client=>cs_view-popover.  "#EC CI_SORTSEQ
        IF lr_layer->app IS INITIAL OR lr_layer->app = mv_app.
          lr_layer->model = lv_model.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " Phase 2: the APP actions - what the app queued, run after rendering
    lv_index = 1.
    DO.
      lv_path = |/S_FRONT/S_ACTION/T_CUSTOM/{ lv_index }|.
      IF lo_resp->exists( lv_path ) = abap_false.
        EXIT.
      ENDIF.
      parse_custom_action( resp = lo_resp
                           path = lv_path ).
      lv_index = lv_index + 1.
    ENDDO.

  ENDMETHOD.

  METHOD parse_system_action.

    " [ VIEW_SLOTS, display, slot, xml, opt? ], [ VIEW_SLOTS, destroy, slot ]
    " and [ ROUTER, sync, opt ] - see z2ui5_cl_ui5_frontend
    CASE resp->get_string( |{ path }/1| ).

      WHEN z2ui5_if_ui5_types=>cs_slot_action-target.
        DATA(lv_method) = resp->get_string( |{ path }/2| ).
        DATA(lv_layer)  = resp->get_string( |{ path }/3| ).

        IF lv_method = z2ui5_if_ui5_types=>cs_slot_action-destroy.
          layer_destroy( lv_layer ).
          RETURN.
        ENDIF.

        IF lv_method <> z2ui5_if_ui5_types=>cs_slot_action-display.
          RETURN.
        ENDIF.

        DATA(lv_opt) = |{ path }/5|.
        DATA(lv_anchor) = resp->get_string( |{ lv_opt }/openById| ).
        IF lv_anchor IS INITIAL.
          lv_anchor = resp->get_string( |{ lv_opt }/id| ).
        ENDIF.

        IF lv_layer = z2ui5_if_client=>cs_view-main.
          ms_nav-nav_back   = xsdbool( resp->get_boolean( |{ lv_opt }/navBack| ) = abap_true
                                    OR resp->get_boolean( |{ lv_opt }/transitionBack| ) = abap_true ).
          ms_nav-transition = resp->get_string( |{ lv_opt }/transition| ).
        ENDIF.

        layer_display( layer     = lv_layer
                       xml       = resp->get_string( |{ path }/4| )
                       model     = model
                       anchor_id = lv_anchor ).

      WHEN z2ui5_if_ui5_types=>cs_global_target-router.
        parse_nav( resp = resp
                   path = |{ path }/3| ).

    ENDCASE.

  ENDMETHOD.

  METHOD parse_nav.

    ms_nav-set_app_state_active  = resp->get_boolean( |{ path }/setAppStateActive| ).
    ms_nav-check_nav_app_call    = resp->get_boolean( |{ path }/checkNavAppCall| ).
    ms_nav-set_push_state        = resp->get_string( |{ path }/setPushState| ).
    ms_nav-hash_replace          = resp->get_string( |{ path }/setHashReplace| ).
    ms_nav-set_nav_routing       = resp->get_string( |{ path }/setNavRouting| ).
    ms_nav-set_hash_event        = resp->get_string( |{ path }/setHashEvent| ).
    ms_nav-nav_app_call_prev_app = resp->get_string( |{ path }/navAppCallPrevApp| ).
    ms_nav-nav_app_call_prev_id  = resp->get_string( |{ path }/navAppCallPrevId| ).

    " the mode stays with the frontend until another one is sent
    IF ms_nav-set_nav_routing IS NOT INITIAL.
      ms_nav-routing = ms_nav-set_nav_routing.
    ENDIF.

  ENDMETHOD.

  METHOD parse_custom_action.

    DATA(ls_action) = VALUE ty_s_action( t_arg = json_args( resp = resp
                                                            path = path ) ).
    TRY.
        ls_action-json = resp->slice( path )->stringify( ).
      CATCH cx_root ##NO_HANDLER.
    ENDTRY.
    IF ls_action-t_arg IS NOT INITIAL.
      ls_action-name = ls_action-t_arg[ 1 ].
      DELETE ls_action-t_arg INDEX 1.
    ENDIF.
    INSERT ls_action INTO TABLE mt_action.

    " the whitelisted global calls - written by the framework directly
    " ([ MESSAGE_TOAST, show, text, opt? ]) or by the app through
    " cs_event-control_global ([ CONTROL_GLOBAL, MESSAGE_BOX, error, ... ])
    DATA(lv_target) = ls_action-name.
    DATA(lv_offset) = 0.
    IF lv_target = z2ui5_if_client=>cs_event-control_global.
      " the arguments of the global call start one position later
      lv_target = resp->get_string( |{ path }/2| ).
      lv_offset = 1.
    ENDIF.

    DATA(lv_method) = resp->get_string( |{ path }/{ 2 + lv_offset }| ).
    DATA(lv_text)   = resp->get_string( |{ path }/{ 3 + lv_offset }| ).
    DATA(lv_opt)    = |{ path }/{ 4 + lv_offset }|.

    CASE lv_target.

      WHEN z2ui5_if_ui5_types=>cs_global_target-message_toast
        OR z2ui5_if_ui5_types=>cs_global_target-message_box.
        DATA(lo_opt) = COND #( WHEN resp->get_node_type( lv_opt ) = z2ui5_if_ajson_types=>node_type-object
                               THEN resp->slice( lv_opt ) ).
        message_add( source = COND #( WHEN lv_target = z2ui5_if_ui5_types=>cs_global_target-message_toast
                                      THEN `toast`
                                      ELSE `box` )
                     method = lv_method
                     text   = lv_text
                     opt    = lo_opt ).

      WHEN z2ui5_if_ui5_types=>cs_slot_action-target.
        " popup_close / popover_close queued as a follow-up action
        IF lv_method = z2ui5_if_ui5_types=>cs_slot_action-destroy.
          layer_destroy( lv_text ).
        ENDIF.

    ENDCASE.

  ENDMETHOD.

  METHOD json_args.

    DATA(lv_index) = 1.
    DO.
      DATA(lv_path) = |{ path }/{ lv_index }|.
      DATA(lv_type) = resp->get_node_type( lv_path ).
      IF lv_type IS INITIAL.
        EXIT.
      ENDIF.
      IF lv_type = z2ui5_if_ajson_types=>node_type-object OR lv_type = z2ui5_if_ajson_types=>node_type-array.
        TRY.
            INSERT resp->slice( lv_path )->stringify( ) INTO TABLE result.
          CATCH cx_root.
            INSERT `` INTO TABLE result.
        ENDTRY.
      ELSE.
        INSERT resp->get_string( lv_path ) INTO TABLE result.
      ENDIF.
      lv_index = lv_index + 1.
    ENDDO.

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

  METHOD layer_display.

    " a display REPLACES the layer (actions/Slots). A new MAIN view is a new
    " screen: the nested views die with the control tree they were inserted
    " into, the standalone layers are taken down with it (displayMain) - a
    " popup the same response opens comes later in slot order and still opens
    IF layer = z2ui5_if_client=>cs_view-main.
      DELETE mt_layer WHERE layer <> z2ui5_if_client=>cs_view-main. "#EC CI_SORTSEQ
    ENDIF.
    layer_destroy( layer ).

    " a nested view owns no model - it inherits the MAIN one (model_of_layer)
    INSERT VALUE #( layer     = layer
                    xml       = xml
                    model     = COND #( WHEN layer <> z2ui5_if_client=>cs_view-nested
                                         AND layer <> z2ui5_if_client=>cs_view-nested2
                                        THEN model )
                    app       = mv_app
                    anchor_id = anchor_id
                    roundtrip = mv_roundtrip ) INTO TABLE mt_layer.

  ENDMETHOD.

  METHOD layer_destroy.

    DELETE mt_layer WHERE layer = layer. "#EC CI_SORTSEQ

    " the nested views live in the MAIN control tree and go down with it
    IF layer = z2ui5_if_client=>cs_view-main.
      DELETE mt_layer WHERE layer = z2ui5_if_client=>cs_view-nested
                         OR layer = z2ui5_if_client=>cs_view-nested2. "#EC CI_SORTSEQ
    ENDIF.

  ENDMETHOD.

  METHOD layer_top.

    LOOP AT VALUE string_table( ( z2ui5_if_client=>cs_view-popover )
                                ( z2ui5_if_client=>cs_view-popup )
                                ( z2ui5_if_client=>cs_view-main ) ) INTO DATA(lv_layer).
      IF line_exists( mt_layer[ layer = lv_layer ] ). "#EC CI_SORTSEQ
        result = lv_layer.
        RETURN.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD layer_read.

    DATA lv_layer TYPE string.
    lv_layer = layer.
    lv_layer = to_upper( lv_layer ).
    READ TABLE mt_layer INTO result WITH KEY layer = lv_layer. "#EC CI_SORTSEQ
    IF sy-subrc <> 0.
      CLEAR result.
      RETURN.
    ENDIF.
    result-model = model_of_layer( lv_layer ).

  ENDMETHOD.

  METHOD model_of_layer.

    DATA(lv_layer) = layer.
    IF lv_layer = z2ui5_if_client=>cs_view-nested OR lv_layer = z2ui5_if_client=>cs_view-nested2.
      lv_layer = z2ui5_if_client=>cs_view-main.
    ENDIF.
    READ TABLE mt_layer INTO DATA(ls_layer) WITH KEY layer = lv_layer. "#EC CI_SORTSEQ
    IF sy-subrc = 0.
      result = ls_layer-model.
    ENDIF.

  ENDMETHOD.

  METHOD events_of_xml.

    " An event wire is .eB(['NAME', ...], args...) - or .eBP($event,cond,
    " ['NAME', ...]) for a prevent-default wire - with the name escaped as a
    " single-quoted JS literal (z2ui5_cl_ui5_srv_event=>get_event). The
    " attribute value is XML-escaped on top, which a hand-written view may
    " also apply to the apostrophes
    DATA lv_name TYPE string.

    DATA(lv_xml) = xml.
    REPLACE ALL OCCURRENCES OF `&apos;` IN lv_xml WITH `'`.
    REPLACE ALL OCCURRENCES OF `&quot;` IN lv_xml WITH `"`.
    REPLACE ALL OCCURRENCES OF `&lt;` IN lv_xml WITH `<`.
    REPLACE ALL OCCURRENCES OF `&gt;` IN lv_xml WITH `>`.
    REPLACE ALL OCCURRENCES OF `&amp;` IN lv_xml WITH `&`.

    DATA(lv_len) = strlen( lv_xml ).
    DATA(lv_off) = 0.
    DO.
      IF lv_off >= lv_len.
        EXIT.
      ENDIF.
      DATA(lv_call) = find( val = lv_xml
                            sub = `.eB`
                            off = lv_off ).
      IF lv_call < 0.
        EXIT.
      ENDIF.
      " .eB(['NAME' - the array opens right behind the parenthesis.
      " .eBP($event,cond,['NAME' - behind the two leading arguments, and
      " the condition may be an expression with parentheses of its own
      DATA(lv_open) = find( val = lv_xml
                            sub = `['`
                            off = lv_call ).
      IF lv_open < 0.
        EXIT.
      ENDIF.
      IF lv_xml+lv_call(4) = `.eB(` AND lv_open <> lv_call + 4.
        lv_off = lv_call + 3.
        CONTINUE.
      ENDIF.

      CLEAR lv_name.
      DATA(lv_pos) = lv_open + 2.
      WHILE lv_pos < lv_len.
        DATA(lv_char) = substring( val = lv_xml
                                   off = lv_pos
                                   len = 1 ).
        IF lv_char = `\` AND lv_pos + 1 < lv_len.
          lv_pos = lv_pos + 1.
          lv_name = lv_name && substring( val = lv_xml
                                          off = lv_pos
                                          len = 1 ).
        ELSEIF lv_char = `'`.
          EXIT.
        ELSE.
          lv_name = lv_name && lv_char.
        ENDIF.
        lv_pos = lv_pos + 1.
      ENDWHILE.

      IF lv_name IS NOT INITIAL AND NOT line_exists( ct_event[ table_line = lv_name ] ). "#EC CI_SORTSEQ
        INSERT lv_name INTO TABLE ct_event.
      ENDIF.
      lv_off = lv_pos + 1.
    ENDDO.

  ENDMETHOD.

  METHOD check_event_exists.

    DATA lv_event TYPE string.
    lv_event = event.
    DATA(lt_event) = get_events( ).
    result = xsdbool( line_exists( lt_event[ table_line = lv_event ] ) ). "#EC CI_SORTSEQ

  ENDMETHOD.

  METHOD get_events.

    " a dialog is modal and a popover sits on top of whatever opened it: the
    " user reaches the topmost layer only. The MAIN view comes with the
    " nested views inserted into it
    DATA(lv_top) = layer_top( ).
    DATA(lt_layer) = COND string_table(
        WHEN lv_top = z2ui5_if_client=>cs_view-main
        THEN VALUE #( ( z2ui5_if_client=>cs_view-main )
                      ( z2ui5_if_client=>cs_view-nested )
                      ( z2ui5_if_client=>cs_view-nested2 ) )
        ELSE VALUE #( ( lv_top ) ) ).

    LOOP AT lt_layer INTO DATA(lv_layer).
      events_of_xml( EXPORTING xml      = layer_read( lv_layer )-xml
                     CHANGING  ct_event = result ).
    ENDLOOP.

  ENDMETHOD.

  METHOD get_view.

    result = layer_read( COND #( WHEN layer IS SUPPLIED THEN layer ELSE layer_top( ) ) )-xml.

  ENDMETHOD.

  METHOD get_popup.
    result = layer_read( z2ui5_if_client=>cs_view-popup )-xml.
  ENDMETHOD.

  METHOD get_popover.
    result = layer_read( z2ui5_if_client=>cs_view-popover )-xml.
  ENDMETHOD.

  METHOD get_layer.
    result = layer_top( ).
  ENDMETHOD.

  METHOD get_layers.

    LOOP AT VALUE string_table( ( z2ui5_if_client=>cs_view-main )
                                ( z2ui5_if_client=>cs_view-nested )
                                ( z2ui5_if_client=>cs_view-nested2 )
                                ( z2ui5_if_client=>cs_view-popup )
                                ( z2ui5_if_client=>cs_view-popover ) ) INTO DATA(lv_layer).
      DATA(ls_layer) = layer_read( lv_layer ).
      IF ls_layer-layer IS NOT INITIAL.
        INSERT ls_layer INTO TABLE result.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD get_model.

    DATA(lv_layer) = COND string( WHEN layer IS SUPPLIED THEN to_upper( layer ) ELSE layer_top( ) ).
    IF lv_layer IS NOT INITIAL AND line_exists( mt_layer[ layer = lv_layer ] ). "#EC CI_SORTSEQ
      result = model_of_layer( lv_layer ).
    ELSEIF layer IS NOT SUPPLIED.
      result = mv_model_last.
    ENDIF.

  ENDMETHOD.

  METHOD get_value.

    DATA(lv_path) = conv_name_to_path( name ).
    DATA(lt_model) = VALUE string_table( ( COND #( WHEN layer IS SUPPLIED
                                                   THEN get_model( layer )
                                                   ELSE get_model( ) ) ) ).
    IF layer IS NOT SUPPLIED.
      INSERT mv_model_last INTO TABLE lt_model.
    ENDIF.

    LOOP AT lt_model INTO DATA(lv_model) WHERE table_line IS NOT INITIAL.
      TRY.
          DATA(lo_model) = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>parse( lv_model ) ).
          IF lo_model->exists( lv_path ) = abap_true.
            result = lo_model->get_string( lv_path ).
            RETURN.
          ENDIF.
        CATCH cx_root ##NO_HANDLER.
      ENDTRY.
    ENDLOOP.

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

  METHOD get_actions.
    result = mt_action.
  ENDMETHOD.

  METHOD get_nav.
    result = ms_nav.
  ENDMETHOD.

  METHOD get_app.
    result = mv_app.
  ENDMETHOD.

  METHOD get_id.
    result = mv_id.
  ENDMETHOD.

  METHOD is_sticky.
    result = xsdbool( mo_handler IS BOUND ).
  ENDMETHOD.

  METHOD get_state.

    DATA(ls_state) = VALUE ty_s_state( version    = 1
                                       id         = mv_id
                                       app        = mv_app
                                       routing    = ms_nav-routing
                                       model_last = mv_model_last
                                       t_layer    = mt_layer ).
    TRY.
        DATA(lo_json) = CAST z2ui5_if_ajson( z2ui5_cl_ajson=>create_empty( ) ).
        lo_json->set( iv_path = `/`
                      iv_val  = ls_state ).
        result = lo_json->stringify( ).
      CATCH cx_root INTO DATA(lx).
        RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error EXPORTING val = lx.
    ENDTRY.

  ENDMETHOD.

  METHOD get_roundtrip.
    result = mv_roundtrip.
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
