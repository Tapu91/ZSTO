@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'STO Process - Header (Interface)'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType:{
  serviceQuality: #X,
  sizeCategory:   #S,
  dataClass:      #TRANSACTIONAL
}
define root view entity ZI_STO_Process
  as select from zsto_process_h

  composition [0..*] of ZI_STO_ProcessItem    as _Item
  composition [0..*] of ZI_STO_ProcessStep    as _Step
  composition [0..*] of ZI_STO_ProcessItemDoc as _ItemDoc
  association [0..*] to ZI_STO_ProcessBatch   as _Batch        on  $projection.ProcessUUID = _Batch.ProcessUUID

  //  association [0..1] to I_Plant     as _FromPlantVH on $projection.FromPlant = _FromPlantVH.Plant
  //  association [0..1] to I_Plant     as _ToPlantVH   on $projection.ToPlant   = _ToPlantVH.Plant

{
  key process_uuid          as ProcessUUID,

      process_id            as ProcessID,

      from_plant            as FromPlant,
      to_plant              as ToPlant,
      from_stor_loc         as FromStorLoc,
      to_stor_loc           as ToStorLoc,
      transfer_date         as TransferDate,

      comp_code             as CompanyCode,
      purch_org             as PurchasingOrg,
      purch_group           as PurchasingGroup,
      po_doc_type           as PODocumentType,
      shipping_point        as ShippingPoint,
      is_intercompany       as IsIntercompany,

      current_step_seq      as CurrentStepSeq,
      @ObjectModel.text.element: [ 'OverallStatusText' ]
      overall_status        as OverallStatus,
      @Semantics.text: true
      case overall_status
        when '10' then cast( 'Requested'          as abap.char( 40 ) )
        when '20' then cast( 'PO Created'         as abap.char( 40 ) )
        when '30' then cast( 'Delivery Created'   as abap.char( 40 ) )
        when '40' then cast( 'Goods Issue Posted' as abap.char( 40 ) )
        when '50' then cast( 'Billed'             as abap.char( 40 ) )
        when '60' then cast( 'Completed'          as abap.char( 40 ) )
        when '90' then cast( 'Error'              as abap.char( 40 ) )
        else           cast( ' '                  as abap.char( 40 ) )
      end                   as OverallStatusText,
      processing_lock       as ProcessingLock,

      purchase_order        as PurchaseOrder,
      outbound_delivery     as OutboundDelivery,
      gi_material_doc       as GIMaterialDoc,
      gi_material_doc_year  as GIMaterialDocYear,
      billing_document      as BillingDocument,
      gr_material_doc       as GRMaterialDoc,
      gr_material_doc_year  as GRMaterialDocYear,

      // ---- derived, not persisted -------------------------------------
      // Label for the single action button on the object page.
      case current_step_seq
        when '001' then cast( 'Create Request'          as abap.char( 40 ) )
        when '002' then cast( 'Create Purchase Order'   as abap.char( 40 ) )
        when '003' then cast( 'Create Outbound Delivery' as abap.char( 40 ) )
        when '004' then cast( 'Post Goods Issue'        as abap.char( 40 ) )
        when '005' then cast( 'Create Billing Document' as abap.char( 40 ) )
        when '006' then cast( 'Post Goods Receipt'      as abap.char( 40 ) )
        else        cast( ' '                       as abap.char( 40 ) )
      end                   as NextActionText,

      // Criticality for the status field in the List Report
      // 0 neutral / 1 red / 2 yellow / 3 green
      case overall_status
        when '90' then 1
        when '60' then 3
        else           2
      end                   as StatusCriticality,

      @Semantics.user.createdBy: true
      created_by            as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at            as CreatedAt,
      @Semantics.user.lastChangedBy: true
      last_changed_by       as LastChangedBy,
      @Semantics.systemDateTime.lastChangedAt: true
      last_changed_at       as LastChangedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,

      _Item,
      _Step,
      _ItemDoc,
      _Batch
      //      _FromPlantVH,
      //      _ToPlantVH
}
