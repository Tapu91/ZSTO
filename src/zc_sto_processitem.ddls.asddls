@EndUserText.label: 'STO Process - Item (Projection)'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true

define view entity ZC_STO_ProcessItem
//  provider contract transactional_query
  as projection on ZI_STO_ProcessItem
{
  key ItemUUID,

      ProcessUUID,
      ProcessItem,

//      @Consumption.valueHelpDefinition: [{ entity: { name: 'I_MaterialStdVH', element: 'Material' } }]
      Material,
      Quantity,
      BaseUnit,
      ItemValue,
      Currency,
//      @Consumption.valueHelpDefinition: [{ entity: { name: 'I_BatchStdVH', element: 'Batch' },
//                                           additionalBinding: [{ localElement: 'Material', element: 'Material' }] }]
      Batch,

      LocalLastChangedAt,
      BatchAssignAllowed,

      /* Read-only trace columns shown directly in the item table */
      _Trace.PODocument        as PODocument,
      _Trace.POItem            as POItem,
      _Trace.DeliveryDocument  as DeliveryDocument,
      _Trace.DeliveryItem      as DeliveryItem,
      _Trace.GIMaterialDoc     as GIMaterialDoc,
      _Trace.BillingDocument   as BillingDocument,
      _Trace.GRMaterialDoc     as GRMaterialDoc,
      _Trace.GRMaterialDocItem as GRMaterialDocItem,

      /* Associations */
      _Process : redirected to parent ZC_STO_Process,
      _ItemDoc : redirected to ZC_STO_ProcessItemDoc,
      _Batch : redirected to composition child ZC_STO_ProcessBatch
//      _Material
}
