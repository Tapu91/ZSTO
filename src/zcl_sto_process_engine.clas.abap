CLASS zcl_sto_process_engine DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES tt_step_seq TYPE STANDARD TABLE OF zsto_step_seq WITH EMPTY KEY.

    "! Everything the behavior pool has to write, in one struct.
    TYPES: BEGIN OF ty_state_change,
             "--- outcome -------------------------------------------------
             success            TYPE abap_bool,
             is_finished        TYPE abap_bool,
             messages           TYPE zsto_bapiret2,

             "--- the step that ran ---------------------------------------
             step_seq           TYPE zsto_step_seq,
             step_name          TYPE zsto_step_name,
             step_status        TYPE zsto_step_status,
             document_number    TYPE zsto_doc_number,
             document_year      TYPE zsto_doc_year,
             document_date      TYPE dats,
             error_message      TYPE zsto_error_message,

             "--- steps that opted out (mark 'S' + IsSkipped) --------------
             skipped_steps      TYPE tt_step_seq,

             "--- new header state ----------------------------------------
             "    only applied when SUCCESS = abap_true
             next_step_seq      TYPE zsto_step_seq,
             new_overall_status TYPE zsto_overall_status,
             purchase_order     TYPE ebeln,
             outbound_delivery  TYPE vbeln,
             gi_material_doc    TYPE zsto_doc_number,
             gi_matdoc_year     TYPE zsto_doc_year,
             billing_document   TYPE vbeln,
             gr_material_doc    TYPE zsto_doc_number,
             gr_matdoc_year     TYPE zsto_doc_year,

             "--- rows for ZSTO_PROC_IDOC ---------------------------------
             item_mapping       TYPE zif_sto_process_step=>tt_item_doc_map,
           END OF ty_state_change.

    "! Resolves the next applicable step, runs its handler, and returns the
    "! resulting state change. Writes nothing.
    METHODS determine_and_execute
      IMPORTING is_header        TYPE zif_sto_process_step=>ty_header
                it_item          TYPE zif_sto_process_step=>tt_item
      RETURNING VALUE(rs_change) TYPE ty_state_change.

    "! State change that clears a failed step: recomputes the overall status
    "! from the last successfully completed step.
    METHODS build_reset_change
      IMPORTING is_header        TYPE zif_sto_process_step=>ty_header
      RETURNING VALUE(rs_change) TYPE ty_state_change.

    "! The step-log rows a brand-new process should start with.
    "! Called by the createStepLog determination, which persists them by EML.
    METHODS build_initial_step_log
      IMPORTING is_header       TYPE zif_sto_process_step=>ty_header
      RETURNING VALUE(rt_steps) TYPE zcl_sto_step_factory=>tt_step_def
      RAISING   zcx_sto_step_error.

  PRIVATE SECTION.

    "! Fills the denormalised header document field belonging to this step.
    METHODS set_header_document
      IMPORTING is_step   TYPE zcl_sto_step_factory=>ty_step_def
                is_result TYPE zif_sto_process_step=>ty_step_result
      CHANGING  cs_change TYPE ty_state_change.

    METHODS highest_step_seq
      RETURNING VALUE(rv_max) TYPE zsto_step_seq.

ENDCLASS.


CLASS zcl_sto_process_engine IMPLEMENTATION.

  METHOD determine_and_execute.

    DATA lt_skipped TYPE zcl_sto_step_factory=>tt_step_def.
    DATA ls_step    TYPE zcl_sto_step_factory=>ty_step_def.

    "--- already done? ----------------------------------------------------
    IF is_header-OverallStatus = zif_sto_process_step=>gc_overall_status-completed.
      rs_change-success     = abap_true.
      rs_change-is_finished = abap_true.
      RETURN.
    ENDIF.

    TRY.
        "--- 1. Which step runs next --------------------------------------
        ls_step = zcl_sto_step_factory=>get_instance( )->get_next_applicable_step(
                    EXPORTING is_header   = is_header
                              iv_from_seq = is_header-CurrentStepSeq
                    IMPORTING et_skipped  = lt_skipped ).

        LOOP AT lt_skipped ASSIGNING FIELD-SYMBOL(<ls_skip>).
          APPEND <ls_skip>-step_seq TO rs_change-skipped_steps.
        ENDLOOP.

        "--- 2. Nothing executable left -> finished ------------------------
        IF ls_step IS INITIAL.
          rs_change-success            = abap_true.
          rs_change-is_finished        = abap_true.
          rs_change-next_step_seq      = highest_step_seq( ) + 1.
          rs_change-new_overall_status = zif_sto_process_step=>gc_overall_status-completed.
          RETURN.
        ENDIF.

        rs_change-step_seq  = ls_step-step_seq.
        rs_change-step_name = ls_step-step_name.

        "--- 3. Run the handler -------------------------------------------
        " Handler creates its document via EML in THIS LUW. If it raises,
        " RAP discards the LUW, so there is nothing to undo here.
        DATA(ls_result) = ls_step-handler->execute( is_header = is_header
                                                    it_item   = it_item ).

        "--- 4. Describe the resulting state ------------------------------
        rs_change-success         = abap_true.
        rs_change-step_status     = zif_sto_process_step=>gc_step_status-success.
        rs_change-document_number = ls_result-document_number.
        rs_change-document_year   = ls_result-document_year.
        rs_change-document_date   = COND #( WHEN ls_result-document_date IS INITIAL
                                            THEN sy-datum
                                            ELSE ls_result-document_date ).
        rs_change-item_mapping    = ls_result-item_mapping.
        rs_change-messages        = ls_result-messages.

        set_header_document( EXPORTING is_step   = ls_step
                                       is_result = ls_result
                             CHANGING  cs_change = rs_change ).

        " Advance past this step and past anything skipped along the way.
        DATA lv_next TYPE zsto_step_seq.
        lv_next = ls_step-step_seq + 1.
        LOOP AT lt_skipped ASSIGNING <ls_skip>.
          IF <ls_skip>-step_seq >= lv_next.
            lv_next = <ls_skip>-step_seq + 1.
          ENDIF.
        ENDLOOP.
        rs_change-next_step_seq = lv_next.

        rs_change-new_overall_status = COND #(
          WHEN lv_next > highest_step_seq( )
            THEN zif_sto_process_step=>gc_overall_status-completed
          WHEN ls_step-status_on_success IS NOT INITIAL
            THEN ls_step-status_on_success
          ELSE is_header-OverallStatus ).

        rs_change-is_finished = xsdbool( lv_next > highest_step_seq( ) ).

      CATCH zcx_sto_step_error INTO DATA(lx_error).

        " NEXT_STEP_SEQ deliberately left initial: the pool must not advance
        " the header, so the very same step is retried on the next click.
        rs_change-success       = abap_false.
        rs_change-step_status   = zif_sto_process_step=>gc_step_status-error.
        rs_change-error_message = lx_error->get_short_text( ).
        rs_change-new_overall_status = zif_sto_process_step=>gc_overall_status-error.

        APPEND VALUE bapiret2( type    = 'E'
                               id      = 'ZSTO'
                               number  = '001'
                               message = lx_error->get_short_text( )
                             ) TO rs_change-messages.
    ENDTRY.

  ENDMETHOD.


  METHOD build_reset_change.

    rs_change-success = abap_true.

    " Recompute from the last COMPLETED step. Simply keeping the old value
    " would leave the process stuck on '90' (error) forever.
    SELECT MAX( step_seq ) FROM zsto_proc_step
      WHERE process_uuid = @is_header-ProcessUUID
        AND step_status  = @zif_sto_process_step=>gc_step_status-success
      INTO @DATA(lv_last_ok).

    rs_change-new_overall_status = zif_sto_process_step=>gc_overall_status-requested.

    IF lv_last_ok IS NOT INITIAL.
      SELECT SINGLE status_on_success FROM zsto_stepcust
        WHERE step_seq = @lv_last_ok
        INTO @rs_change-new_overall_status.
    ENDIF.

    " Retry the step after the last successful one.
    rs_change-next_step_seq = lv_last_ok + 1.

  ENDMETHOD.


  METHOD build_initial_step_log.

    rt_steps = zcl_sto_step_factory=>get_instance( )->get_all_steps( ).

  ENDMETHOD.


  METHOD set_header_document.

    CASE is_step-step_name.
      WHEN zif_sto_process_step=>gc_step_name-po.
        cs_change-purchase_order = is_result-document_number.

      WHEN zif_sto_process_step=>gc_step_name-delivery.
        cs_change-outbound_delivery = is_result-document_number.

      WHEN zif_sto_process_step=>gc_step_name-pgi.
        cs_change-gi_material_doc = is_result-document_number.
        cs_change-gi_matdoc_year  = is_result-document_year.

      WHEN zif_sto_process_step=>gc_step_name-billing.
        cs_change-billing_document = is_result-document_number.

      WHEN zif_sto_process_step=>gc_step_name-gr.
        cs_change-gr_material_doc = is_result-document_number.
        cs_change-gr_matdoc_year  = is_result-document_year.

      WHEN OTHERS.
        " REQUEST or a customer-added step - nothing denormalised.
    ENDCASE.

  ENDMETHOD.


  METHOD highest_step_seq.

    TRY.
        DATA(lt_all) = zcl_sto_step_factory=>get_instance( )->get_all_steps( ).
        LOOP AT lt_all ASSIGNING FIELD-SYMBOL(<ls_all>).
          IF <ls_all>-step_seq > rv_max.
            rv_max = <ls_all>-step_seq.
          ENDIF.
        ENDLOOP.
      CATCH zcx_sto_step_error ##NO_HANDLER.
    ENDTRY.

  ENDMETHOD.

ENDCLASS.

