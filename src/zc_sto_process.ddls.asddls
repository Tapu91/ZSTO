@EndUserText.label: 'STO Process - Header (Projection)'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true
@Search.searchable: true
@ObjectModel.semanticKey: [ 'ProcessID' ]

define root view entity ZC_STO_Process
  provider contract transactional_query
  as projection on ZI_STO_Process
{
  key ProcessUUID,

      @Search.defaultSearchElement: true
      @Search.fuzzinessThreshold: 0.8
      ProcessID,

      @Search.defaultSearchElement: true
//      @Consumption.valueHelpDefinition: [{ entity: { name: 'I_PlantStdVH', element: 'Plant' } }]
      FromPlant,
      @Search.defaultSearchElement: true
//      @Consumption.valueHelpDefinition: [{ entity: { name: 'I_PlantStdVH', element: 'Plant' } }]
      ToPlant,
//      @Consumption.valueHelpDefinition: [{ entity: { name: 'I_StorageLocationStdVH', element: 'StorageLocation' },
//                                           additionalBinding: [{ localElement: 'FromPlant', element: 'Plant' }] }]
      FromStorLoc,
//      @Consumption.valueHelpDefinition: [{ entity: { name: 'I_StorageLocationStdVH', element: 'StorageLocation' },
//                                           additionalBinding: [{ localElement: 'ToPlant', element: 'Plant' }] }]
      ToStorLoc,
      TransferDate,

      CompanyCode,
      PurchasingOrg,
      PurchasingGroup,
      PODocumentType,
      ShippingPoint,
      IsIntercompany,

      CurrentStepSeq,
      OverallStatus,
      OverallStatusText,
      ProcessingLock,
      NextActionText,
      StatusCriticality,

      PurchaseOrder,
      OutboundDelivery,
      GIMaterialDoc,
      GIMaterialDocYear,
      BillingDocument,
      GRMaterialDoc,
      GRMaterialDocYear,

      CreatedBy,
      CreatedAt,
      LastChangedBy,
      LastChangedAt,
      LocalLastChangedAt,

      /* Associations */
      _Item  : redirected to composition child ZC_STO_ProcessItem,
      _Step  : redirected to composition child ZC_STO_ProcessStep,
      _ItemDoc : redirected to composition child ZC_STO_ProcessItemDoc
}
