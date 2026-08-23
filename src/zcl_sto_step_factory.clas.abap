CLASS zcl_sto_step_factory DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.

    TYPES: BEGIN OF ty_step_def,
             step_seq          TYPE zsto_step_seq,
             step_name         TYPE zsto_step_name,
             handler_class     TYPE zsto_step_class,
             status_on_success TYPE zsto_overall_status,
             handler           TYPE REF TO zif_sto_process_step,
           END OF ty_step_def,
           tt_step_def TYPE STANDARD TABLE OF ty_step_def WITH EMPTY KEY.

    CLASS-METHODS get_instance
      RETURNING VALUE(ro_instance) TYPE REF TO zcl_sto_step_factory.

    "! All active steps in sequence, handlers instantiated.
    METHODS get_all_steps
      RETURNING VALUE(rt_steps) TYPE tt_step_def
      RAISING   zcx_sto_step_error.

    "! One step by sequence number.
    METHODS get_step
      IMPORTING iv_step_seq    TYPE zsto_step_seq
      RETURNING VALUE(rs_step) TYPE ty_step_def
      RAISING   zcx_sto_step_error.

    "! The next step at or after IV_FROM_SEQ that is applicable to this
    "! process. Steps that opt out (e.g. Billing for intracompany) are
    "! returned in ET_SKIPPED so the engine can flag them in the step log.
    METHODS get_next_applicable_step
      IMPORTING is_header      TYPE zif_sto_process_step=>ty_header
                iv_from_seq    TYPE zsto_step_seq
      EXPORTING et_skipped     TYPE tt_step_def
      RETURNING VALUE(rs_step) TYPE ty_step_def
      RAISING   zcx_sto_step_error.

  PRIVATE SECTION.
    CLASS-DATA go_instance TYPE REF TO zcl_sto_step_factory.
    DATA mt_cache TYPE tt_step_def.

    METHODS instantiate
      IMPORTING iv_class          TYPE zsto_step_class
      RETURNING VALUE(ro_handler) TYPE REF TO zif_sto_process_step
      RAISING   zcx_sto_step_error.

ENDCLASS.


CLASS zcl_sto_step_factory IMPLEMENTATION.

  METHOD get_instance.
    IF go_instance IS NOT BOUND.
      go_instance = NEW #( ).
    ENDIF.
    ro_instance = go_instance.
  ENDMETHOD.


  METHOD get_all_steps.

    IF mt_cache IS NOT INITIAL.
      rt_steps = mt_cache.
      RETURN.
    ENDIF.

    SELECT step_seq, step_name, handler_class, status_on_success
      FROM zsto_stepcust
      WHERE is_active = @abap_true
      ORDER BY step_seq
      INTO CORRESPONDING FIELDS OF TABLE @rt_steps.

    IF rt_steps IS INITIAL.
      RAISE EXCEPTION NEW zcx_sto_step_error( text = |No active steps configured in ZSTO_STEPCUST| ).
    ENDIF.

    LOOP AT rt_steps ASSIGNING FIELD-SYMBOL(<ls_step>).
      " Step 1 (REQUEST) has no handler class - it is completed by the
      " initial save, not by a BAPI call.
      IF <ls_step>-handler_class IS NOT INITIAL.
        <ls_step>-handler = instantiate( <ls_step>-handler_class ).
      ENDIF.
    ENDLOOP.

    mt_cache = rt_steps.

  ENDMETHOD.


  METHOD get_step.

    DATA(lt_steps) = get_all_steps( ).

    rs_step = VALUE #( lt_steps[ step_seq = iv_step_seq ] OPTIONAL ).

    IF rs_step IS INITIAL.
      RAISE EXCEPTION NEW zcx_sto_step_error( text = |No active step configured for sequence { iv_step_seq }| ).
    ENDIF.

  ENDMETHOD.


  METHOD get_next_applicable_step.

    CLEAR: rs_step, et_skipped.

    DATA(lt_steps) = get_all_steps( ).

    LOOP AT lt_steps ASSIGNING FIELD-SYMBOL(<ls_step>)
         WHERE step_seq >= iv_from_seq.

      " A step with no handler class (REQUEST) is completed by saving the
      " process, not by a BAPI. Never hand it back to the engine - it would
      " dereference an unbound handler and short-dump.
      IF <ls_step>-handler IS NOT BOUND.
        APPEND <ls_step> TO et_skipped.
        CONTINUE.
      ENDIF.

      IF <ls_step>-handler->is_applicable( is_header ) = abap_false.
        APPEND <ls_step> TO et_skipped.
        CONTINUE.
      ENDIF.

      rs_step = <ls_step>.
      RETURN.
    ENDLOOP.

    " Nothing left - process is finished.
    CLEAR rs_step.

  ENDMETHOD.


  METHOD instantiate.

    TRY.
        CREATE OBJECT ro_handler TYPE (iv_class).
      CATCH cx_sy_create_object_error
            cx_sy_dyn_call_illegal_class INTO DATA(lx_root).
        RAISE EXCEPTION NEW zcx_sto_step_error( previous = lx_root
                                                text     = |Step handler class { iv_class } could not be instantiated| ).
    ENDTRY.

  ENDMETHOD.

ENDCLASS.


