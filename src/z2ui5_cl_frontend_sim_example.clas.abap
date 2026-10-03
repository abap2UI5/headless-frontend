"! Example app for z2ui5_cl_frontend_simulator.
"!
"! A minimal, self-contained abap2UI5 app - one input, one output text and two
"! buttons - that exists purely to be driven by the headless simulator. Its
"! unit tests (in z2ui5_cl_frontend_simulator.clas.testclasses) show how a
"! full user session - type a name, press a button, read the result back - is
"! reproduced on the server without a browser.
"!
"! Bound names an external driver addresses it by:
"!   MV_NAME     - the input value      ( _bind )
"!   MV_GREETING - the output text      ( _bind )
"!   GREET       - build+show greeting  ( _event )
"!   CLEAR       - reset both fields    ( _event )
CLASS z2ui5_cl_frontend_sim_example DEFINITION PUBLIC.

  PUBLIC SECTION.
    INTERFACES z2ui5_if_app.

    DATA mv_name     TYPE string.
    DATA mv_greeting TYPE string.

  PROTECTED SECTION.
    DATA client TYPE REF TO z2ui5_if_client.

    METHODS view_display.

  PRIVATE SECTION.
ENDCLASS.


CLASS z2ui5_cl_frontend_sim_example IMPLEMENTATION.

  METHOD z2ui5_if_app~main.

    me->client = client.

    CASE client->get_event( ).
      WHEN `GREET`.
        mv_greeting = |Hello { mv_name }!|.
        client->message_toast_display( mv_greeting ).

      WHEN `CLEAR`.
        CLEAR mv_name.
        CLEAR mv_greeting.
    ENDCASE.

    " the canonical display branch: true on the first start and whenever the
    " app is reached again (navigation, a restored draft) - see the
    " build-an-app guide of abap2UI5. Bound changes of an event roundtrip
    " reach the view through the automatic model update
    IF client->check_on_navigated( ).
      view_display( ).
    ENDIF.

  ENDMETHOD.


  METHOD view_display.

    DATA(view) = z2ui5_cl_ui5_view_builder=>factory( ).

    view->ele( n = `View` ns = `mvc`
        )->a( n = `xmlns`     v = `sap.m`
        )->a( n = `xmlns:mvc` v = `sap.ui.core.mvc`

        )->ele( `Page`
            )->a( n = `title` v = `Simulator Example`

            )->ele( `content`
                )->ele( `VBox`
                    )->a( n = `class` v = `sapUiContentPadding`

                    )->tag( `Input`
                        )->a( n = `value`       v = client->_bind( mv_name )
                        )->a( n = `placeholder` v = `Enter your name`
                    )->tag( `Text`
                        )->a( n = `text`  v = client->_bind( mv_greeting )
                        )->a( n = `class` v = `sapUiSmallMarginTop`
                    )->tag( `Button`
                        )->a( n = `text`  v = `Greet`
                        )->a( n = `press` v = client->_event( `GREET` )
                    )->tag( `Button`
                        )->a( n = `text`  v = `Clear`
                        )->a( n = `press` v = client->_event( `CLEAR` ) ).

    client->view_display( view->stringify( ) ).

  ENDMETHOD.

ENDCLASS.
