CLASS zcl_sto_step_base DEFINITION
  PUBLIC
  ABSTRACT
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_sto_process_step ABSTRACT METHODS execute.

  PROTECTED SECTION.

    "! Technical name of this step - set by each subclass's constructor so
    "! the base class can find its own customizing row.
    DATA mv_step_name TYPE zsto_step_name.

    METHODS read_step_customizing
      IMPORTING iv_step_name   TYPE zsto_step_name
      RETURNING VALUE(rs_cust) TYPE zsto_stepcust.

    "! delivery item -> process item, from the step-3 mapping rows that the
    "! engine already persisted in a PREVIOUS LUW. Reading is always legal.
    METHODS read_delivery_item_map
      IMPORTING iv_process_uuid TYPE sysuuid_x16
      RETURNING VALUE(rt_map)   TYPE zif_sto_process_step=>tt_item_doc_map.

    "! Appends an informational message to a step result.
    METHODS add_warning
      IMPORTING iv_text   TYPE string
      CHANGING  cs_result TYPE zif_sto_process_step=>ty_step_result.

ENDCLASS.


CLASS zcl_sto_step_base IMPLEMENTATION.

  METHOD read_step_customizing.
    SELECT SINGLE * FROM zsto_stepcust
      WHERE step_name = @iv_step_name
        AND is_active = @abap_true
      INTO @rs_cust.
  ENDMETHOD.


  METHOD read_delivery_item_map.
    SELECT process_item, document_number, document_item, quantity, base_unit
      FROM zsto_proc_idoc
      WHERE process_uuid = @iv_process_uuid
        AND step_name    = @zif_sto_process_step=>gc_step_name-delivery
      INTO CORRESPONDING FIELDS OF TABLE @rt_map.
  ENDMETHOD.


  METHOD add_warning.
    APPEND VALUE bapiret2( type    = 'W'
                           id      = 'ZSTO'
                           number  = '002'
                           message = iv_text ) TO cs_result-messages.
  ENDMETHOD.

  METHOD zif_sto_process_step~is_applicable.

    rv_applicable = abap_true.

    IF mv_step_name IS INITIAL.
      RETURN.
    ENDIF.

    DATA(ls_cust) = read_step_customizing( mv_step_name ).

    IF ls_cust-only_intercompany = abap_true
       AND is_header-IsIntercompany <> abap_true.
      rv_applicable = abap_false.
      RETURN.
    ENDIF.

    IF ls_cust-only_intracompany = abap_true
       AND is_header-IsIntercompany = abap_true.
      rv_applicable = abap_false.
    ENDIF.

  ENDMETHOD.

ENDCLASS.


