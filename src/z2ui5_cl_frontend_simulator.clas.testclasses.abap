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

ENDCLASS.
