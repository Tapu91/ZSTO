CLASS zcl_sto_step_delivery DEFINITION
  PUBLIC
  INHERITING FROM zcl_sto_step_base
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor.
    METHODS zif_sto_process_step~execute REDEFINITION.

ENDCLASS.


CLASS zcl_sto_step_delivery IMPLEMENTATION.

  METHOD constructor.
    super->constructor( ).
    mv_step_name = zif_sto_process_step=>gc_step_name-delivery.
  ENDMETHOD.


  METHOD zif_sto_process_step~execute.

*    DATA ls_poheader  TYPE bapimepoheader.
*    DATA ls_poheaderx TYPE bapimepoheaderx.
*    DATA lt_poitem    TYPE STANDARD TABLE OF bapimepoitem.
*    DATA lt_poitemx   TYPE STANDARD TABLE OF bapimepoitemx.
*    DATA lt_posched   TYPE STANDARD TABLE OF bapimeposchedule.
*    DATA lt_poschedx  TYPE STANDARD TABLE OF bapimeposchedulx.
*    DATA lt_return    TYPE bapiret2_t.
*    DATA lv_po        TYPE bapimepoheader-po_number.
*
*    "--- Header -------------------------------------------------------------
*    ls_poheader-doc_type   = COND #( WHEN is_header-po_doc_type IS NOT INITIAL
*                                     THEN is_header-po_doc_type
*                                     ELSE 'UB' ).          " standard STO type
*    ls_poheader-comp_code  = is_header-comp_code.
*    ls_poheader-purch_org  = is_header-purch_org.
*    ls_poheader-pur_group  = is_header-purch_group.
*    ls_poheader-suppl_plnt = is_header-from_plant.          " supplying plant
*    ls_poheader-doc_date   = sy-datum.
*
*    ls_poheaderx-doc_type   = abap_true.
*    ls_poheaderx-comp_code  = abap_true.
*    ls_poheaderx-purch_org  = abap_true.
*    ls_poheaderx-pur_group  = abap_true.
*    ls_poheaderx-suppl_plnt = abap_true.
*    ls_poheaderx-doc_date   = abap_true.
*
*    "--- Items: PO item number == process item number -----------------------
*    LOOP AT it_item ASSIGNING FIELD-SYMBOL(<ls_item>).
*
*      DATA(lv_po_item) = CONV bapimepoitem-po_item( <ls_item>-process_item ).
*
*      APPEND VALUE #( po_item   = lv_po_item
*                      material  = <ls_item>-material
*                      plant     = is_header-to_plant       " receiving plant
*                      stge_loc  = is_header-to_stor_loc
*                      quantity  = <ls_item>-quantity
*                      po_unit   = <ls_item>-base_unit
*                      batch     = <ls_item>-batch
*                    ) TO lt_poitem.
*
*      APPEND VALUE #( po_item   = lv_po_item
*                      po_itemx  = abap_true
*                      material  = abap_true
*                      plant     = abap_true
*                      stge_loc  = abap_true
*                      quantity  = abap_true
*                      po_unit   = abap_true
*                      batch     = abap_true
*                    ) TO lt_poitemx.
*
*      APPEND VALUE #( po_item   = lv_po_item
*                      sched_line = '0001'
*                      delivery_date = is_header-transfer_date
*                      quantity  = <ls_item>-quantity
*                    ) TO lt_posched.
*
*      APPEND VALUE #( po_item   = lv_po_item
*                      sched_line = '0001'
*                      po_itemx  = abap_true
*                      sched_linex = abap_true
*                      delivery_date = abap_true
*                      quantity  = abap_true
*                    ) TO lt_poschedx.
*    ENDLOOP.
*
*    IF lt_poitem IS INITIAL.
*      RAISE EXCEPTION NEW zcx_sto_step_error(
*        step_name = zif_sto_process_step=>gc_step_name-po
*        text      = |No items to transfer| ).
*    ENDIF.
*
*    "--- Call ---------------------------------------------------------------
*    CALL FUNCTION 'BAPI_PO_CREATE1'
*      EXPORTING
*        poheader         = ls_poheader
*        poheaderx        = ls_poheaderx
*      IMPORTING
*        exppurchaseorder = lv_po
*      TABLES
*        return           = lt_return
*        poitem           = lt_poitem
*        poitemx          = lt_poitemx
*        poschedule       = lt_posched
*        poschedulex      = lt_poschedx.
*
*    IF zcx_sto_step_error=>has_error( lt_return ) = abap_true OR lv_po IS INITIAL.
*      rollback_bapi( ).
*      RAISE EXCEPTION NEW zcx_sto_step_error(
*        step_name = zif_sto_process_step=>gc_step_name-po
*        bapiret   = lt_return ).
*    ENDIF.
*
*    commit_bapi( ).

    "--- Result + mapping ---------------------------------------------------
    " Trivial here: document item == process item, by construction.
    DATA(lv_po) = '2000000001'.
    rs_result-document_number = lv_po.
    rs_result-document_date   = sy-datum.
*    rs_result-messages        = lt_return.

    LOOP AT it_item ASSIGNING FIELD-SYMBOL(<ls_item>).
      APPEND VALUE #( process_item    = <ls_item>-ProcessItem
                      document_number = lv_po
                      document_item   = <ls_item>-ProcessItem
                      quantity        = <ls_item>-quantity
                      base_unit       = <ls_item>-baseunit
                    ) TO rs_result-item_mapping.
    ENDLOOP.



  ENDMETHOD.

ENDCLASS.


