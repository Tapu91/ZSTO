@EndUserText.label: 'STO Process - Batch Split (Projection)'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true

define view entity ZC_STO_ProcessBatch
  as projection on ZI_STO_ProcessBatch
{
  key BatchUUID,

      ProcessUUID,
      ItemUUID,
      ProcessItem,

      Batch,
      Quantity,
      BaseUnit,

      ExpiryDate,
      AvailableQuantity,
      StorageLocation,
      DaysToExpiry,
      ExpiryCriticality,

      PoItemNo,

      LocalLastChangedAt,

      /* Associations */
      _Item : redirected to parent ZC_STO_ProcessItem,
      _Process : redirected to ZC_STO_Process
}
