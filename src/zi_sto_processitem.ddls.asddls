@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'STO Process - Item (Interface)'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType:{
  serviceQuality: #X,
  sizeCategory:   #S,
  dataClass:      #TRANSACTIONAL
}
define view entity ZI_STO_ProcessItem
  as select from zsto_process_i

  association        to parent ZI_STO_Process     as _Process
    on $projection.ProcessUUID = _Process.ProcessUUID

  // All documents this one line produced, across every step.
  association [0..*] to ZI_STO_ProcessItemDoc     as _ItemDoc
    on  $projection.ProcessUUID = _ItemDoc.ProcessUUID
    and $projection.ProcessItem = _ItemDoc.ProcessItem

  // Flattened one-row-per-line trace (PO item / delivery item / GR item ...)
  association [0..1] to ZI_STO_ProcessItemTrace   as _Trace
    on  $projection.ProcessUUID = _Trace.ProcessUUID
    and $projection.ProcessItem = _Trace.ProcessItem

//  association [0..1] to I_Material                as _Material
//    on $projection.Material = _Material.Material

{
  key item_uuid               as ItemUUID,

      process_uuid            as ProcessUUID,
      process_item            as ProcessItem,

      material                as Material,
      @Semantics.quantity.unitOfMeasure: 'BaseUnit'
      quantity                as Quantity,
      base_unit               as BaseUnit,
      @Semantics.amount.currencyCode: 'Currency'
      item_value              as ItemValue,
      currency                as Currency,
      batch                   as Batch,

      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at   as LocalLastChangedAt,

      _Process,
      _ItemDoc,
      _Trace
//      _Material
}
