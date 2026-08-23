@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'STO Process - Horizontal Item Trace'
@Metadata.ignorePropagatedAnnotations: true

// ---------------------------------------------------------------------------
// Pivots ZSTO_PROC_IDOC from one-row-per-step into one-row-per-process-item
// with a column per step. This is what makes the line-level traceability
// visible directly in the object page item table:
//
//  Item | Material | PO Item          | Delivery Item   | GR Item
//  0030 | MAT-123  | 4500001234/30    | 80000241/10     | 5000000777/1
//
// MAX() is used purely as a pivot aggregate - for the linear one-document-
// per-step flow each (item, step) pair has exactly one row. If you later
// introduce partial delivery / partial GR, this view shows the LAST document
// per step and ZI_STO_ProcessItemDoc remains the complete record.
// ---------------------------------------------------------------------------

define view entity ZI_STO_ProcessItemTrace
  as select from zsto_proc_idoc
{
  key process_uuid                                                  as ProcessUUID,
  key process_item                                                  as ProcessItem,

      max( case when step_seq = '002' then document_number else ' ' end )        as PODocument,
      max( case when step_seq = '002' then document_item else cast ( ' ' as zsto_doc_item ) end )        as POItem,

      max( case when step_seq = '003' then document_number else ' ' end )        as DeliveryDocument,
      max( case when step_seq = '003' then document_item   else cast ( ' ' as zsto_doc_item ) end )        as DeliveryItem,

      max( case when step_seq = '004' then document_number else ' ' end )        as GIMaterialDoc,
      max( case when step_seq = '004' then document_item   else cast ( ' ' as zsto_doc_item ) end )        as GIMaterialDocItem,

      max( case when step_seq = '005' then document_number else ' ' end )        as BillingDocument,
      max( case when step_seq = '005' then document_item   else cast ( ' ' as zsto_doc_item ) end )        as BillingItem,

      max( case when step_seq = '006' then document_number else ' ' end )        as GRMaterialDoc,
      max( case when step_seq = '006' then document_item   else cast ( ' ' as zsto_doc_item ) end )  as GRMaterialDocItem
}
group by
  process_uuid,
  process_item
