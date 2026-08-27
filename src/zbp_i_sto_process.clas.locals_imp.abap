CLASS lhc_batch DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.

    TYPES tt_batch_read   TYPE TABLE FOR READ RESULT zi_sto_process\\Batch.
    TYPES tt_process_read TYPE TABLE FOR READ RESULT zi_sto_process.


    METHODS get_instance_features FOR INSTANCE FEATURES
      keys REQUEST requested_features FOR Batch RESULT result.

    METHODS assignPoItemNo FOR DETERMINE ON SAVE
       keys FOR Batch~assignPoItemNo.

    METHODS validateBatchQuantity FOR VALIDATE ON SAVE
       keys FOR Batch~validateBatchQuantity.

    METHODS deriveBatchKeys FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Batch~deriveBatchKeys.

    METHODS syncItemQuantity FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Batch~syncItemQuantity.


    METHODS read_processes
      IMPORTING it_batch          TYPE tt_batch_read
      RETURNING VALUE(rt_process) TYPE tt_process_read.

ENDCLASS.

CLASS lhc_batch IMPLEMENTATION.

  METHOD get_instance_features.
    READ ENTITIES OF zi_sto_process IN LOCAL MODE
    ENTITY Batch
      FIELDS ( ProcessUUID )
      WITH CORRESPONDING #( keys )
    RESULT DATA(lt_batch).

    DATA(lt_process) = read_processes( lt_batch ).

    LOOP AT lt_batch ASSIGNING FIELD-SYMBOL(<ls_batch>).

      DATA lv_seq TYPE zsto_step_seq.
      lv_seq = VALUE #( lt_process[ ProcessUUID = <ls_batch>-ProcessUUID
                                  ]-CurrentStepSeq OPTIONAL ).

      DATA lv_locked TYPE if_abap_behv=>t_xflag.
      lv_locked = COND #( WHEN lv_seq > 1
                          THEN if_abap_behv=>fc-o-disabled
                          ELSE if_abap_behv=>fc-o-enabled ).

      APPEND VALUE #( %tky    = <ls_batch>-%tky
                      %update = lv_locked
                      %delete = lv_locked ) TO result.
    ENDLOOP.


  ENDMETHOD.

  METHOD assignPoItemNo.

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
        ENTITY Batch
          FIELDS ( ProcessUUID )
          WITH CORRESPONDING #( keys )
        RESULT DATA(lt_trigger).

    DATA(lt_process) = read_processes( lt_trigger ).
    CHECK lt_process IS NOT INITIAL.

    DATA lt_update TYPE TABLE FOR UPDATE zi_sto_process\\Batch.

    LOOP AT lt_process ASSIGNING FIELD-SYMBOL(<ls_process>).

      " Frozen once a document exists.
      CHECK <ls_process>-CurrentStepSeq <= 1.

      " Every batch row of this process, drafts included: root -> items ->
      " batches, walking the composition tree.
      READ ENTITIES OF zi_sto_process IN LOCAL MODE
        ENTITY Process BY \_Item
          FIELDS ( ProcessItem )
          WITH VALUE #( ( %tky = <ls_process>-%tky ) )
        RESULT DATA(lt_item).

      CHECK lt_item IS NOT INITIAL.

      READ ENTITIES OF zi_sto_process IN LOCAL MODE
        ENTITY Item BY \_Batch
          FIELDS ( ProcessItem Batch PoItemNo )
          WITH CORRESPONDING #( lt_item )
        RESULT DATA(lt_batch).

      " (ProcessItem, Batch) is the business order of the PO lines.
      SORT lt_batch BY ProcessItem ASCENDING Batch ASCENDING.

      DATA lv_no TYPE zsto_doc_item.
      CLEAR lv_no.

      LOOP AT lt_batch ASSIGNING FIELD-SYMBOL(<ls_batch>).
        lv_no = lv_no + 10.
        CHECK <ls_batch>-PoItemNo <> lv_no.          " only real changes
        APPEND VALUE #( %tky     = <ls_batch>-%tky
                        PoItemNo = lv_no ) TO lt_update.
      ENDLOOP.

    ENDLOOP.

    CHECK lt_update IS NOT INITIAL.

    MODIFY ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Batch
        UPDATE FIELDS ( PoItemNo )
        WITH lt_update
      REPORTED DATA(ld_reported).


  ENDMETHOD.

  METHOD validateBatchQuantity.

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
    ENTITY Batch
      FIELDS ( ProcessUUID ProcessItem Batch Quantity BaseUnit StorageLocation )
      WITH CORRESPONDING #( keys )
    RESULT DATA(lt_batch).

    " material comes from the parent item
    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Batch BY \_Item
        FIELDS ( Material )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_item)
      LINK   DATA(lt_item_link).

    " source plant comes from the header
    DATA(lt_process) = read_processes( lt_batch ).

    LOOP AT lt_batch ASSIGNING FIELD-SYMBOL(<ls_batch>).

      "--- quantity must be positive -----------------------------------
      IF <ls_batch>-Quantity <= 0.
        APPEND VALUE #( %tky = <ls_batch>-%tky ) TO failed-batch.
        APPEND VALUE #(
          %tky = <ls_batch>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = |Batch { <ls_batch>-Batch }: enter a quantity | &&
                              |greater than zero, or remove the row.| )
          %element-Quantity = if_abap_behv=>mk-on
        ) TO reported-batch.
        CONTINUE.
      ENDIF.

      "--- resolve material and source plant ----------------------------
      DATA(ls_link) = VALUE #( lt_item_link[ source-%tky = <ls_batch>-%tky ]
                               OPTIONAL ).
      DATA(ls_item) = VALUE #( lt_item[ %tky = ls_link-target-%tky ] OPTIONAL ).
      DATA(ls_proc) = VALUE #( lt_process[ ProcessUUID = <ls_batch>-ProcessUUID ]
                               OPTIONAL ).

      CHECK ls_item-Material IS NOT INITIAL
        AND ls_proc-FromPlant IS NOT INITIAL.

      "--- live availability -------------------------------------------
      SELECT SINGLE AvailableQuantity
        FROM zi_sto_batchstockvh WITH PRIVILEGED ACCESS
        WHERE Material        = @ls_item-Material
*          AND Plant           = @ls_proc-FromPlant
*          AND StorageLocation = @<ls_batch>-StorageLocation
*          AND Batch           = @<ls_batch>-Batch
        INTO @DATA(lv_available).

      IF sy-subrc <> 0.
        lv_available = 0.
      ENDIF.

      CHECK <ls_batch>-Quantity > lv_available.

      APPEND VALUE #( %tky = <ls_batch>-%tky ) TO failed-batch.
      APPEND VALUE #(
        %tky = <ls_batch>-%tky
        %msg = new_message_with_text(
                 severity = if_abap_behv_message=>severity-error
                 text     = |Batch { <ls_batch>-Batch }: only { lv_available } | &&
                            |{ <ls_batch>-BaseUnit } available in plant | &&
                            |{ ls_proc-FromPlant } / { <ls_batch>-StorageLocation }, | &&
                            |{ <ls_batch>-Quantity } requested.| )
        %element-Quantity = if_abap_behv=>mk-on
      ) TO reported-batch.

    ENDLOOP.



  ENDMETHOD.

  METHOD read_processes.

    DATA lt_key TYPE TABLE FOR READ IMPORT zi_sto_process.

    LOOP AT it_batch ASSIGNING FIELD-SYMBOL(<ls_batch>).
      APPEND VALUE #( %key-ProcessUUID = <ls_batch>-ProcessUUID
                      %is_draft        = <ls_batch>-%is_draft ) TO lt_key.
    ENDLOOP.

    SORT lt_key BY %key-ProcessUUID %is_draft.
    DELETE ADJACENT DUPLICATES FROM lt_key
      COMPARING %key-ProcessUUID %is_draft.

    CHECK lt_key IS NOT INITIAL.

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process
        ALL FIELDS WITH lt_key
      RESULT rt_process.


  ENDMETHOD.

  METHOD syncItemQuantity.

    " Parent items of the touched batch rows.
    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Batch BY \_Item
        FIELDS ( ItemUUID BaseUnit )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_item).

    CHECK lt_item IS NOT INITIAL.

    SORT lt_item BY %tky.
    DELETE ADJACENT DUPLICATES FROM lt_item COMPARING %tky.

    " ALL current batch rows of those items - not just the ones in `keys`.
    " Summing only the changed rows would drop every sibling that was not
    " touched.
    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Item BY \_Batch
        FIELDS ( Quantity BaseUnit )
        WITH CORRESPONDING #( lt_item )
      RESULT DATA(lt_batch)
      LINK   DATA(lt_link).

    DATA lt_upd TYPE TABLE FOR UPDATE zi_sto_process\\Item.

    LOOP AT lt_item ASSIGNING FIELD-SYMBOL(<ls_item>).

      DATA lv_sum TYPE menge_d.
      DATA lv_unit TYPE meins.
      CLEAR: lv_sum, lv_unit.

      LOOP AT lt_link ASSIGNING FIELD-SYMBOL(<ls_link>)
           WHERE source-%tky = <ls_item>-%tky.
        DATA(ls_b) = VALUE #( lt_batch[ %tky = <ls_link>-target-%tky ] OPTIONAL ).
        lv_sum = lv_sum + ls_b-Quantity.
        IF lv_unit IS INITIAL.
          lv_unit = ls_b-BaseUnit.
        ENDIF.
      ENDLOOP.

      APPEND VALUE #( %tky     = <ls_item>-%tky
                      Quantity = lv_sum
                      " Only stamp the unit if the batches actually carried
                      " one - a line whose splits were all removed keeps the
                      " unit it had, so the field does not blank out.
                      BaseUnit = COND #( WHEN lv_unit IS NOT INITIAL
                                         THEN lv_unit
                                         ELSE <ls_item>-BaseUnit )
                    ) TO lt_upd.

    ENDLOOP.

    CHECK lt_upd IS NOT INITIAL.

    MODIFY ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Item
        UPDATE FIELDS ( Quantity BaseUnit )
        WITH lt_upd
      REPORTED DATA(ld_reported).

  ENDMETHOD.



  METHOD derivebatchkeys.

  ENDMETHOD.

ENDCLASS.

CLASS lhc_process DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR Process RESULT result.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR Process RESULT result.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR Process RESULT result.

    METHODS processNextStep FOR MODIFY
      IMPORTING keys FOR ACTION Process~processNextStep RESULT result.

    METHODS resetFailedStep FOR MODIFY
      IMPORTING keys FOR ACTION Process~resetFailedStep RESULT result.

    METHODS setInitialState FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Process~setInitialState.

    METHODS assignProcessID FOR DETERMINE ON SAVE
      IMPORTING keys FOR Process~assignProcessID.

    METHODS createStepLog FOR DETERMINE ON SAVE
      IMPORTING keys FOR Process~createStepLog.

    METHODS validateHeader FOR VALIDATE ON SAVE
      IMPORTING keys FOR Process~validateHeader.

    METHODS validateItems FOR VALIDATE ON SAVE
      IMPORTING keys FOR Process~validateItems.

*    METHODS validateNotInProcess FOR VALIDATE ON SAVE
*      IMPORTING keys FOR Process~validateNotInProcess.

    METHODS validateConfiguration FOR VALIDATE ON SAVE
      IMPORTING keys FOR Process~validateConfiguration.


    TYPES ty_process_row TYPE STRUCTURE FOR READ RESULT zi_sto_process.

    METHODS apply_state_change
      IMPORTING is_process TYPE ty_process_row
                is_change  TYPE zcl_sto_process_engine=>ty_state_change.

    METHODS update_step_row
      IMPORTING is_process TYPE ty_process_row
                is_change  TYPE zcl_sto_process_engine=>ty_state_change.

    METHODS mark_steps_skipped
      IMPORTING is_process TYPE ty_process_row
                it_seq     TYPE zcl_sto_process_engine=>tt_step_seq.

    METHODS create_mapping_rows
      IMPORTING is_process TYPE ty_process_row
                is_change  TYPE zcl_sto_process_engine=>ty_state_change.

    METHODS update_header
      IMPORTING is_process TYPE ty_process_row
                is_change  TYPE zcl_sto_process_engine=>ty_state_change.

ENDCLASS.


CLASS lhc_process IMPLEMENTATION.

  "=======================================================================
  " FEATURE CONTROL
  "=======================================================================
  METHOD get_instance_features.

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process
        FIELDS ( OverallStatus ProcessingLock CurrentStepSeq )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_process)
      FAILED failed.

    result = VALUE #(
      FOR ls IN lt_process (
        %tky = ls-%tky

        %action-processNextStep = COND #(
          WHEN ls-OverallStatus = zif_sto_process_step=>gc_overall_status-completed
          THEN if_abap_behv=>fc-o-disabled
          ELSE if_abap_behv=>fc-o-enabled )

        %action-resetFailedStep = COND #(
          WHEN ls-OverallStatus = zif_sto_process_step=>gc_overall_status-error
          THEN if_abap_behv=>fc-o-enabled
          ELSE if_abap_behv=>fc-o-disabled )

        %delete = COND #(
          WHEN ls-CurrentStepSeq > 1
          THEN if_abap_behv=>fc-o-disabled
          ELSE if_abap_behv=>fc-o-enabled )

        %assoc-_Item = COND #(
          WHEN ls-CurrentStepSeq > 1
          THEN if_abap_behv=>fc-o-disabled
          ELSE if_abap_behv=>fc-o-enabled )
      ) ).

  ENDMETHOD.


  "=======================================================================
  " THE ACTION BEHIND THE BUTTON
  "
  " read -> decide -> write, all inside the RAP LUW, all through EML.
  "=======================================================================
  METHOD processNextStep.

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_process)
      FAILED failed.

    LOOP AT lt_process ASSIGNING FIELD-SYMBOL(<ls_process>).

      "--- items of this process ----------------------------------------
      READ ENTITIES OF zi_sto_process IN LOCAL MODE
        ENTITY Process BY \_Item
          ALL FIELDS WITH VALUE #( ( %tky = <ls_process>-%tky ) )
        RESULT DATA(lt_item_rap).

      DATA lt_item TYPE zif_sto_process_step=>tt_item.
      CLEAR lt_item.
      LOOP AT lt_item_rap ASSIGNING FIELD-SYMBOL(<ls_item_rap>).
        " Field names in the RAP derived type and in the CDS-based
        " ty_header / tt_item are identical, so CORRESPONDING is enough.
        APPEND CORRESPONDING #( <ls_item_rap> ) TO lt_item.
      ENDLOOP.

      READ ENTITIES OF zi_sto_process IN LOCAL MODE
        ENTITY Item BY \_Batch
          ALL FIELDS WITH CORRESPONDING #( lt_item_rap )
        RESULT DATA(lt_batch_rap).

      DATA lt_batch TYPE zif_sto_process_step=>tt_batch.
      CLEAR lt_batch.
      LOOP AT lt_batch_rap ASSIGNING FIELD-SYMBOL(<ls_batch_rap>).
        APPEND CORRESPONDING #( <ls_batch_rap> ) TO lt_batch.
      ENDLOOP.
      SORT lt_batch BY PoItemNo ASCENDING.


      "--- decide + execute (no writes in there) -------------------------
      DATA(lo_engine) = NEW zcl_sto_process_engine( ).

      DATA(ls_change) = lo_engine->determine_and_execute(
                          is_header = CORRESPONDING #( <ls_process> )
                          it_item   = lt_item
                          it_batch  = lt_batch ).

      "--- persist the outcome, through EML ------------------------------
      apply_state_change( is_process = <ls_process>
                          is_change  = ls_change ).

      "--- report --------------------------------------------------------
      IF ls_change-success = abap_false.

        APPEND VALUE #( %tky = <ls_process>-%tky ) TO failed-process.

        LOOP AT ls_change-messages ASSIGNING FIELD-SYMBOL(<ls_msg>)
             WHERE type CA 'EAX'.
          APPEND VALUE #(
            %tky = <ls_process>-%tky
            %msg = new_message_with_text(
                     severity = if_abap_behv_message=>severity-error
                     text     = CONV #( <ls_msg>-message ) )
          ) TO reported-process.
        ENDLOOP.

      ELSE.

        APPEND VALUE #(
          %tky = <ls_process>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-success
                   text     = COND #(
                     WHEN ls_change-is_finished = abap_true
                       THEN |STO process completed|
                     ELSE |{ ls_change-step_name }: document | &&
                          |{ ls_change-document_number } created| ) )
        ) TO reported-process.

        LOOP AT ls_change-messages ASSIGNING <ls_msg> WHERE type = 'W'.
          APPEND VALUE #(
            %tky = <ls_process>-%tky
            %msg = new_message_with_text(
                     severity = if_abap_behv_message=>severity-warning
                     text     = CONV #( <ls_msg>-message ) )
          ) TO reported-process.
        ENDLOOP.

      ENDIF.

    ENDLOOP.

    "--- return the refreshed instance ---------------------------------
    " Because the writes above went through EML, the RAP buffer is now
    " current and READ ENTITIES returns the new state. (The previous
    " version had to bypass this with a SELECT precisely because the
    " engine wrote behind RAP's back.)
    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_refreshed).

    result = VALUE #( FOR ls IN lt_refreshed
                      ( %tky = ls-%tky  %param = ls ) ).

  ENDMETHOD.


  "=======================================================================
  METHOD resetFailedStep.

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_process)
      FAILED failed.

    LOOP AT lt_process ASSIGNING FIELD-SYMBOL(<ls_process>).

      DATA(lo_engine) = NEW zcl_sto_process_engine( ).
      DATA(ls_change) = lo_engine->build_reset_change(
                          CORRESPONDING #( <ls_process> ) ).

      "--- clear every errored step row -----------------------------------
      READ ENTITIES OF zi_sto_process IN LOCAL MODE
        ENTITY Process BY \_Step
          FIELDS ( StepStatus )
          WITH VALUE #( ( %tky = <ls_process>-%tky ) )
        RESULT DATA(lt_step).

      DATA lt_step_upd TYPE TABLE FOR UPDATE zi_sto_process\\Step.
      CLEAR lt_step_upd.

      LOOP AT lt_step ASSIGNING FIELD-SYMBOL(<ls_step>)
           WHERE StepStatus = zif_sto_process_step=>gc_step_status-error.
        APPEND VALUE #( %tky         = <ls_step>-%tky
                        StepStatus   = zif_sto_process_step=>gc_step_status-open
                        ErrorMessage = space ) TO lt_step_upd.
      ENDLOOP.

      IF lt_step_upd IS NOT INITIAL.
        MODIFY ENTITIES OF zi_sto_process IN LOCAL MODE
          ENTITY Step
            UPDATE FIELDS ( StepStatus ErrorMessage )
            WITH lt_step_upd
          REPORTED DATA(ld_rep_step).
      ENDIF.

      "--- reset the header status ----------------------------------------
      MODIFY ENTITIES OF zi_sto_process IN LOCAL MODE
        ENTITY Process
          UPDATE FIELDS ( OverallStatus CurrentStepSeq ProcessingLock )
          WITH VALUE #( ( %tky           = <ls_process>-%tky
                          OverallStatus  = ls_change-new_overall_status
                          CurrentStepSeq = ls_change-next_step_seq
                          ProcessingLock = abap_false ) )
        REPORTED DATA(ld_rep_hdr).

      APPEND VALUE #(
        %tky = <ls_process>-%tky
        %msg = new_message_with_text(
                 severity = if_abap_behv_message=>severity-success
                 text     = |Failed step reset - you can retry now| )
      ) TO reported-process.

    ENDLOOP.

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_refreshed).

    result = VALUE #( FOR ls IN lt_refreshed
                      ( %tky = ls-%tky  %param = ls ) ).

  ENDMETHOD.


  "=======================================================================
  " PERSISTENCE - every write in this BO goes through one of these
  "=======================================================================
  METHOD apply_state_change.

    " 1. the step row that just ran (also on failure - that is how the
    "    error text reaches the ProcessFlow node)
    update_step_row( is_process = is_process
                     is_change  = is_change ).

    " 2. steps that opted out for this process
    mark_steps_skipped( is_process = is_process
                        it_seq     = is_change-skipped_steps ).

    IF is_change-success = abap_false.
      " Header: status only. CURRENT_STEP_SEQ is deliberately NOT advanced,
      " so the next click retries the same step.
      MODIFY ENTITIES OF zi_sto_process IN LOCAL MODE
        ENTITY Process
          UPDATE FIELDS ( OverallStatus )
          WITH VALUE #( ( %tky          = is_process-%tky
                          OverallStatus = is_change-new_overall_status ) )
        REPORTED DATA(ld_reported).
      RETURN.
    ENDIF.

    " 3. the traceability rows
    create_mapping_rows( is_process = is_process
                         is_change  = is_change ).

    " 4. advance the header
    update_header( is_process = is_process
                   is_change  = is_change ).

  ENDMETHOD.


  "=======================================================================
  METHOD update_step_row.

    CHECK is_change-step_seq IS NOT INITIAL.

    " Take the child's %tky from RAP rather than assembling it from a UUID.
    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process BY \_Step
        FIELDS ( StepSeq )
        WITH VALUE #( ( %tky = is_process-%tky ) )
      RESULT DATA(lt_step).

    DATA lt_upd TYPE TABLE FOR UPDATE zi_sto_process\\Step.
    GET TIME STAMP FIELD DATA(lv_now).

    LOOP AT lt_step ASSIGNING FIELD-SYMBOL(<ls_step>)
         WHERE StepSeq = is_change-step_seq.

      APPEND VALUE #( %tky           = <ls_step>-%tky
                      StepStatus     = is_change-step_status
                      DocumentNumber = is_change-document_number
                      DocumentYear   = is_change-document_year
                      DocumentDate   = is_change-document_date
                      ErrorMessage   = is_change-error_message
                      ProcessedBy    = sy-uname
                      ProcessedAt    = lv_now ) TO lt_upd.
    ENDLOOP.

    CHECK lt_upd IS NOT INITIAL.

    MODIFY ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Step
        UPDATE FIELDS ( StepStatus DocumentNumber DocumentYear
                        DocumentDate ErrorMessage ProcessedBy ProcessedAt )
        WITH lt_upd
      REPORTED DATA(ld_reported).

  ENDMETHOD.


  "=======================================================================
  METHOD mark_steps_skipped.

    CHECK it_seq IS NOT INITIAL.

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process BY \_Step
        FIELDS ( StepSeq StepStatus )
        WITH VALUE #( ( %tky = is_process-%tky ) )
      RESULT DATA(lt_step).

    DATA lt_upd TYPE TABLE FOR UPDATE zi_sto_process\\Step.
    GET TIME STAMP FIELD DATA(lv_now).

    LOOP AT it_seq ASSIGNING FIELD-SYMBOL(<lv_seq>).

      " "AND StepStatus <> 'S'" matters: the handler-less REQUEST step also
      " arrives here, and it must not be relabelled "not applicable" - it
      " genuinely completed when the process was saved.
      LOOP AT lt_step ASSIGNING FIELD-SYMBOL(<ls_step>)
           WHERE StepSeq    = <lv_seq>
             AND StepStatus <> zif_sto_process_step=>gc_step_status-success.

        APPEND VALUE #( %tky         = <ls_step>-%tky
                        StepStatus   = zif_sto_process_step=>gc_step_status-success
                        IsSkipped    = abap_true
                        ErrorMessage = 'Not applicable for this process'
                        ProcessedBy  = sy-uname
                        ProcessedAt  = lv_now ) TO lt_upd.
      ENDLOOP.
    ENDLOOP.

    CHECK lt_upd IS NOT INITIAL.

    MODIFY ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Step
        UPDATE FIELDS ( StepStatus IsSkipped ErrorMessage
                        ProcessedBy ProcessedAt )
        WITH lt_upd
      REPORTED DATA(ld_reported).

  ENDMETHOD.


  "=======================================================================
  " ONE ROW PER PROCESS ITEM - the line-level trace.
  " Created through the composition, so RAP fills ProcessUUID itself.
  "=======================================================================
  METHOD create_mapping_rows.

    CHECK is_change-item_mapping IS NOT INITIAL.

    DATA lt_create TYPE TABLE FOR CREATE zi_sto_process\_ItemDoc.

    DATA ls_create LIKE LINE OF lt_create.
    ls_create-%tky = is_process-%tky.

    LOOP AT is_change-item_mapping ASSIGNING FIELD-SYMBOL(<ls_map>).
      APPEND VALUE #(
        %cid           = |MAP_{ is_change-step_seq }_{ <ls_map>-process_item }|
        %is_draft   =    is_process-%is_draft
        ProcessItem    = <ls_map>-process_item
        StepSeq        = is_change-step_seq
        StepName       = is_change-step_name
        DocumentNumber = <ls_map>-document_number
        DocumentItem   = <ls_map>-document_item
        DocumentYear   = <ls_map>-document_year
        Quantity       = <ls_map>-quantity
        BaseUnit       = <ls_map>-base_unit
      ) TO ls_create-%target.
    ENDLOOP.

    APPEND ls_create TO lt_create.

    MODIFY ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process
        CREATE BY \_ItemDoc
          FIELDS ( ProcessItem StepSeq StepName DocumentNumber
                   DocumentItem DocumentYear Quantity BaseUnit )
          WITH lt_create
      REPORTED DATA(ld_reported)
      FAILED   DATA(ld_failed).

  ENDMETHOD.


  "=======================================================================
  METHOD update_header.

    DATA ls_upd TYPE STRUCTURE FOR UPDATE zi_sto_process.

    ls_upd-%tky           = is_process-%tky.
    ls_upd-CurrentStepSeq = is_change-next_step_seq.
    ls_upd-OverallStatus  = is_change-new_overall_status.
    ls_upd-ProcessingLock = abap_false.

    " Only the document field belonging to the step that just ran is filled
    " in the state change; the others stay initial and must not be written,
    " or they would blank out earlier documents.
    IF is_change-purchase_order IS NOT INITIAL.
      ls_upd-PurchaseOrder = is_change-purchase_order.
    ENDIF.
    IF is_change-outbound_delivery IS NOT INITIAL.
      ls_upd-OutboundDelivery = is_change-outbound_delivery.
    ENDIF.
    IF is_change-gi_material_doc IS NOT INITIAL.
      ls_upd-GIMaterialDoc     = is_change-gi_material_doc.
      ls_upd-GIMaterialDocYear = is_change-gi_matdoc_year.
    ENDIF.
    IF is_change-billing_document IS NOT INITIAL.
      ls_upd-BillingDocument = is_change-billing_document.
    ENDIF.
    IF is_change-gr_material_doc IS NOT INITIAL.
      ls_upd-GRMaterialDoc     = is_change-gr_material_doc.
      ls_upd-GRMaterialDocYear = is_change-gr_matdoc_year.
    ENDIF.

    " %control decides which fields are actually written, so the initial
    " ones above are left untouched rather than cleared.
    ls_upd-%control-CurrentStepSeq    = if_abap_behv=>mk-on.
    ls_upd-%control-OverallStatus     = if_abap_behv=>mk-on.
    ls_upd-%control-ProcessingLock    = if_abap_behv=>mk-on.
    ls_upd-%control-PurchaseOrder     = COND #( WHEN is_change-purchase_order IS NOT INITIAL
                                                THEN if_abap_behv=>mk-on ELSE if_abap_behv=>mk-off ).
    ls_upd-%control-OutboundDelivery  = COND #( WHEN is_change-outbound_delivery IS NOT INITIAL
                                                THEN if_abap_behv=>mk-on ELSE if_abap_behv=>mk-off ).
    ls_upd-%control-GIMaterialDoc     = COND #( WHEN is_change-gi_material_doc IS NOT INITIAL
                                                THEN if_abap_behv=>mk-on ELSE if_abap_behv=>mk-off ).
    ls_upd-%control-GIMaterialDocYear = ls_upd-%control-GIMaterialDoc.
    ls_upd-%control-BillingDocument   = COND #( WHEN is_change-billing_document IS NOT INITIAL
                                                THEN if_abap_behv=>mk-on ELSE if_abap_behv=>mk-off ).
    ls_upd-%control-GRMaterialDoc     = COND #( WHEN is_change-gr_material_doc IS NOT INITIAL
                                                THEN if_abap_behv=>mk-on ELSE if_abap_behv=>mk-off ).
    ls_upd-%control-GRMaterialDocYear = ls_upd-%control-GRMaterialDoc.


    MODIFY ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process
        UPDATE SET FIELDS WITH VALUE #( ( ls_upd ) )
      REPORTED DATA(ld_reported).

  ENDMETHOD.


  "=======================================================================
  " DETERMINATIONS
  "=======================================================================
  METHOD setInitialState.

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process
        FIELDS ( CurrentStepSeq OverallStatus TransferDate )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_process).

    DATA lt_update TYPE TABLE FOR UPDATE zi_sto_process.

    LOOP AT lt_process ASSIGNING FIELD-SYMBOL(<ls_process>)
         WHERE CurrentStepSeq IS INITIAL.

      APPEND VALUE #(
        %tky           = <ls_process>-%tky
        CurrentStepSeq = 1
        OverallStatus  = zif_sto_process_step=>gc_overall_status-requested
        ProcessingLock = abap_false
        TransferDate   = COND #( WHEN <ls_process>-TransferDate IS INITIAL
                                 THEN sy-datum
                                 ELSE <ls_process>-TransferDate )
      ) TO lt_update.
    ENDLOOP.

    CHECK lt_update IS NOT INITIAL.

    MODIFY ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process
        UPDATE FIELDS ( CurrentStepSeq OverallStatus ProcessingLock TransferDate )
        WITH lt_update
      REPORTED DATA(ld_reported).

  ENDMETHOD.


  "=======================================================================
  " NUMBER_GET_NEXT is not released for ABAP Cloud.
  " CL_NUMBERRANGE_RUNTIME is the released replacement.
  "=======================================================================
  METHOD assignProcessID.

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process
        FIELDS ( ProcessID )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_process).

    DATA lt_update TYPE TABLE FOR UPDATE zi_sto_process.

    LOOP AT lt_process ASSIGNING FIELD-SYMBOL(<ls_process>)
         WHERE ProcessID IS INITIAL.

      TRY.
*          cl_numberrange_runtime=>number_get(
*            EXPORTING nr_range_nr = '01'
*                      object      = 'ZSTO_PROC'
*                      quantity    = '1'
*            IMPORTING number      = DATA(lv_number)
*                      returncode  = DATA(lv_rc)          ##NEEDED
*                      returned_quantity = DATA(lv_qty) ) ##NEEDED.
          SELECT MAX( process_id ) FROM zsto_process_h INTO @DATA(lv_number).
          lv_number = lv_number + 1.
          APPEND VALUE #( %tky      = <ls_process>-%tky
                          ProcessID = |{ lv_number ALPHA = IN }| ) TO lt_update.

        CATCH cx_number_ranges INTO DATA(lx_nr).
          " NOTE: no `failed` here. A DETERMINE handler has only `reported`
          " - it cannot reject the save. A number-range outage therefore
          " surfaces as an error message, not as a rejected save.
          APPEND VALUE #(
            %tky = <ls_process>-%tky
            %msg = new_message_with_text(
                     severity = if_abap_behv_message=>severity-error
                     text     = |Number range ZSTO_PROC: { lx_nr->get_text( ) }| )
          ) TO reported-process.
      ENDTRY.

    ENDLOOP.

    CHECK lt_update IS NOT INITIAL.

    MODIFY ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process
        UPDATE FIELDS ( ProcessID )
        WITH lt_update
      REPORTED DATA(ld_reported).

  ENDMETHOD.


  "=======================================================================
  " Creates the step log THROUGH RAP.
  "
  " Replaces ZCL_STO_PROCESS_ENGINE=>INITIALIZE_STEP_LOG, whose
  " "INSERT zsto_proc_step FROM TABLE" was one of the statements causing
  " BEHAVIOR_ILLEGAL_STATEMENT.
  "
  " ProcessID is deliberately NOT copied into the REQUEST row: determination
  " order on save is not guaranteed, so assignProcessID may not have run yet.
  "=======================================================================
  METHOD createStepLog.

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_process).

    " Re-entrancy guard.
    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process BY \_Step
        FIELDS ( StepSeq )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_existing)                ##NEEDED
      LINK   DATA(lt_existing_link).

    DATA(lo_engine) = NEW zcl_sto_process_engine( ).

    DATA lt_create TYPE TABLE FOR CREATE zi_sto_process\_Step.

    LOOP AT lt_process ASSIGNING FIELD-SYMBOL(<ls_process>).

      IF line_exists( lt_existing_link[ source-%tky = <ls_process>-%tky ] ).
        CONTINUE.
      ENDIF.

      TRY.
          DATA(lt_def) = lo_engine->build_initial_step_log(
                           CORRESPONDING #( <ls_process> ) ).
        CATCH zcx_sto_step_error INTO DATA(lx_cfg).
          " Determinations have no `failed` - report only. The usable-config
          " case is caught up front by validateConfiguration.
          APPEND VALUE #(
            %tky = <ls_process>-%tky
            %msg = new_message_with_text(
                     severity = if_abap_behv_message=>severity-error
                     text     = CONV #( lx_cfg->get_short_text( ) ) )
          ) TO reported-process.
          CONTINUE.
      ENDTRY.

      DATA ls_create LIKE LINE OF lt_create.
      CLEAR ls_create.
      ls_create-%tky = <ls_process>-%tky.

      LOOP AT lt_def ASSIGNING FIELD-SYMBOL(<ls_def>).

        DATA lv_skipped TYPE abap_bool.
        lv_skipped = COND abap_bool(
          WHEN <ls_def>-handler IS BOUND
           AND <ls_def>-handler->is_applicable(
                 CORRESPONDING #( <ls_process> ) ) = abap_false
          THEN abap_true ELSE abap_false ).

        " A step with no handler (REQUEST) is complete the moment the
        " process is saved. A step that is not applicable is closed
        " straight away too, so the flow never shows a node that will
        " never run as "pending".
        DATA lv_status TYPE zsto_step_status.
        lv_status = COND #(
          WHEN <ls_def>-handler IS NOT BOUND OR lv_skipped = abap_true
          THEN zif_sto_process_step=>gc_step_status-success
          ELSE zif_sto_process_step=>gc_step_status-open ).

        APPEND VALUE #(
          %cid         = |STEP_{ <ls_process>-ProcessUUID }_{ <ls_def>-step_seq }|
          StepSeq      = <ls_def>-step_seq
          StepName     = <ls_def>-step_name
          StepStatus   = lv_status
          IsSkipped    = lv_skipped
          DocumentDate = COND #(
                           WHEN lv_status = zif_sto_process_step=>gc_step_status-success
                           THEN sy-datum ELSE '00000000' )
          ProcessedBy  = COND #(
                           WHEN lv_status = zif_sto_process_step=>gc_step_status-success
                           THEN sy-uname ELSE space )
          ErrorMessage = COND #(
                           WHEN lv_skipped = abap_true
                           THEN 'Not applicable for this process' ELSE space )
        ) TO ls_create-%target.

      ENDLOOP.

      IF ls_create-%target IS NOT INITIAL.
        APPEND ls_create TO lt_create.
      ENDIF.

    ENDLOOP.

    CHECK lt_create IS NOT INITIAL.

    MODIFY ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process
        CREATE BY \_Step
          FIELDS ( StepSeq StepName StepStatus IsSkipped
                   DocumentDate ProcessedBy ErrorMessage )
          WITH lt_create
      REPORTED DATA(ld_reported)
      FAILED   DATA(ld_failed).

  ENDMETHOD.


  "=======================================================================
  " VALIDATIONS
  "=======================================================================
  METHOD validateHeader.

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process
        FIELDS ( FromPlant ToPlant TransferDate CompanyCode PurchasingOrg )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_process).

    LOOP AT lt_process ASSIGNING FIELD-SYMBOL(<ls_process>).

      DATA(lv_error) = abap_false.
      DATA lv_text TYPE string.

      IF <ls_process>-FromPlant IS INITIAL OR <ls_process>-ToPlant IS INITIAL.
        lv_error = abap_true.
        lv_text  = |Supplying and receiving plant are both required|.

      ELSEIF <ls_process>-FromPlant = <ls_process>-ToPlant.
        lv_error = abap_true.
        lv_text  = |Supplying and receiving plant must be different|.

      ELSEIF <ls_process>-TransferDate IS INITIAL.
        lv_error = abap_true.
        lv_text  = |Transfer date is required|.

      ELSEIF <ls_process>-CompanyCode IS INITIAL
          OR <ls_process>-PurchasingOrg IS INITIAL.
        lv_error = abap_true.
        lv_text  = |Company code and purchasing organization are required | &&
                   |to create the stock transport order|.

      ELSE.
*        SELECT SINGLE @abap_true FROM i_plant
*          WHERE Plant = @<ls_process>-FromPlant
*          INTO @DATA(lv_from_ok).
*        SELECT SINGLE @abap_true FROM i_plant
*          WHERE Plant = @<ls_process>-ToPlant
*          INTO @DATA(lv_to_ok).
*
*        IF lv_from_ok = abap_false OR lv_to_ok = abap_false.
*          lv_error = abap_true.
*          lv_text  = |Plant does not exist|.
*        ENDIF.
      ENDIF.

      IF lv_error = abap_true.
        APPEND VALUE #( %tky = <ls_process>-%tky ) TO failed-process.
        APPEND VALUE #(
          %tky = <ls_process>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = lv_text )
          %element-FromPlant = if_abap_behv=>mk-on
          %element-ToPlant   = if_abap_behv=>mk-on
        ) TO reported-process.
      ENDIF.

    ENDLOOP.

  ENDMETHOD.


  "=======================================================================
  METHOD validateItems.

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process BY \_Item
        FIELDS ( Material Quantity BaseUnit )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_item)
      LINK DATA(lt_link).

    LOOP AT keys ASSIGNING FIELD-SYMBOL(<ls_key>).

      DATA lt_own LIKE lt_link.
      lt_own = VALUE #( FOR ls IN lt_link
                        WHERE ( source-%tky = <ls_key>-%tky ) ( ls ) ).

      IF lt_own IS INITIAL.
        APPEND VALUE #( %tky = <ls_key>-%tky ) TO failed-process.
        APPEND VALUE #(
          %tky = <ls_key>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = |At least one item is required| )
        ) TO reported-process.
      ENDIF.

    ENDLOOP.

    LOOP AT lt_item ASSIGNING FIELD-SYMBOL(<ls_item>).

      IF <ls_item>-Material IS INITIAL OR <ls_item>-Quantity <= 0.
        APPEND VALUE #( %tky = <ls_item>-%tky ) TO failed-item.
        APPEND VALUE #(
          %tky = <ls_item>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = |Material and a quantity greater than zero | &&
                              |are required| )
          %element-Material = if_abap_behv=>mk-on
          %element-Quantity = if_abap_behv=>mk-on
        ) TO reported-item.
      ENDIF.

    ENDLOOP.

  ENDMETHOD.


*  "=======================================================================
*  METHOD validateNotInProcess.
*
*    READ ENTITIES OF zi_sto_process IN LOCAL MODE
*      ENTITY Process
*        FIELDS ( ProcessingLock CurrentStepSeq )
*        WITH CORRESPONDING #( keys )
*      RESULT DATA(lt_process).
*
*    LOOP AT lt_process ASSIGNING FIELD-SYMBOL(<ls_process>)
*         WHERE CurrentStepSeq > 1.
*
*      APPEND VALUE #( %tky = <ls_process>-%tky ) TO failed-process.
*      APPEND VALUE #(
*        %tky = <ls_process>-%tky
*        %msg = new_message_with_text(
*                 severity = if_abap_behv_message=>severity-error
*                 text     = |Documents already exist for this process - | &&
*                            |header and items can no longer be changed| )
*      ) TO reported-process.
*
*    ENDLOOP.
*
*  ENDMETHOD.


*  "=======================================================================
  METHOD validateConfiguration.

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process
        FIELDS ( ProcessUUID )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_process).

    CHECK lt_process IS NOT INITIAL.

    " Read-only, so it is safe in Prepare as well as on save. Resolving the
    " step definitions also instantiates every handler class, so a mistyped
    " HANDLER_CLASS in ZSTO_STEPCUST is caught here rather than at the first
    " click on "Execute Next Step".
    DATA lv_text TYPE string.

    TRY.
        DATA(lt_def) = zcl_sto_step_factory=>get_instance( )->get_all_steps( ).

        IF lt_def IS INITIAL.
          lv_text = |No active process steps are configured in ZSTO_STEPCUST|.
        ENDIF.

      CATCH zcx_sto_step_error INTO DATA(lx_cfg).
        lv_text = lx_cfg->get_short_text( ).
    ENDTRY.

    CHECK lv_text IS NOT INITIAL.

    LOOP AT lt_process ASSIGNING FIELD-SYMBOL(<ls_process>).
      APPEND VALUE #( %tky = <ls_process>-%tky ) TO failed-process.
      APPEND VALUE #(
        %tky = <ls_process>-%tky
        %msg = new_message_with_text(
                 severity = if_abap_behv_message=>severity-error
                 text     = lv_text )
      ) TO reported-process.
    ENDLOOP.

  ENDMETHOD.


  "=======================================================================
  METHOD get_global_authorizations.
    result-%create = if_abap_behv=>auth-allowed.
  ENDMETHOD.

  METHOD get_instance_authorizations.
    result = VALUE #( FOR ls IN keys
                      ( %tky        = ls-%tky
                        %update     = if_abap_behv=>auth-allowed
                        %delete     = if_abap_behv=>auth-allowed
                        %action-processNextStep = if_abap_behv=>auth-allowed
                        %action-resetFailedStep = if_abap_behv=>auth-allowed ) ).
  ENDMETHOD.

ENDCLASS.


"===========================================================================
" ITEM HANDLER
"===========================================================================
CLASS lhc_item DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.
   TYPES tt_process_read TYPE TABLE FOR READ RESULT zi_sto_process.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR Item RESULT result.

    METHODS deriveMaterialData FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Item~deriveMaterialData.

    METHODS assignItemNumber FOR DETERMINE ON SAVE
      IMPORTING keys FOR Item~assignItemNumber.

    METHODS validateMaterial FOR VALIDATE ON SAVE
      IMPORTING keys FOR Item~validateMaterial.
    METHODS validateUniqueMaterial FOR VALIDATE ON SAVE
       keys FOR Item~validateUniqueMaterial.
           TYPES tt_item_read TYPE TABLE FOR READ RESULT zi_sto_process\\Item.

    METHODS read_headers
      IMPORTING it_item           TYPE tt_item_read
      RETURNING VALUE(rt_header)  TYPE tt_process_read.

*    METHODS validateBatchSum FOR VALIDATE ON SAVE
*       keys FOR Item~validateBatchSum.

ENDCLASS.


CLASS lhc_item IMPLEMENTATION.

  METHOD get_instance_features.

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Item BY \_Process
        FIELDS ( CurrentStepSeq )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_process).

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Item
        FIELDS ( ProcessUUID )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_item).

    LOOP AT lt_item ASSIGNING FIELD-SYMBOL(<ls_item>).

      DATA lv_locked TYPE if_abap_behv=>t_xflag.
      DATA lv_seq    TYPE zsto_step_seq.

      lv_seq = VALUE #( lt_process[ ProcessUUID = <ls_item>-ProcessUUID
                                  ]-CurrentStepSeq OPTIONAL ).

      lv_locked = COND #( WHEN lv_seq > 1
                          THEN if_abap_behv=>fc-o-disabled
                          ELSE if_abap_behv=>fc-o-enabled ).

      APPEND VALUE #( %tky    = <ls_item>-%tky
                      %update = lv_locked
                      %delete = lv_locked ) TO result.
    ENDLOOP.


*    DATA(lo_ctrl) = zcl_sto_field_control=>get_instance( ).
*
*    LOOP AT lt_item ASSIGNING FIELD-SYMBOL(<ls_item>).
*
*      DATA(lv_step) = VALUE zsto_step_seq(
*        lt_header[ ProcessUUID = <ls_item>-ProcessUUID ]-CurrentStepSeq OPTIONAL ).
*
*      DATA(lv_has_batches) = xsdbool(
*        line_exists( lt_link[ source-%tky = <ls_item>-%tky ] ) ).
*
*      " Quantity is read-only for EITHER reason: the step rule says so, or
*      " the line has splits and the number is derived from them. The second
*      " is not configurable - it is not a policy, it is arithmetic.
*      DATA(lv_qty_fc) = COND #(
*        WHEN lv_has_batches = abap_true
*        THEN if_abap_behv=>fc-f-read_only
*        ELSE lo_ctrl->field_feature( iv_object       = zcl_sto_field_control=>co_object-item
*                                     iv_group        = zcl_sto_field_control=>co_group-item_qty
*                                     iv_current_step = lv_step ) ).
*
*      APPEND VALUE #(
*        %tky = <ls_item>-%tky
*
*        %field-Material = lo_ctrl->field_feature(
*                            iv_object       = zcl_sto_field_control=>co_object-item
*                            iv_group        = zcl_sto_field_control=>co_group-item_detail
*                            iv_current_step = lv_step )
*        %field-Quantity = lv_qty_fc
*
*        %delete = lo_ctrl->feature(
*                    iv_object       = zcl_sto_field_control=>co_object-item
*                    iv_group        = zcl_sto_field_control=>co_group-item_delete
*                    iv_current_step = lv_step )
*
*        " THE server-side gate for Assign. The dialog creates batch rows by
*        " association from this item, so disabling the association is what
*        " actually stops it - the button being greyed out is a courtesy, this
*        " is the enforcement.
*        %assoc-_Batch = lo_ctrl->feature(
*                          iv_object       = zcl_sto_field_control=>co_object-item
*                          iv_group        = zcl_sto_field_control=>co_group-batch_assign
*                          iv_current_step = lv_step )
*      ) TO result.
*
*    ENDLOOP.


  ENDMETHOD.


  "=======================================================================
  METHOD deriveMaterialData.

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Item
        FIELDS ( Material BaseUnit Currency )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_item).

    DATA lt_update TYPE TABLE FOR UPDATE zi_sto_process\\Item.

    LOOP AT lt_item ASSIGNING FIELD-SYMBOL(<ls_item>)
         WHERE Material IS NOT INITIAL.

*      SELECT SINGLE BaseUnit FROM i_material
*        WHERE Material = @<ls_item>-Material
*        INTO @DATA(lv_base_unit).
*
*      IF sy-subrc = 0 AND lv_base_unit <> <ls_item>-BaseUnit.
*        APPEND VALUE #( %tky     = <ls_item>-%tky
*                        BaseUnit = lv_base_unit ) TO lt_update.
*      ENDIF.

    ENDLOOP.

    CHECK lt_update IS NOT INITIAL.

    MODIFY ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Item
        UPDATE FIELDS ( BaseUnit )
        WITH lt_update
      REPORTED DATA(ld_reported).

  ENDMETHOD.


  "=======================================================================
  " Assigns the STABLE ANCHOR: 0010, 0020, 0030 ...
  "
  " On the ITEM, not the header, and continues from the highest number
  " already used by its siblings. A header-level "on create" determination
  " would leave items added in a later edit at 0000, collapsing several
  " lines onto the same anchor and destroying the traceability the whole
  " design rests on.
  "=======================================================================
  METHOD assignItemNumber.

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Item
        FIELDS ( ProcessUUID ProcessItem )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_new).

    DELETE lt_new WHERE ProcessItem IS NOT INITIAL.
    CHECK lt_new IS NOT INITIAL.

    DATA lt_update TYPE TABLE FOR UPDATE zi_sto_process\\Item.

    " Group by parent so two processes saved in one LUW do not share a
    " running counter.
    DATA lt_parent TYPE SORTED TABLE OF sysuuid_x16 WITH UNIQUE KEY table_line.
    LOOP AT lt_new ASSIGNING FIELD-SYMBOL(<ls_n>).
      INSERT <ls_n>-ProcessUUID INTO TABLE lt_parent.
    ENDLOOP.

    LOOP AT lt_parent ASSIGNING FIELD-SYMBOL(<lv_parent>).

      " Highest number already persisted for this process. A SELECT is a
      " read - always legal inside the RAP LUW.
      SELECT MAX( process_item ) FROM zsto_process_i
        WHERE process_uuid = @<lv_parent>
        INTO @DATA(lv_max).

      DATA lv_next TYPE zsto_process_item.
      lv_next = lv_max.

      LOOP AT lt_new ASSIGNING FIELD-SYMBOL(<ls_item>)
           WHERE ProcessUUID = <lv_parent>.
        lv_next = lv_next + 10.
        APPEND VALUE #( %tky        = <ls_item>-%tky
                        ProcessItem = lv_next ) TO lt_update.
      ENDLOOP.

    ENDLOOP.

    CHECK lt_update IS NOT INITIAL.

    MODIFY ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Item
        UPDATE FIELDS ( ProcessItem )
        WITH lt_update
      REPORTED DATA(ld_reported).

  ENDMETHOD.


  "=======================================================================
  METHOD validateMaterial.

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Item
        FIELDS ( Material Quantity )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_item).

    LOOP AT lt_item ASSIGNING FIELD-SYMBOL(<ls_item>).

*      SELECT SINGLE @abap_true FROM i_material
*        WHERE Material = @<ls_item>-Material
*        INTO @DATA(lv_exists).
*
*      IF lv_exists = abap_false.
*        APPEND VALUE #( %tky = <ls_item>-%tky ) TO failed-item.
*        APPEND VALUE #(
*          %tky = <ls_item>-%tky
*          %msg = new_message_with_text(
*                   severity = if_abap_behv_message=>severity-error
*                   text     = |Material { <ls_item>-Material } does not exist| )
*          %element-Material = if_abap_behv=>mk-on
*        ) TO reported-item.
*      ENDIF.

    ENDLOOP.

  ENDMETHOD.

  METHOD validateUniqueMaterial.

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
    ENTITY Item
      FIELDS ( ProcessUUID ProcessItem Material )
      WITH CORRESPONDING #( keys )
    RESULT DATA(lt_changed).

    CHECK lt_changed IS NOT INITIAL.

    " Pull every item of every affected process, via the parent, so draft
    " rows are seen too.
    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Item BY \_Process
        FIELDS ( ProcessUUID )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_parent).

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Process BY \_Item
        FIELDS ( ProcessItem Material )
        WITH CORRESPONDING #( lt_parent )
      RESULT DATA(lt_all_items).

    LOOP AT lt_changed ASSIGNING FIELD-SYMBOL(<ls_item>).

      CHECK <ls_item>-Material IS NOT INITIAL.

      DATA lv_hits TYPE i.
      CLEAR lv_hits.
      DATA lv_other TYPE zsto_process_item.
      CLEAR lv_other.

      LOOP AT lt_all_items ASSIGNING FIELD-SYMBOL(<ls_sib>)
           WHERE Material = <ls_item>-Material.
        lv_hits = lv_hits + 1.
        IF <ls_sib>-%tky <> <ls_item>-%tky.
          lv_other = <ls_sib>-ProcessItem.
        ENDIF.
      ENDLOOP.

      CHECK lv_hits > 1.

      APPEND VALUE #( %tky = <ls_item>-%tky ) TO failed-item.
      APPEND VALUE #(
        %tky = <ls_item>-%tky
        %msg = new_message_with_text(
                 severity = if_abap_behv_message=>severity-error
                 text     = |Material { <ls_item>-Material } is already on | &&
                            |item { lv_other }. Enter each material once and | &&
                            |split it across batches instead.| )
        %element-Material = if_abap_behv=>mk-on
      ) TO reported-item.

    ENDLOOP.


  ENDMETHOD.

*  METHOD validateBatchSum.
*
*    READ ENTITIES OF zi_sto_process IN LOCAL MODE
*    ENTITY Item
*      FIELDS ( ProcessItem Material Quantity BaseUnit )
*      WITH CORRESPONDING #( keys )
*    RESULT DATA(lt_item).
*
*    READ ENTITIES OF zi_sto_process IN LOCAL MODE
*      ENTITY Item BY \_Batch
*        FIELDS ( Quantity )
*        WITH CORRESPONDING #( keys )
*      RESULT DATA(lt_batch)
*      LINK   DATA(lt_link).
*
*    LOOP AT lt_item ASSIGNING FIELD-SYMBOL(<ls_item>).
*
*      DATA lv_sum TYPE menge_d.
*      CLEAR lv_sum.
*
*      LOOP AT lt_link ASSIGNING FIELD-SYMBOL(<ls_link>)
*           WHERE source-%tky = <ls_item>-%tky.
*        DATA(ls_b) = VALUE #( lt_batch[ %tky = <ls_link>-target-%tky ] OPTIONAL ).
*        lv_sum = lv_sum + ls_b-Quantity.
*      ENDLOOP.
*
*      IF lv_sum = <ls_item>-Quantity.
*        CONTINUE.
*      ENDIF.
*
*      APPEND VALUE #( %tky = <ls_item>-%tky ) TO failed-item.
*
*      APPEND VALUE #(
*        %tky = <ls_item>-%tky
*        %msg = new_message_with_text(
*                 severity = if_abap_behv_message=>severity-error
*                 text     = COND #(
*                   WHEN lv_sum IS INITIAL
*                     THEN |Item { <ls_item>-ProcessItem } | &&
*                          |({ <ls_item>-Material }): no batches selected. | &&
*                          |Choose batches for { <ls_item>-Quantity } | &&
*                          |{ <ls_item>-BaseUnit }.|
*                   WHEN lv_sum < <ls_item>-Quantity
*                     THEN |Item { <ls_item>-ProcessItem }: batch quantities | &&
*                          |total { lv_sum } { <ls_item>-BaseUnit }, | &&
*                          |{ <ls_item>-Quantity - lv_sum } short of the | &&
*                          |line quantity { <ls_item>-Quantity }.|
*                   ELSE     |Item { <ls_item>-ProcessItem }: batch quantities | &&
*                            |total { lv_sum } { <ls_item>-BaseUnit }, | &&
*                            |{ lv_sum - <ls_item>-Quantity } more than the | &&
*                            |line quantity { <ls_item>-Quantity }.| ) )
*        %element-Quantity = if_abap_behv=>mk-on
*      ) TO reported-item.
*
*    ENDLOOP.
*
*
*  ENDMETHOD.

  METHOD read_headers.

    READ ENTITIES OF zi_sto_process IN LOCAL MODE
      ENTITY Item BY \_Process
        FIELDS ( ProcessUUID CurrentStepSeq OverallStatus FromPlant FromStorLoc )
        WITH CORRESPONDING #( it_item )
      RESULT rt_header.

  ENDMETHOD.

ENDCLASS.

