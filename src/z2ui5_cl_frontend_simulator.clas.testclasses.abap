"! In-memory draft store, installed through the core's store seam
"! (z2ui5_cl_ui5_srv_draft=>set_instance) so the HARMLESS tests below run
"! the full draft roundtrip - serialize, persist, restore - without a single
"! database write. The DANGEROUS class at the end of this include covers the
"! real store on purpose.
CLASS ltd_draft_store DEFINITION FINAL FOR TESTING.

  PUBLIC SECTION.
    INTERFACES z2ui5_if_ui5_draft_store.

    DATA mt_db TYPE STANDARD TABLE OF z2ui5_if_ui5_draft_store=>ty_s_db WITH EMPTY KEY.

ENDCLASS.


CLASS ltd_draft_store IMPLEMENTATION.

  METHOD z2ui5_if_ui5_draft_store~count_entries.
    result = lines( mt_db ).
  ENDMETHOD.

  METHOD z2ui5_if_ui5_draft_store~count_entries_total.
    result = lines( mt_db ).
  ENDMETHOD.

  METHOD z2ui5_if_ui5_draft_store~create.

    DELETE mt_db WHERE id = draft-id.
    INSERT VALUE #( id                = draft-id
                    id_prev           = draft-id_prev
                    id_prev_app       = draft-id_prev_app
                    id_prev_app_stack = draft-id_prev_app_stack
                    data              = model_xml ) INTO TABLE mt_db.

  ENDMETHOD.

  METHOD z2ui5_if_ui5_draft_store~read_draft.

    READ TABLE mt_db INTO result WITH KEY id = id. "#EC CI_SORTSEQ
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE z2ui5_cx_ui5_util_error
        EXPORTING val = `NO_DRAFT_ENTRY_OF_PREVIOUS_REQUEST_FOUND`.
    ENDIF.

  ENDMETHOD.

  METHOD z2ui5_if_ui5_draft_store~read_info.

    DATA(ls_db) = z2ui5_if_ui5_draft_store~read_draft( id ).
    result = VALUE #( id                = ls_db-id
                      id_prev           = ls_db-id_prev
                      id_prev_app       = ls_db-id_prev_app
                      id_prev_app_stack = ls_db-id_prev_app_stack ).

  ENDMETHOD.

  METHOD z2ui5_if_ui5_draft_store~check_exists.
    result = xsdbool( line_exists( mt_db[ id = id ] ) ). "#EC CI_SORTSEQ
  ENDMETHOD.

  METHOD z2ui5_if_ui5_draft_store~cleanup.
    " nothing expires within a test
  ENDMETHOD.

ENDCLASS.


CLASS ltcl_frontend_simulator DEFINITION FINAL
  FOR TESTING RISK LEVEL HARMLESS DURATION MEDIUM.

  PRIVATE SECTION.
    DATA mo_store TYPE REF TO ltd_draft_store.

    METHODS setup.
    METHODS teardown.

    METHODS start_renders_view    FOR TESTING.
    METHODS input_and_click       FOR TESTING.
    METHODS fluent_chaining       FOR TESTING.
    METHODS clear_event           FOR TESTING.
    METHODS unknown_app_raises    FOR TESTING.
    METHODS draft_path_uses_store FOR TESTING.
    METHODS messages_kept         FOR TESTING.
    METHODS message_box_severity  FOR TESTING.
    METHODS popup_flow                FOR TESTING.
    METHODS popup_cancel              FOR TESTING.
    METHODS popover_anchor            FOR TESTING.
    METHODS nested_view               FOR TESTING.
    METHODS main_display_closes_popup FOR TESTING.
    METHODS app_switch                FOR TESTING.
    METHODS follow_up_action          FOR TESTING.
    METHODS nav_app_state             FOR TESTING.
    METHODS table_cell_delta          FOR TESTING.
    METHODS row_event_arg             FOR TESTING.
    METHODS events_wired              FOR TESTING.
    METHODS strict_click              FOR TESTING.
    METHODS resume_with_state         FOR TESTING.
    METHODS resume_without_state      FOR TESTING.
    METHODS resume_refresh            FOR TESTING.
    METHODS resume_errors             FOR TESTING.
    METHODS sticky_session            FOR TESTING.
ENDCLASS.


CLASS ltcl_frontend_simulator IMPLEMENTATION.

  METHOD setup.

    mo_store = NEW #( ).
    z2ui5_cl_ui5_srv_draft=>set_instance( mo_store ).

  ENDMETHOD.

  METHOD teardown.

    " an unbound reference restores the shipped store
    DATA li_default TYPE REF TO z2ui5_if_ui5_draft_store.
    z2ui5_cl_ui5_srv_draft=>set_instance( li_default ).

  ENDMETHOD.

  METHOD start_renders_view.

    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_EXAMPLE` ).

    " a draft id was minted (would be sent back on the next request)
    cl_abap_unit_assert=>assert_not_initial( lo_sim->get_id( ) ).

    " the rendered view carries the app's input field and Greet button
    cl_abap_unit_assert=>assert_true( xsdbool( lo_sim->get_view( ) CS `Input` ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( lo_sim->get_view( ) CS `Greet` ) ).

    " no message on a plain start
    cl_abap_unit_assert=>assert_initial( lo_sim->get_message( ) ).

  ENDMETHOD.

  METHOD input_and_click.

    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_EXAMPLE` ).

    lo_sim->set_value( name  = `MV_NAME`
                       value = `World` ).
    lo_sim->click( `GREET` ).

    " the value travelled to the server, the event ran, the toast came back
    cl_abap_unit_assert=>assert_equals( exp = `Hello World!`
                                        act = lo_sim->get_message( ) ).

    " and the recomputed model field is readable
    cl_abap_unit_assert=>assert_equals( exp = `Hello World!`
                                        act = lo_sim->get_value( `MV_GREETING` ) ).

  ENDMETHOD.

  METHOD fluent_chaining.

    DATA(lv_msg) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_EXAMPLE`
        )->set_value( name  = `MV_NAME`
                      value = `Bob`
        )->click( `GREET`
        )->get_message( ).

    cl_abap_unit_assert=>assert_equals( exp = `Hello Bob!`
                                        act = lv_msg ).

  ENDMETHOD.

  METHOD clear_event.

    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_EXAMPLE` ).

    lo_sim->set_value( name  = `MV_NAME`
                       value = `World` ).
    lo_sim->click( `GREET` ).
    lo_sim->click( `CLEAR` ).

    " CLEAR reset both bound fields, and the empty model round-tripped back
    cl_abap_unit_assert=>assert_initial( lo_sim->get_value( `MV_NAME` ) ).
    cl_abap_unit_assert=>assert_initial( lo_sim->get_value( `MV_GREETING` ) ).

  ENDMETHOD.

  METHOD unknown_app_raises.

    " a wrong app name must surface as a framework error, not a dump
    TRY.
        z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_APP_DOES_NOT_EXIST` ).
        cl_abap_unit_assert=>fail( `expected an error for an unknown app` ).
      CATCH z2ui5_cx_ui5_util_error ##NO_HANDLER.
    ENDTRY.

  ENDMETHOD.

  METHOD draft_path_uses_store.

    " the example app is not sticky: every roundtrip persists a draft, and
    " the next one restores the app from it - through the in-memory store
    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_EXAMPLE` ).
    DATA(lv_first) = lo_sim->get_id( ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( mo_store->mt_db[ id = lv_first ] ) ) ). "#EC CI_SORTSEQ

    lo_sim->set_value( name  = `MV_NAME`
                       value = `Draft` ).
    lo_sim->click( `GREET` ).

    cl_abap_unit_assert=>assert_differs( exp = lv_first
                                         act = lo_sim->get_id( ) ).
    DATA(lv_second) = lo_sim->get_id( ).
    READ TABLE mo_store->mt_db INTO DATA(ls_db) WITH KEY id = lv_second. "#EC CI_SORTSEQ
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( exp = lv_first
                                        act = CONV string( ls_db-id_prev ) ).

  ENDMETHOD.

  METHOD messages_kept.

    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_EXAMPLE` ).

    lo_sim->set_value( name  = `MV_NAME`
                       value = `A` ).
    lo_sim->click( `GREET` ).
    lo_sim->set_value( name  = `MV_NAME`
                       value = `B` ).
    lo_sim->click( `GREET` ).
    lo_sim->click( `CLEAR` ).

    " the history survives the roundtrip that produced no message ...
    DATA(lt_all) = lo_sim->get_messages( ).
    cl_abap_unit_assert=>assert_equals( exp = 2
                                        act = lines( lt_all ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Hello A!`
                                        act = lt_all[ 1 ]-text ).
    cl_abap_unit_assert=>assert_equals( exp = 2
                                        act = lt_all[ 1 ]-roundtrip ).
    cl_abap_unit_assert=>assert_equals( exp = `toast`
                                        act = lt_all[ 2 ]-source ).
    cl_abap_unit_assert=>assert_equals( exp = `info`
                                        act = lt_all[ 2 ]-type ).

    " ... while the convenience accessor only looks at the last one
    cl_abap_unit_assert=>assert_initial( lo_sim->get_message( ) ).
    cl_abap_unit_assert=>assert_initial( lo_sim->get_messages( abap_true ) ).
    cl_abap_unit_assert=>assert_equals( exp = 4
                                        act = lo_sim->get_roundtrip( ) ).

  ENDMETHOD.

  METHOD message_box_severity.

    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_LAYERS` ).
    lo_sim->click( `BOX` ).

    DATA(lt_msg) = lo_sim->get_messages( abap_true ).
    cl_abap_unit_assert=>assert_equals( exp = 1
                                        act = lines( lt_msg ) ).
    cl_abap_unit_assert=>assert_equals( exp = `box`
                                        act = lt_msg[ 1 ]-source ).
    cl_abap_unit_assert=>assert_equals( exp = `error`
                                        act = lt_msg[ 1 ]-type ).
    cl_abap_unit_assert=>assert_equals( exp = `error`
                                        act = lt_msg[ 1 ]-method ).
    cl_abap_unit_assert=>assert_equals( exp = `Failure`
                                        act = lt_msg[ 1 ]-title ).
    cl_abap_unit_assert=>assert_equals( exp = `Something went wrong`
                                        act = lo_sim->get_message( ) ).

  ENDMETHOD.


  METHOD popup_flow.

    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_LAYERS` ).
    lo_sim->set_value( name  = `MV_NAME`
                       value = `Ann` ).
    lo_sim->click( `POPUP_OPEN` ).

    " the dialog is the topmost layer now, the main view still underneath
    cl_abap_unit_assert=>assert_equals( exp = `POPUP`
                                        act = lo_sim->get_layer( ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( lo_sim->get_popup( ) CS `Dialog` ) ).
    cl_abap_unit_assert=>assert_equals( exp = lo_sim->get_popup( )
                                        act = lo_sim->get_view( ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( lo_sim->get_view( `MAIN` ) CS `Simulator Layers` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Ann`
                                        act = lo_sim->get_value( `MV_POPUP_TEXT` ) ).

    lo_sim->set_value( name  = `MV_POPUP_TEXT`
                       value = `Bea` ).
    lo_sim->click( `POPUP_CONFIRM` ).

    " closed again, the value travelled through the popup into the main model
    cl_abap_unit_assert=>assert_initial( lo_sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_equals( exp = `MAIN`
                                        act = lo_sim->get_layer( ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Bea`
                                        act = lo_sim->get_value( `MV_NAME` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Name set to Bea`
                                        act = lo_sim->get_message( ) ).

  ENDMETHOD.

  METHOD popup_cancel.

    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_LAYERS` ).
    lo_sim->set_value( name  = `MV_NAME`
                       value = `Ann` ).
    lo_sim->click( `POPUP_OPEN` ).
    lo_sim->set_value( name  = `MV_POPUP_TEXT`
                       value = `Bea` ).
    lo_sim->click( `POPUP_CANCEL` ).

    cl_abap_unit_assert=>assert_initial( lo_sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Ann`
                                        act = lo_sim->get_value( `MV_NAME` ) ).

  ENDMETHOD.

  METHOD popover_anchor.

    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_LAYERS` ).
    lo_sim->click( `POPOVER_OPEN` ).

    cl_abap_unit_assert=>assert_equals( exp = `POPOVER`
                                        act = lo_sim->get_layer( ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( lo_sim->get_popover( ) CS `Popover` ) ).
    DATA(lt_layer) = lo_sim->get_layers( ).
    READ TABLE lt_layer INTO DATA(ls_layer) WITH KEY layer = `POPOVER`. "#EC CI_SORTSEQ
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( exp = `btnPopover`
                                        act = ls_layer-anchor_id ).
    cl_abap_unit_assert=>assert_equals( exp = `Z2UI5_CL_FRONTEND_SIM_LAYERS`
                                        act = ls_layer-app ).

    lo_sim->click( `POPOVER_CLOSE` ).
    cl_abap_unit_assert=>assert_initial( lo_sim->get_popover( ) ).

  ENDMETHOD.

  METHOD nested_view.

    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_LAYERS` ).
    lo_sim->set_value( name  = `MV_NAME`
                       value = `Nest` ).
    lo_sim->click( `NEST_SHOW` ).

    " a nested view is part of the MAIN layer, not on top of it
    cl_abap_unit_assert=>assert_equals( exp = `MAIN`
                                        act = lo_sim->get_layer( ) ).
    DATA(lt_layer) = lo_sim->get_layers( ).
    cl_abap_unit_assert=>assert_equals( exp = 2
                                        act = lines( lt_layer ) ).
    cl_abap_unit_assert=>assert_equals( exp = `NEST`
                                        act = lt_layer[ 2 ]-layer ).
    cl_abap_unit_assert=>assert_equals( exp = `nestHost`
                                        act = lt_layer[ 2 ]-anchor_id ).
    " ... and it is bound against the model it inherits from MAIN
    cl_abap_unit_assert=>assert_equals( exp = lt_layer[ 1 ]-model
                                        act = lt_layer[ 2 ]-model ).
    cl_abap_unit_assert=>assert_equals( exp = `Nest`
                                        act = lo_sim->get_value( name  = `MV_NAME`
                                                                 layer = `NEST` ) ).

    lo_sim->click( `NEST_HIDE` ).
    cl_abap_unit_assert=>assert_initial( lo_sim->get_view( `NEST` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 1
                                        act = lines( lo_sim->get_layers( ) ) ).

  ENDMETHOD.

  METHOD main_display_closes_popup.

    " a new MAIN view is a new screen - the frontend takes open dialogs down
    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_LAYERS` ).
    lo_sim->click( `NEST_SHOW` ).
    lo_sim->click( `POPUP_OPEN` ).
    lo_sim->click( `REFRESH` ).

    cl_abap_unit_assert=>assert_initial( lo_sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_initial( lo_sim->get_view( `NEST` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `MAIN`
                                        act = lo_sim->get_layer( ) ).

  ENDMETHOD.

  METHOD app_switch.

    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_LAYERS` ).
    cl_abap_unit_assert=>assert_equals( exp = `Z2UI5_CL_FRONTEND_SIM_LAYERS`
                                        act = lo_sim->get_app( ) ).
    lo_sim->click( `POPUP_OPEN` ).

    " nav_app_call: the called app answers, the caller's dialog is gone
    lo_sim->click( `NAV` ).
    cl_abap_unit_assert=>assert_equals( exp = `Z2UI5_CL_FRONTEND_SIM_EXAMPLE`
                                        act = lo_sim->get_app( ) ).
    cl_abap_unit_assert=>assert_initial( lo_sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( lo_sim->get_view( ) CS `Simulator Example` ) ).

    lo_sim->set_value( name  = `MV_NAME`
                       value = `Nav` ).
    lo_sim->click( `GREET` ).
    cl_abap_unit_assert=>assert_equals( exp = `Hello Nav!`
                                        act = lo_sim->get_message( ) ).

  ENDMETHOD.

  METHOD follow_up_action.

    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_LAYERS` ).
    lo_sim->click( `FOCUS` ).

    DATA(lt_action) = lo_sim->get_actions( ).
    cl_abap_unit_assert=>assert_equals( exp = 1
                                        act = lines( lt_action ) ).
    cl_abap_unit_assert=>assert_equals( exp = `SET_FOCUS`
                                        act = lt_action[ 1 ]-name ).
    cl_abap_unit_assert=>assert_equals( exp = `inputName`
                                        act = lt_action[ 1 ]-t_arg[ 1 ] ).
    cl_abap_unit_assert=>assert_true( xsdbool( lt_action[ 1 ]-json CS `SET_FOCUS` ) ).

    " follow-up actions belong to one response
    lo_sim->click( `SUM` ).
    lt_action = lo_sim->get_actions( ).
    cl_abap_unit_assert=>assert_equals( exp = `MESSAGE_TOAST`
                                        act = lt_action[ 1 ]-name ).

  ENDMETHOD.

  METHOD nav_app_state.

    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_LAYERS` ).
    cl_abap_unit_assert=>assert_false( lo_sim->get_nav( )-set_app_state_active ).

    lo_sim->click( `APP_STATE` ).
    cl_abap_unit_assert=>assert_true( lo_sim->get_nav( )-set_app_state_active ).

    " the app keeps asking for it on every later response
    lo_sim->click( `SUM` ).
    cl_abap_unit_assert=>assert_true( lo_sim->get_nav( )-set_app_state_active ).

  ENDMETHOD.

  METHOD table_cell_delta.

    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_LAYERS` ).
    lo_sim->set_cell( table  = `MT_ITEM`
                      row    = 2
                      column = `QTY`
                      value  = `10` ).
    lo_sim->click( `SUM` ).

    " 1 + 10 + 3 - the row delta reached row 2 only
    cl_abap_unit_assert=>assert_equals( exp = `14`
                                        act = lo_sim->get_value( `MV_TOTAL` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `10`
                                        act = lo_sim->get_value( `MT_ITEM/2/QTY` ) ).

  ENDMETHOD.

  METHOD row_event_arg.

    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_LAYERS` ).
    lo_sim->click( event = `ROW`
                   t_arg = VALUE #( ( `Bananas` ) ) ).

    cl_abap_unit_assert=>assert_equals( exp = `Bananas`
                                        act = lo_sim->get_value( `MV_SELECTED` ) ).

  ENDMETHOD.

  METHOD events_wired.

    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_LAYERS` ).

    cl_abap_unit_assert=>assert_true( lo_sim->check_event_exists( `POPUP_OPEN` ) ).
    cl_abap_unit_assert=>assert_true( lo_sim->check_event_exists( `ROW` ) ).
    cl_abap_unit_assert=>assert_false( lo_sim->check_event_exists( `POPUP_CONFIRM` ) ).
    cl_abap_unit_assert=>assert_false( lo_sim->check_event_exists( `NEST_HIDE` ) ).

    " a nested view adds its events to the MAIN layer
    lo_sim->click( `NEST_SHOW` ).
    cl_abap_unit_assert=>assert_true( lo_sim->check_event_exists( `NEST_HIDE` ) ).
    cl_abap_unit_assert=>assert_true( lo_sim->check_event_exists( `SUM` ) ).

    " a dialog is modal: only its own events are reachable
    lo_sim->click( `POPUP_OPEN` ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `POPUP_CANCEL` ) ( `POPUP_CONFIRM` ) )
                                        act = lo_sim->get_events( ) ).
    cl_abap_unit_assert=>assert_false( lo_sim->check_event_exists( `SUM` ) ).

  ENDMETHOD.

  METHOD strict_click.

    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_EXAMPLE`
        )->set_check_events( ).

    TRY.
        lo_sim->click( `NOT_WIRED` ).
        cl_abap_unit_assert=>fail( `expected an error for an event that is not wired` ).
      CATCH z2ui5_cx_ui5_util_error INTO DATA(lx).
        cl_abap_unit_assert=>assert_true( xsdbool( lx->get_text( ) CS `GREET` ) ).
    ENDTRY.

    " the roundtrip did not happen, and a wired event still goes through
    cl_abap_unit_assert=>assert_equals( exp = 1
                                        act = lo_sim->get_roundtrip( ) ).
    lo_sim->set_value( name  = `MV_NAME`
                       value = `Strict` ).
    lo_sim->click( `GREET` ).
    cl_abap_unit_assert=>assert_equals( exp = `Hello Strict!`
                                        act = lo_sim->get_message( ) ).

  ENDMETHOD.

  METHOD resume_with_state.

    " request 1: start, open the popup, hand over id and state
    DATA(lo_first) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_LAYERS` ).
    lo_first->set_value( name  = `MV_NAME`
                         value = `Res` ).
    lo_first->click( `POPUP_OPEN` ).
    DATA(lv_id) = lo_first->get_id( ).
    DATA(lv_state) = lo_first->get_state( ).

    " request 2: a new instance continues where the first one stopped
    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>resume( id    = lv_id
                                                        state = lv_state ).
    cl_abap_unit_assert=>assert_equals( exp = lv_id
                                        act = lo_sim->get_id( ) ).
    cl_abap_unit_assert=>assert_equals( exp = `POPUP`
                                        act = lo_sim->get_layer( ) ).
    cl_abap_unit_assert=>assert_equals( exp = lo_first->get_popup( )
                                        act = lo_sim->get_popup( ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Z2UI5_CL_FRONTEND_SIM_LAYERS`
                                        act = lo_sim->get_app( ) ).
    cl_abap_unit_assert=>assert_equals( exp = 0
                                        act = lo_sim->get_roundtrip( ) ).

    lo_sim->set_check_events( ).
    lo_sim->set_value( name  = `MV_POPUP_TEXT`
                       value = `Resumed` ).
    lo_sim->click( `POPUP_CONFIRM` ).
    cl_abap_unit_assert=>assert_equals( exp = `Resumed`
                                        act = lo_sim->get_value( `MV_NAME` ) ).
    cl_abap_unit_assert=>assert_initial( lo_sim->get_popup( ) ).

  ENDMETHOD.

  METHOD resume_without_state.

    DATA(lo_first) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_EXAMPLE` ).
    lo_first->set_value( name  = `MV_NAME`
                         value = `Draft` ).
    lo_first->click( `GREET` ).

    " the draft knows the app and its model, not the view
    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>resume( lo_first->get_id( ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Z2UI5_CL_FRONTEND_SIM_EXAMPLE`
                                        act = lo_sim->get_app( ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Hello Draft!`
                                        act = lo_sim->get_value( `MV_GREETING` ) ).
    cl_abap_unit_assert=>assert_initial( lo_sim->get_view( ) ).
    cl_abap_unit_assert=>assert_initial( lo_sim->get_layers( ) ).

    lo_sim->set_value( name  = `MV_NAME`
                       value = `Again` ).
    lo_sim->click( `GREET` ).
    cl_abap_unit_assert=>assert_equals( exp = `Hello Again!`
                                        act = lo_sim->get_message( ) ).

  ENDMETHOD.

  METHOD resume_refresh.

    DATA(lo_first) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_EXAMPLE` ).
    lo_first->set_value( name  = `MV_NAME`
                         value = `Reload` ).
    lo_first->click( `GREET` ).
    DATA(lv_id) = lo_first->get_id( ).

    " the reload of a routed app: the draft is restored, check_on_navigated
    " re-displays the view - under a new draft id
    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>resume( id      = lv_id
                                                        refresh = abap_true ).
    cl_abap_unit_assert=>assert_true( xsdbool( lo_sim->get_view( ) CS `Greet` ) ).
    cl_abap_unit_assert=>assert_differs( exp = lv_id
                                         act = lo_sim->get_id( ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Reload`
                                        act = lo_sim->get_value( `MV_NAME` ) ).
    cl_abap_unit_assert=>assert_initial( lo_sim->get_message( ) ).

  ENDMETHOD.

  METHOD resume_errors.

    TRY.
        z2ui5_cl_frontend_simulator=>resume( `00000000000000000000000000000000` ).
        cl_abap_unit_assert=>fail( `expected an error for an unknown draft` ).
      CATCH z2ui5_cx_ui5_util_error INTO DATA(lx).
        cl_abap_unit_assert=>assert_true( xsdbool( lx->get_text( ) CS `RESUME_NO_DRAFT` ) ).
    ENDTRY.

    " a state of an older roundtrip does not fit the current draft
    DATA(lo_first) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_EXAMPLE` ).
    DATA(lv_state) = lo_first->get_state( ).
    lo_first->click( `CLEAR` ).
    TRY.
        z2ui5_cl_frontend_simulator=>resume( id    = lo_first->get_id( )
                                             state = lv_state ).
        cl_abap_unit_assert=>fail( `expected an error for a stale state` ).
      CATCH z2ui5_cx_ui5_util_error INTO lx.
        cl_abap_unit_assert=>assert_true( xsdbool( lx->get_text( ) CS `RESUME_STATE_STALE` ) ).
    ENDTRY.

  ENDMETHOD.

  METHOD sticky_session.

    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_LAYERS` ).
    cl_abap_unit_assert=>assert_false( lo_sim->is_sticky( ) ).
    lo_sim->click( `STICKY` ).
    cl_abap_unit_assert=>assert_true( lo_sim->is_sticky( ) ).

    " no draft behind the id - the session lives in this instance only ...
    cl_abap_unit_assert=>assert_false( xsdbool( line_exists( mo_store->mt_db[ id = lo_sim->get_id( ) ] ) ) ). "#EC CI_SORTSEQ
    lo_sim->set_cell( table  = `MT_ITEM`
                      row    = 1
                      column = `QTY`
                      value  = `5` ).
    lo_sim->click( `SUM` ).
    cl_abap_unit_assert=>assert_equals( exp = `10`
                                        act = lo_sim->get_value( `MV_TOTAL` ) ).

    " ... and cannot be resumed in another one
    TRY.
        z2ui5_cl_frontend_simulator=>resume( lo_sim->get_id( ) ).
        cl_abap_unit_assert=>fail( `expected an error for a sticky session` ).
      CATCH z2ui5_cx_ui5_util_error INTO DATA(lx).
        cl_abap_unit_assert=>assert_true( xsdbool( lx->get_text( ) CS `sticky` ) ).
    ENDTRY.

  ENDMETHOD.

ENDCLASS.


"! The draft path against the REAL store - Z2UI5_T_01 and its COMMITs -
"! which is what a production app runs, and therefore not HARMLESS. Every
"! draft a test creates is collected and deleted again in teardown.
CLASS ltcl_frontend_simulator_db DEFINITION FINAL
  FOR TESTING RISK LEVEL DANGEROUS DURATION MEDIUM.

  PRIVATE SECTION.
    DATA mt_id        TYPE string_table.
    DATA mv_marker_id TYPE string.

    METHODS teardown.

    METHODS track
      IMPORTING
        sim TYPE REF TO z2ui5_cl_frontend_simulator.

    METHODS marker_insert.

    METHODS marker_exists
      RETURNING
        VALUE(result) TYPE abap_bool.

    METHODS draft_persisted        FOR TESTING.
    METHODS rollback_before_main   FOR TESTING.
    METHODS sticky_skips_rollback  FOR TESTING.
    METHODS resume_across_requests FOR TESTING.
ENDCLASS.


CLASS ltcl_frontend_simulator_db IMPLEMENTATION.

  METHOD teardown.

    " whatever a test left in the LUW goes first, then the drafts it made
    ROLLBACK WORK.
    IF mv_marker_id IS NOT INITIAL.
      INSERT mv_marker_id INTO TABLE mt_id.
    ENDIF.
    LOOP AT mt_id INTO DATA(lv_id).
      DELETE FROM z2ui5_t_01 WHERE id = @lv_id.
    ENDLOOP.
    COMMIT WORK.

  ENDMETHOD.

  METHOD track.
    INSERT sim->get_id( ) INTO TABLE mt_id.
  ENDMETHOD.

  METHOD marker_insert.

    " an uncommitted row in the caller's LUW - what the framework's rollback
    " bracket around main( ) must discard in the draft path
    mv_marker_id = z2ui5_cl_ui5_util_context=>uuid_get_c32( ).
    DATA(ls_db) = VALUE z2ui5_t_01( id   = mv_marker_id
                                    data = `simulator rollback marker` ).
    INSERT z2ui5_t_01 FROM @ls_db.

  ENDMETHOD.

  METHOD marker_exists.

    SELECT SINGLE id FROM z2ui5_t_01
      WHERE id = @mv_marker_id
      INTO @DATA(lv_id).
    result = xsdbool( sy-subrc = 0 AND lv_id IS NOT INITIAL ).

  ENDMETHOD.

  METHOD draft_persisted.

    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_EXAMPLE` ).
    track( lo_sim ).
    lo_sim->set_value( name  = `MV_NAME`
                       value = `Db` ).
    lo_sim->click( `GREET` ).
    track( lo_sim ).

    cl_abap_unit_assert=>assert_equals( exp = `Hello Db!`
                                        act = lo_sim->get_message( ) ).

    DATA(lv_id) = lo_sim->get_id( ).
    SELECT SINGLE id_prev FROM z2ui5_t_01
      WHERE id = @lv_id
      INTO @DATA(lv_prev).
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( exp = mt_id[ 1 ]
                                        act = CONV string( lv_prev ) ).

  ENDMETHOD.

  METHOD rollback_before_main.

    " start( ) itself commits (draft cleanup + save), so the marker is
    " written afterwards - the click must roll it back before main( ) runs
    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_EXAMPLE` ).
    track( lo_sim ).
    marker_insert( ).
    cl_abap_unit_assert=>assert_true( marker_exists( ) ).

    lo_sim->click( `GREET` ).
    track( lo_sim ).

    cl_abap_unit_assert=>assert_false( marker_exists( ) ).

  ENDMETHOD.

  METHOD sticky_skips_rollback.

    " a sticky app keeps its handler and its LUW - no rollback, no save
    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_LAYERS` ).
    track( lo_sim ).
    lo_sim->click( `STICKY` ).
    track( lo_sim ).
    marker_insert( ).

    lo_sim->click( `SUM` ).
    track( lo_sim ).

    cl_abap_unit_assert=>assert_true( marker_exists( ) ).

  ENDMETHOD.

  METHOD resume_across_requests.

    " request 1
    DATA(lo_first) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_EXAMPLE` ).
    track( lo_first ).
    lo_first->set_value( name  = `MV_NAME`
                         value = `Persisted` ).
    lo_first->click( `GREET` ).
    track( lo_first ).
    DATA(lv_id) = lo_first->get_id( ).
    DATA(lv_state) = lo_first->get_state( ).
    CLEAR lo_first.

    " request 2 - nothing but the id and the state survived
    DATA(lo_sim) = z2ui5_cl_frontend_simulator=>resume( id    = lv_id
                                                        state = lv_state ).
    lo_sim->click( `GREET` ).
    track( lo_sim ).

    cl_abap_unit_assert=>assert_equals( exp = `Hello Persisted!`
                                        act = lo_sim->get_message( ) ).

  ENDMETHOD.

ENDCLASS.
