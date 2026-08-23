@EndUserText.label: 'STO Process - Item/Document Mapping'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true

define view entity ZC_STO_ProcessItemDoc
//  provider contract transactional_query
  as projection on ZI_STO_ProcessItemDoc
{
  key MappingUUID,

      ProcessUUID,
      ProcessItem,
      StepSeq,
      StepName,

      DocumentNumber,
      DocumentItem,
      DocumentYear,
      DocumentDisplay,

      Quantity,
      BaseUnit,

      CreatedBy,
      CreatedAt,
      LocalLastChangedAt,

      /* Associations */
      _Process : redirected to parent ZC_STO_Process
}
