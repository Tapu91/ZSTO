@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'STO - Available Batch Stock (FEFO)'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType:{ serviceQuality: #B, sizeCategory: #M, dataClass: #MIXED }

define view entity ZI_STO_BatchStockVH
  as select from zsto_batch_help
{
  key material                        as Material,
  key plant                           as Plant,
  key storagelocation                 as StorageLocation,
  key batch                           as Batch,
      //
      @Semantics.quantity.unitOfMeasure: 'BaseUnit'
      availablequantity as AvailableQuantity,
      baseunit                        as BaseUnit,
      //
      cast( '00000000' as abap.dats ) as ExpiryDate,

      case when cast( expirydate as abap.dats ) = '00000000'
           then 1 else 0 end          as NoExpirySort
}
where
      availablequantity > 0
