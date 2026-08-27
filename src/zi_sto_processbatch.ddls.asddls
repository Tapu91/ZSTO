@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'STO Process - Batch Split (Interface)'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType:{
  serviceQuality: #X,
  sizeCategory:   #S,
  dataClass:      #TRANSACTIONAL
}
define view entity ZI_STO_ProcessBatch
  as select from zsto_proc_batch

  association        to parent ZI_STO_ProcessItem as _Item
    on $projection.ItemUUID = _Item.ItemUUID

  association [1..1] to ZI_STO_Process            as _Process
    on $projection.ProcessUUID = _Process.ProcessUUID
    
    

{
  key batch_uuid            as BatchUUID,

      process_uuid          as ProcessUUID,
      item_uuid             as ItemUUID,
      process_item          as ProcessItem,

      batch                 as Batch,

      @Semantics.quantity.unitOfMeasure: 'BaseUnit'
      quantity              as Quantity,
      base_unit             as BaseUnit,

      expiry_date           as ExpiryDate,
      @Semantics.quantity.unitOfMeasure: 'BaseUnit'
      available_qty         as AvailableQuantity,
      stor_loc              as StorageLocation,

      po_item_no            as PoItemNo,

      // Days to expiry, negative when already expired. Drives the amber /
      // red colouring in the batch list so a short-dated batch is obvious
      // without the user reading dates.
      dats_days_between( $session.system_date, expiry_date ) as DaysToExpiry,

      case
        when expiry_date = '00000000'                             then 0
        when dats_days_between( $session.system_date,
                                expiry_date ) < 0                 then 1
        when dats_days_between( $session.system_date,
                                expiry_date ) <= 30               then 2
        else                                                           3
      end                   as ExpiryCriticality,

      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,

      _Item,
      _Process
}
