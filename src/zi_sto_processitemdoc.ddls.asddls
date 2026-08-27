@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'STO Process - Item/Document Mapping'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType:{
  serviceQuality: #X,
  sizeCategory:   #S,
  dataClass:      #TRANSACTIONAL
}
define view entity ZI_STO_ProcessItemDoc
  as select from zsto_proc_idoc

  association to parent ZI_STO_Process as _Process on $projection.ProcessUUID = _Process.ProcessUUID

{
  key mapping_uuid                                              as MappingUUID,

      process_uuid                                              as ProcessUUID,
      process_item                                              as ProcessItem,
      step_seq                                                  as StepSeq,
      step_name                                                 as StepName,

      document_number                                           as DocumentNumber,
      document_item                                             as DocumentItem,
      document_year                                             as DocumentYear,

      @Semantics.quantity.unitOfMeasure: 'BaseUnit'
      quantity                                                  as Quantity,
      base_unit                                                 as BaseUnit,
      batch                                                     as Batch, // <-- NEW
      po_item_no                                                as PoItemNo, // <-- NEW
      // "4500001234 / 000030" for the connection-label popover
      concat( concat( document_number, ' / ' ), document_item ) as DocumentDisplay,

      @Semantics.user.createdBy: true
      created_by                                                as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at                                                as CreatedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at                                     as LocalLastChangedAt,

      _Process
}
