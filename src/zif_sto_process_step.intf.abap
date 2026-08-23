INTERFACE zif_sto_process_step
  PUBLIC.

  TYPES:
    "! Header and items are typed on the CDS VIEWS, not on the database
    "! tables. That is deliberate: the CDS element names (ProcessUUID,
    "! FromPlant, ...) are identical to the names in the RAP derived types,
    "! so the behavior pool can fill them with a plain CORRESPONDING #( )
    "! instead of ~20 lines of hand-written field assignments.
    ty_header TYPE ZI_STO_Process.

  TYPES:
    tt_item TYPE STANDARD TABLE OF zi_sto_processitem WITH EMPTY KEY.

  TYPES:
    "! ONE ROW PER PROCESS ITEM that ended up in the created document.
    "! This is what makes line-level traceability work: the handler tells
    "! the engine which document item corresponds to which stable process
    "! item. The engine persists it - the handler never writes.
    BEGIN OF ty_item_doc_map,
      process_item    TYPE zsto_process_item,
      document_number TYPE zsto_doc_number,
      document_item   TYPE zsto_doc_item,
      document_year   TYPE zsto_doc_year,
      quantity        TYPE menge_d,
      base_unit       TYPE meins,
    END OF ty_item_doc_map,
    tt_item_doc_map TYPE STANDARD TABLE OF ty_item_doc_map WITH EMPTY KEY.

  TYPES:
    BEGIN OF ty_step_result,
      document_number TYPE zsto_doc_number,
      document_year   TYPE zsto_doc_year,
      document_date   TYPE datum,
      item_mapping    TYPE tt_item_doc_map,
      messages        TYPE zsto_bapiret2,
    END OF ty_step_result.

  CONSTANTS:
    BEGIN OF gc_step_name,
      request  TYPE zsto_step_name VALUE 'REQUEST',
      po       TYPE zsto_step_name VALUE 'PO',
      delivery TYPE zsto_step_name VALUE 'DELIVERY',
      pgi      TYPE zsto_step_name VALUE 'PGI',
      billing  TYPE zsto_step_name VALUE 'BILLING',
      gr       TYPE zsto_step_name VALUE 'GR',
    END OF gc_step_name.

  CONSTANTS:
    BEGIN OF gc_step_status,
      open       TYPE zsto_step_status VALUE 'O',
      in_process TYPE zsto_step_status VALUE 'P',
      success    TYPE zsto_step_status VALUE 'S',
      error      TYPE zsto_step_status VALUE 'E',
    END OF gc_step_status.

  CONSTANTS:
    BEGIN OF gc_overall_status,
      requested TYPE zsto_overall_status VALUE '10',
      po_create TYPE zsto_overall_status VALUE '20',
      delivered TYPE zsto_overall_status VALUE '30',
      gi_posted TYPE zsto_overall_status VALUE '40',
      billed    TYPE zsto_overall_status VALUE '50',
      completed TYPE zsto_overall_status VALUE '60',
      error     TYPE zsto_overall_status VALUE '90',
    END OF gc_overall_status.

  "! Creates exactly ONE document and returns its number plus the item-level
  "! mapping back to the process items.
  "!
  "! CONTRACT:
  "!  - No commit, no direct DB write, no classic FM (see class docu above).
  "!  - On a business error: raise ZCX_STO_STEP_ERROR. The engine will mark
  "!    the step 'E' and leave CURRENT_STEP_SEQ untouched so the next click
  "!    retries the SAME step. RAP rolls the LUW back, so nothing the handler
  "!    created via EML is persisted - a retry is therefore always safe and
  "!    cannot produce a duplicate document.
  METHODS execute
    IMPORTING
      is_header        TYPE ty_header
      it_item          TYPE tt_item
    RETURNING
      VALUE(rs_result) TYPE ty_step_result
    RAISING
      zcx_sto_step_error.

  "! Lets a step opt out for a given process (e.g. Billing is skipped for
  "! intracompany STOs). Default implementation in ZCL_STO_STEP_BASE reads
  "! the ONLY_INTERCOMPANY / ONLY_INTRACOMPANY flags from ZSTO_STEPCUST.
  METHODS is_applicable
    IMPORTING
      is_header            TYPE ty_header
    RETURNING
      VALUE(rv_applicable) TYPE abap_bool.

ENDINTERFACE.
