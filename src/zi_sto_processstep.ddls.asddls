@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'STO Process - Step Log (Interface)'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType:{
  serviceQuality: #X,
  sizeCategory:   #S,
  dataClass:      #TRANSACTIONAL
}
define view entity ZI_STO_ProcessStep
  as select from zsto_proc_step

  association        to parent ZI_STO_Process as _Process
    on $projection.ProcessUUID = _Process.ProcessUUID

  association [0..*] to ZI_STO_ProcessItemDoc as _ItemDoc
    on  $projection.ProcessUUID = _ItemDoc.ProcessUUID
    and $projection.StepSeq     = _ItemDoc.StepSeq

{
  key step_uuid           as StepUUID,

      process_uuid        as ProcessUUID,
      step_seq            as StepSeq,
      step_name           as StepName,
      step_status         as StepStatus,

      document_number     as DocumentNumber,
      document_year       as DocumentYear,
      document_date       as DocumentDate,
      error_message       as ErrorMessage,
      is_skipped          as IsSkipped,

      // ------------------------------------------------------------------
      // Drives sap.suite.ui.commons.ProcessFlowNode directly.
      // ProcessFlowState: Planned / Critical / Positive / Negative
      // ------------------------------------------------------------------
      case
        when is_skipped  = 'X' then cast( 'Planned'  as abap.char( 10 ) )
        when step_status = 'P' then cast( 'Critical' as abap.char( 10 ) )
        when step_status = 'S' then cast( 'Positive' as abap.char( 10 ) )
        when step_status = 'E' then cast( 'Negative' as abap.char( 10 ) )
        else                        cast( 'Planned'  as abap.char( 10 ) )
      end                 as FlowState,

      // stateText shown under the node: doc number, or the error text
      case
        when is_skipped  = 'X' then cast( 'Not applicable' as abap.char( 220 ) )
        when step_status = 'E' then cast( error_message    as abap.char( 220 ) )
        when step_status = 'S' then cast( document_number  as abap.char( 220 ) )
        else                        cast( ' '              as abap.char( 220 ) )
      end                 as FlowStateText,

      // Node id / lane id consumed by the ProcessFlow control.
      // ZSTO_STEP_SEQ is NUMC(3) - character-like, so it concatenates
      // directly. (CDS would reject an INT1 -> NUMC cast, which is why the
      // data element is NUMC and not INT1.)
      concat( 'NODE_', step_seq ) as FlowNodeId,
      concat( 'LANE_', step_seq ) as FlowLaneId,

      case step_name
        when 'REQUEST'  then cast( 'sap-icon://request'          as abap.char( 40 ) )
        when 'PO'       then cast( 'sap-icon://sales-order'      as abap.char( 40 ) )
        when 'DELIVERY' then cast( 'sap-icon://shipping-status'  as abap.char( 40 ) )
        when 'PGI'      then cast( 'sap-icon://goods-issue'      as abap.char( 40 ) )
        when 'BILLING'  then cast( 'sap-icon://money-bills'      as abap.char( 40 ) )
        when 'GR'       then cast( 'sap-icon://cart'             as abap.char( 40 ) )
        else                 cast( 'sap-icon://circle-task'      as abap.char( 40 ) )
      end                 as FlowIcon,

      case step_status
        when 'E' then 1
        when 'S' then 3
        when 'P' then 2
        else          0
      end                 as StatusCriticality,

      @Semantics.user.lastChangedBy: true
      processed_by        as ProcessedBy,
      @Semantics.systemDateTime.lastChangedAt: true
      processed_at        as ProcessedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,

      _Process,
      _ItemDoc
}
