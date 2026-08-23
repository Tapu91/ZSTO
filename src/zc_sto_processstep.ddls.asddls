@EndUserText.label: 'STO Process - Step Log (Projection)'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true

define view entity ZC_STO_ProcessStep
//  provider contract transactional_query
  as projection on ZI_STO_ProcessStep
{
  key StepUUID,

      ProcessUUID,
      StepSeq,
      StepName,
      StepStatus,

      DocumentNumber,
      DocumentYear,
      DocumentDate,
      ErrorMessage,
      IsSkipped,

      /* Consumed by sap.suite.ui.commons.ProcessFlow */
      FlowState,
      FlowStateText,
      FlowNodeId,
      FlowLaneId,
      FlowIcon,
      StatusCriticality,

      ProcessedBy,
      ProcessedAt,
      LocalLastChangedAt,

      /* Associations */
      _Process : redirected to parent ZC_STO_Process,
      _ItemDoc : redirected to ZC_STO_ProcessItemDoc
}
