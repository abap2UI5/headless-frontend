"! Second example app for z2ui5_cl_frontend_simulator - every view layer.
"!
"! Where z2ui5_cl_frontend_sim_example is the minimal session, this app
"! exists to exercise the parts of the protocol a realistic app uses: a
"! popup with its own input, a popover anchored to a button, a nested view
"! inserted into the main view, a follow-up action, a message box with a
"! type, an editable table (row deltas), the app-state hash, an app-to-app
"! navigation and the switch to a stateful (sticky) session.
"!
"! Bound names an external driver addresses it by:
"!   MV_NAME       - the input of the main view       ( _bind )
"!   MV_POPUP_TEXT - the input of the popup           ( _bind )
"!   MT_ITEM       - table NAME / QTY, QTY editable   ( _bind )
"!   MV_TOTAL      - sum of MT_ITEM-QTY after SUM     ( _bind )
"!   MV_SELECTED   - NAME of the row pressed by ROW   ( _bind )
"! Events: POPUP_OPEN, POPUP_CONFIRM, POPUP_CANCEL, POPOVER_OPEN,
"! POPOVER_CLOSE, NEST_SHOW, NEST_HIDE, FOCUS, BOX, SUM, ROW, REFRESH,
"! APP_STATE, STICKY, NAV.
CLASS z2ui5_cl_frontend_sim_layers DEFINITION PUBLIC.

  PUBLIC SECTION.
    INTERFACES z2ui5_if_app.

    TYPES:
      BEGIN OF ty_s_item,
        name TYPE string,
        qty  TYPE i,
      END OF ty_s_item.
    TYPES ty_t_item TYPE STANDARD TABLE OF ty_s_item WITH EMPTY KEY.

    DATA mv_name       TYPE string.
    DATA mv_popup_text TYPE string.
    DATA mt_item       TYPE ty_t_item.
    DATA mv_total      TYPE i.
    DATA mv_selected   TYPE string.

  PROTECTED SECTION.
    DATA client TYPE REF TO z2ui5_if_client.

    METHODS on_event.
    METHODS view_display.
    METHODS popup_display.
    METHODS popover_display.
    METHODS nest_display.

  PRIVATE SECTION.
ENDCLASS.


CLASS z2ui5_cl_frontend_sim_layers IMPLEMENTATION.

  METHOD z2ui5_if_app~main.

    me->client = client.

    IF client->check_on_init( ).
      mt_item = VALUE #( ( name = `Apples`  qty = 1 )
                         ( name = `Bananas` qty = 2 )
                         ( name = `Cherries` qty = 3 ) ).
    ENDIF.

    on_event( ).

    IF client->check_on_navigated( ).
      view_display( ).
    ENDIF.

  ENDMETHOD.


  METHOD on_event.

    CASE client->get_event( ).

      WHEN `POPUP_OPEN`.
        mv_popup_text = mv_name.
        popup_display( ).

      WHEN `POPUP_CONFIRM`.
        mv_name = mv_popup_text.
        client->popup_destroy( ).
        client->message_toast_display( |Name set to { mv_name }| ).

      WHEN `POPUP_CANCEL`.
        client->popup_destroy( ).

      WHEN `POPOVER_OPEN`.
        popover_display( ).

      WHEN `POPOVER_CLOSE`.
        client->popover_destroy( ).

      WHEN `NEST_SHOW`.
        nest_display( ).

      WHEN `NEST_HIDE`.
        client->nest_view_destroy( ).

      WHEN `FOCUS`.
        client->follow_up_action( val   = client->cs_event-set_focus
                                  t_arg = VALUE #( ( `inputName` ) ) ).

      WHEN `BOX`.
        client->message_box_display( text  = `Something went wrong`
                                     type  = `error`
                                     title = `Failure` ).

      WHEN `SUM`.
        mv_total = 0.
        LOOP AT mt_item INTO DATA(ls_item).
          mv_total = mv_total + ls_item-qty.
        ENDLOOP.
        client->message_toast_display( |Total { mv_total }| ).

      WHEN `ROW`.
        mv_selected = client->get_event_arg( ).

      WHEN `REFRESH`.
        view_display( ).

      WHEN `APP_STATE`.
        client->app_state_set_active( ).

      WHEN `STICKY`.
        client->set_session_stateful( ).

      WHEN `NAV`.
        client->nav_app_call( NEW z2ui5_cl_frontend_sim_example( ) ).

    ENDCASE.

  ENDMETHOD.


  METHOD view_display.

    DATA(view) = z2ui5_cl_ui5_view_builder=>factory( ).

    view->ele( n = `View` ns = `mvc`
        )->a( n = `xmlns`     v = `sap.m`
        )->a( n = `xmlns:mvc` v = `sap.ui.core.mvc`

        )->ele( `Page`
            )->a( n = `title` v = `Simulator Layers`

            )->ele( `content`
                )->ele( `VBox`
                    )->a( n = `id`    v = `nestHost`
                    )->a( n = `class` v = `sapUiContentPadding`

                    )->tag( `Input`
                        )->a( n = `id`    v = `inputName`
                        )->a( n = `value` v = client->_bind( mv_name )
                    )->tag( `Button`
                        )->a( n = `text`  v = `Edit in popup`
                        )->a( n = `press` v = client->_event( `POPUP_OPEN` )
                    )->tag( `Button`
                        )->a( n = `id`    v = `btnPopover`
                        )->a( n = `text`  v = `More`
                        )->a( n = `press` v = client->_event( `POPOVER_OPEN` )
                    )->tag( `Button`
                        )->a( n = `text`  v = `Show details`
                        )->a( n = `press` v = client->_event( `NEST_SHOW` )
                    )->tag( `Button`
                        )->a( n = `text`  v = `Focus`
                        )->a( n = `press` v = client->_event( `FOCUS` )
                    )->tag( `Button`
                        )->a( n = `text`  v = `Fail`
                        )->a( n = `press` v = client->_event( `BOX` )
                    )->tag( `Button`
                        )->a( n = `text`  v = `Sum`
                        )->a( n = `press` v = client->_event( `SUM` )
                    )->tag( `Text`
                        )->a( n = `text` v = client->_bind( mv_total )

                    )->ele( `Table`
                        )->a( n = `items` v = client->_bind( mt_item )

                        )->ele( `columns`
                            )->ele( `Column`
                                )->tag( `Text`
                                    )->a( n = `text` v = `Name`
                            )->end(
                            )->ele( `Column`
                                )->tag( `Text`
                                    )->a( n = `text` v = `Quantity`
                            )->end(
                        )->end(
                        )->ele( `items`
                            )->ele( `ColumnListItem`
                                )->a( n = `type`  v = `Navigation`
                                )->a( n = `press` v = client->_event( val   = `ROW`
                                                                      t_arg = VALUE #( ( `${NAME}` ) ) )

                                )->ele( `cells`
                                    )->tag( `Text`
                                        )->a( n = `text` v = `{NAME}`
                                    )->tag( `Input`
                                        )->a( n = `value` v = `{QTY}` ).

    client->view_display( view->stringify( ) ).

  ENDMETHOD.


  METHOD popup_display.

    DATA(popup) = z2ui5_cl_ui5_view_builder=>factory( ).

    popup->ele( n = `FragmentDefinition` ns = `core`
        )->a( n = `xmlns`      v = `sap.m`
        )->a( n = `xmlns:core` v = `sap.ui.core`

        )->ele( `Dialog`
            )->a( n = `title` v = `Edit name`

            )->ele( `content`
                )->tag( `Input`
                    )->a( n = `value` v = client->_bind( mv_popup_text )
            )->end(
            )->ele( `buttons`
                )->tag( `Button`
                    )->a( n = `text`  v = `Cancel`
                    )->a( n = `press` v = client->_event( `POPUP_CANCEL` )
                )->tag( `Button`
                    )->a( n = `text`  v = `OK`
                    )->a( n = `type`  v = `Emphasized`
                    )->a( n = `press` v = client->_event( `POPUP_CONFIRM` ) ).

    client->popup_display( popup->stringify( ) ).

  ENDMETHOD.


  METHOD popover_display.

    DATA(popover) = z2ui5_cl_ui5_view_builder=>factory( ).

    popover->ele( n = `FragmentDefinition` ns = `core`
        )->a( n = `xmlns`      v = `sap.m`
        )->a( n = `xmlns:core` v = `sap.ui.core`

        )->ele( `Popover`
            )->a( n = `title` v = `More`

            )->tag( `Text`
                )->a( n = `text` v = client->_bind( mv_name )
            )->tag( `Button`
                )->a( n = `text`  v = `Close`
                )->a( n = `press` v = client->_event( `POPOVER_CLOSE` ) ).

    client->popover_display( xml   = popover->stringify( )
                             by_id = `btnPopover` ).

  ENDMETHOD.


  METHOD nest_display.

    DATA(nest) = z2ui5_cl_ui5_view_builder=>factory( ).

    nest->ele( n = `View` ns = `mvc`
        )->a( n = `xmlns`     v = `sap.m`
        )->a( n = `xmlns:mvc` v = `sap.ui.core.mvc`

        )->ele( `VBox`
            )->tag( `Text`
                )->a( n = `text` v = client->_bind( mv_name )
            )->tag( `Button`
                )->a( n = `text`  v = `Hide details`
                )->a( n = `press` v = client->_event( `NEST_HIDE` ) ).

    client->nest_view_display( val            = nest->stringify( )
                               id             = `nestHost`
                               method_insert  = `addItem`
                               method_destroy = `removeAllItems` ).

  ENDMETHOD.

ENDCLASS.
