"! Third example app for z2ui5_cl_frontend_sim - typed edits.
"!
"! Where z2ui5_cl_frontend_example types text, this app exists for the
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
CLASS z2ui5_cl_frontend_form DEFINITION PUBLIC.

  PUBLIC SECTION.
    INTERFACES z2ui5_if_app.

    TYPES:
      BEGIN OF ty_s_pos,
        item TYPE string,
        qty  TYPE i,
      END OF ty_s_pos.
    TYPES ty_t_pos TYPE STANDARD TABLE OF ty_s_pos WITH DEFAULT KEY.

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
    TYPES ty_t_row TYPE STANDARD TABLE OF ty_s_row WITH DEFAULT KEY.

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


CLASS z2ui5_cl_frontend_form IMPLEMENTATION.

  METHOD z2ui5_if_app~main.
      DATA temp3 TYPE z2ui5_cl_frontend_form=>ty_t_pos.
      DATA temp4 LIKE LINE OF temp3.
      DATA temp1 TYPE z2ui5_cl_frontend_form=>ty_t_row.
      DATA temp2 LIKE LINE OF temp1.
      DATA temp5 TYPE z2ui5_cl_frontend_form=>ty_t_pos.
      DATA temp6 LIKE LINE OF temp5.
      DATA temp7 TYPE z2ui5_cl_frontend_form=>ty_t_pos.
      DATA temp8 LIKE LINE OF temp7.
      DATA temp9 TYPE z2ui5_cl_frontend_form=>ty_t_pos.
      DATA temp10 LIKE LINE OF temp9.

    me->client = client.

    IF client->check_on_init( ) IS NOT INITIAL.
      CLEAR ms_order.
      ms_order-name = `Order`.
      CLEAR ms_order-s_addr.
      ms_order-s_addr-city = `Paris`.

      CLEAR temp3.

      temp4-item = `Pen`.
      temp4-qty = 1.
      INSERT temp4 INTO TABLE temp3.
      temp4-item = `Ink`.
      temp4-qty = 2.
      INSERT temp4 INTO TABLE temp3.
      ms_order-t_pos = temp3.

      CLEAR temp1.

      temp2-name = `Anna`.
      temp2-qty = 1.

      CLEAR temp5.

      temp6-item = `a1`.
      temp6-qty = 10.
      INSERT temp6 INTO TABLE temp5.
      temp2-t_sub = temp5.
      INSERT temp2 INTO TABLE temp1.
      temp2-name = `Ben`.
      temp2-qty = 2.

      CLEAR temp7.

      temp8-item = `b1`.
      temp8-qty = 20.
      INSERT temp8 INTO TABLE temp7.
      temp2-t_sub = temp7.
      INSERT temp2 INTO TABLE temp1.
      temp2-name = `Carl`.
      temp2-qty = 3.

      CLEAR temp9.

      temp10-item = `c1`.
      temp10-qty = 30.
      INSERT temp10 INTO TABLE temp9.
      temp10-item = `c2`.
      temp10-qty = 31.
      INSERT temp10 INTO TABLE temp9.
      temp2-t_sub = temp9.
      INSERT temp2 INTO TABLE temp1.
      mt_row = temp1.
    ENDIF.

    on_event( ).

    IF client->check_on_navigated( ) IS NOT INITIAL.
      view_display( ).
    ENDIF.

  ENDMETHOD.


  METHOD on_event.

    DATA lv_qty TYPE i.
    DATA lv_sub TYPE i.
    DATA lt_name TYPE string_table.
        DATA temp3 TYPE string.
        DATA temp4 TYPE string.
        DATA ls_pos LIKE LINE OF ms_order-t_pos.
        DATA temp5 TYPE string.
        DATA ls_row LIKE LINE OF mt_row.
        DATA temp6 TYPE string.

    CASE client->get_event( ).

      WHEN `CHECK`.

        IF mv_active = abap_true.
          temp3 = `yes`.
        ELSE.
          temp3 = `no`.
        ENDIF.
        mv_result = |active { temp3 }|.

      WHEN `KEYS`.

        IF mt_key IS INITIAL.
          temp4 = `none`.
        ELSE.
          temp4 = concat_lines_of( table = mt_key sep = `,` ).
        ENDIF.
        mv_result = |keys { temp4 }|.

      WHEN `ORDER`.

        LOOP AT ms_order-t_pos INTO ls_pos.
          lv_qty = lv_qty + ls_pos-qty.
        ENDLOOP.

        IF ms_order-urgent = abap_true.
          temp5 = `urgent`.
        ELSE.
          temp5 = `normal`.
        ENDIF.
        mv_result = |{ ms_order-name } { temp5 } | &&
                    |{ ms_order-s_addr-city } positions { lines( ms_order-t_pos ) } qty { lv_qty }|.

      WHEN `ROWS`.

        LOOP AT mt_row INTO ls_row.
          IF ls_row-selkz = abap_true.
            INSERT ls_row-name INTO TABLE lt_name.
            lv_qty = lv_qty + ls_row-qty.
          ENDIF.
          LOOP AT ls_row-t_sub INTO ls_pos.
            lv_sub = lv_sub + ls_pos-qty.
          ENDLOOP.
        ENDLOOP.

        IF lt_name IS INITIAL.
          temp6 = `none`.
        ELSE.
          temp6 = concat_lines_of( table = lt_name sep = `,` ).
        ENDIF.
        mv_result = |selected { temp6 } qty { lv_qty } sub { lv_sub }|.

      WHEN OTHERS.
        RETURN.

    ENDCASE.

    client->message_toast_display( mv_result ).

  ENDMETHOD.


  METHOD view_display.

    DATA view TYPE REF TO z2ui5_cl_ui5_view_builder.
    view = z2ui5_cl_ui5_view_builder=>factory( ).

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
