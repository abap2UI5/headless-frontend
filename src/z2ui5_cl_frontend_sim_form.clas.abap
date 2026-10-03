"! Third example app for z2ui5_cl_frontend_simulator - typed edits.
"!
"! Where z2ui5_cl_frontend_sim_example types text, this app exists for the
"! values a browser sends as something else: a CheckBox sends a boolean, a
"! MultiComboBox an array of keys, a structure that holds a table travels
"! as one whole value, and a selectable table writes its selection into a
"! column of its rows - next to a nested table inside the rows.
"!
"! Bound names an external driver addresses it by:
"!   MV_ACTIVE        - CheckBox                             ( _bind )
"!   MT_KEY           - MultiComboBox selectedKeys, A B C    ( _bind )
"!   MS_ORDER         - NAME, URGENT, S_ADDR-CITY and the
"!                      table T_POS (ITEM, QTY editable)     ( _bind )
"!   MT_ROW           - SELKZ (selected), NAME, QTY, and the
"!                      nested table T_SUB (ITEM, QTY)       ( _bind )
"!   MV_RESULT        - what the last event computed        ( _bind )
"! Events: CHECK, KEYS, ORDER, ROWS - each writes MV_RESULT and shows it
"! as a toast.
CLASS z2ui5_cl_frontend_sim_form DEFINITION PUBLIC.

  PUBLIC SECTION.
    INTERFACES z2ui5_if_app.

    TYPES:
      BEGIN OF ty_s_pos,
        item TYPE string,
        qty  TYPE i,
      END OF ty_s_pos.
    TYPES ty_t_pos TYPE STANDARD TABLE OF ty_s_pos WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_s_addr,
        city TYPE string,
      END OF ty_s_addr.

    TYPES:
      BEGIN OF ty_s_order,
        name   TYPE string,
        urgent TYPE abap_bool,
        s_addr TYPE ty_s_addr,
        t_pos  TYPE ty_t_pos,
      END OF ty_s_order.

    TYPES:
      BEGIN OF ty_s_row,
        selkz TYPE abap_bool,
        name  TYPE string,
        qty   TYPE i,
        t_sub TYPE ty_t_pos,
      END OF ty_s_row.
    TYPES ty_t_row TYPE STANDARD TABLE OF ty_s_row WITH EMPTY KEY.

    DATA mv_active TYPE abap_bool.
    DATA mt_key    TYPE string_table.
    DATA ms_order  TYPE ty_s_order.
    DATA mt_row    TYPE ty_t_row.
    DATA mv_result TYPE string.

  PROTECTED SECTION.
    DATA client TYPE REF TO z2ui5_if_client.

    METHODS on_event.
    METHODS view_display.

  PRIVATE SECTION.
ENDCLASS.


CLASS z2ui5_cl_frontend_sim_form IMPLEMENTATION.

  METHOD z2ui5_if_app~main.

    me->client = client.

    IF client->check_on_init( ).
      ms_order = VALUE #( name   = `Order`
                          s_addr = VALUE #( city = `Paris` )
                          t_pos  = VALUE #( ( item = `Pen` qty = 1 )
                                            ( item = `Ink` qty = 2 ) ) ).
      mt_row = VALUE #( ( name  = `Anna`
                          qty   = 1
                          t_sub = VALUE #( ( item = `a1` qty = 10 ) ) )
                        ( name  = `Ben`
                          qty   = 2
                          t_sub = VALUE #( ( item = `b1` qty = 20 ) ) )
                        ( name  = `Carl`
                          qty   = 3
                          t_sub = VALUE #( ( item = `c1` qty = 30 )
                                           ( item = `c2` qty = 31 ) ) ) ).
    ENDIF.

    on_event( ).

    IF client->check_on_navigated( ).
      view_display( ).
    ENDIF.

  ENDMETHOD.


  METHOD on_event.

    DATA lv_qty TYPE i.
    DATA lv_sub TYPE i.
    DATA lt_name TYPE string_table.

    CASE client->get_event( ).

      WHEN `CHECK`.
        mv_result = |active { COND #( WHEN mv_active = abap_true THEN `yes` ELSE `no` ) }|.

      WHEN `KEYS`.
        mv_result = |keys { COND #( WHEN mt_key IS INITIAL THEN `none`
                                    ELSE concat_lines_of( table = mt_key
                                                          sep   = `,` ) ) }|.

      WHEN `ORDER`.
        LOOP AT ms_order-t_pos INTO DATA(ls_pos).
          lv_qty = lv_qty + ls_pos-qty.
        ENDLOOP.
        mv_result = |{ ms_order-name } { COND #( WHEN ms_order-urgent = abap_true THEN `urgent` ELSE `normal` ) } | &&
                    |{ ms_order-s_addr-city } positions { lines( ms_order-t_pos ) } qty { lv_qty }|.

      WHEN `ROWS`.
        LOOP AT mt_row INTO DATA(ls_row).
          IF ls_row-selkz = abap_true.
            INSERT ls_row-name INTO TABLE lt_name.
            lv_qty = lv_qty + ls_row-qty.
          ENDIF.
          LOOP AT ls_row-t_sub INTO ls_pos.
            lv_sub = lv_sub + ls_pos-qty.
          ENDLOOP.
        ENDLOOP.
        mv_result = |selected { COND #( WHEN lt_name IS INITIAL THEN `none`
                                        ELSE concat_lines_of( table = lt_name
                                                              sep   = `,` ) ) } qty { lv_qty } sub { lv_sub }|.

      WHEN OTHERS.
        RETURN.

    ENDCASE.

    client->message_toast_display( mv_result ).

  ENDMETHOD.


  METHOD view_display.

    DATA(view) = z2ui5_cl_ui5_view_builder=>factory( ).

    view->ele( n = `View` ns = `mvc`
        )->a( n = `xmlns`      v = `sap.m`
        )->a( n = `xmlns:mvc`  v = `sap.ui.core.mvc`
        )->a( n = `xmlns:core` v = `sap.ui.core`

        )->ele( `Page`
            )->a( n = `title` v = `Simulator Form`

            )->ele( `content`
                )->ele( `VBox`
                    )->a( n = `class` v = `sapUiContentPadding`

                    )->tag( `CheckBox`
                        )->a( n = `text`     v = `Active`
                        )->a( n = `selected` v = client->_bind( mv_active )

                    )->ele( `MultiComboBox`
                        )->a( n = `selectedKeys` v = client->_bind( mt_key )

                        )->tag( n = `Item` ns = `core`
                            )->a( n = `key`  v = `A`
                            )->a( n = `text` v = `Alpha`
                        )->tag( n = `Item` ns = `core`
                            )->a( n = `key`  v = `B`
                            )->a( n = `text` v = `Beta`
                        )->tag( n = `Item` ns = `core`
                            )->a( n = `key`  v = `C`
                            )->a( n = `text` v = `Gamma`

                    )->end(
                    )->tag( `Input`
                        )->a( n = `value` v = client->_bind( ms_order-name )
                    )->tag( `CheckBox`
                        )->a( n = `text`     v = `Urgent`
                        )->a( n = `selected` v = client->_bind( ms_order-urgent )
                    )->tag( `Input`
                        )->a( n = `value` v = client->_bind( ms_order-s_addr-city )

                    )->ele( `Table`
                        )->a( n = `items` v = client->_bind( ms_order-t_pos )

                        )->ele( `columns`
                            )->ele( `Column`

                                )->tag( `Text`
                                    )->a( n = `text` v = `Item`

                            )->end(
                            )->ele( `Column`

                                )->tag( `Text`
                                    )->a( n = `text` v = `Quantity`

                            )->end(
                        )->end(
                        )->ele( `items`
                            )->ele( `ColumnListItem`
                                )->ele( `cells`

                                    )->tag( `Text`
                                        )->a( n = `text` v = `{ITEM}`
                                    )->tag( `Input`
                                        )->a( n = `value` v = `{QTY}`

                                )->end(
                            )->end(
                        )->end(
                    )->end(

                    )->ele( `Table`
                        )->a( n = `mode`  v = `MultiSelect`
                        )->a( n = `items` v = client->_bind( mt_row )

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
                                )->a( n = `selected` v = `{SELKZ}`

                                )->ele( `cells`

                                    )->tag( `Text`
                                        )->a( n = `text` v = `{NAME}`
                                    )->tag( `Input`
                                        )->a( n = `value` v = `{QTY}`

                                )->end(
                            )->end(
                        )->end(
                    )->end(

                    )->tag( `Button`
                        )->a( n = `text`  v = `Check`
                        )->a( n = `press` v = client->_event( `CHECK` )
                    )->tag( `Button`
                        )->a( n = `text`  v = `Keys`
                        )->a( n = `press` v = client->_event( `KEYS` )
                    )->tag( `Button`
                        )->a( n = `text`  v = `Order`
                        )->a( n = `press` v = client->_event( `ORDER` )
                    )->tag( `Button`
                        )->a( n = `text`  v = `Rows`
                        )->a( n = `press` v = client->_event( `ROWS` )
                    )->tag( `Text`
                        )->a( n = `text` v = client->_bind( mv_result ) ).

    client->view_display( view->stringify( ) ).

  ENDMETHOD.

ENDCLASS.
