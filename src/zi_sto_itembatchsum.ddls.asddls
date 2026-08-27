@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'STO - Assigned Batch Quantity per Item'
@Metadata.ignorePropagatedAnnotations: true

define view entity ZI_STO_ItemBatchSum
  as select from zsto_proc_batch
{
  key item_uuid                 as ItemUUID,

//      @Semantics.quantity.unitOfMeasure: 'BaseUnit'
      sum( cast ( quantity as abap.dec( 13, 3 ) ) ) as AssignedQuantity,
      max( cast ( base_unit as char3 ) )   as BaseUnit,
      count( * )                as BatchCount
}
group by
  item_uuid
