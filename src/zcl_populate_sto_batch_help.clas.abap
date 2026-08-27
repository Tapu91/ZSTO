CLASS zcl_populate_sto_batch_help DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun .
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.


CLASS zcl_populate_sto_batch_help IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    DATA: lt_dummy_data TYPE TABLE OF zsto_batch_help,
          ls_dummy_data LIKE LINE OF lt_dummy_data,
          lv_date       TYPE d.

    lv_date = cl_abap_context_info=>get_system_date( ).

    " Clear existing data first to ensure clean execution
    DELETE FROM zsto_batch_help.

    " 1. Record 1: Material A, Plant 1010, Loc 0001 - Normal Batch
    ls_dummy_data = VALUE #(
      client            = sy-mandt
      material          = 'MAT-100-01'
      plant             = '1010'
      storagelocation   = '0001'
      batch             = 'BATCH00001'
      availablequantity = '150.000'
      baseunit          = 'KG'
      expirydate        = lv_date + 180
      noexpirysort      = 0
    ).
    APPEND ls_dummy_data TO lt_dummy_data.

    " 2. Record 2: Material A, Plant 1010, Loc 0001 - Near Expiry Batch
    ls_dummy_data = VALUE #(
      client            = sy-mandt
      material          = 'MAT-100-01'
      plant             = '1010'
      storagelocation   = '0001'
      batch             = 'BATCH00002'
      availablequantity = '45.500'
      baseunit          = 'KG'
      expirydate        = lv_date + 15
      noexpirysort      = 0
    ).
    APPEND ls_dummy_data TO lt_dummy_data.



      ls_dummy_data = VALUE #(
      client            = sy-mandt
      material          = '000000000000001000'
      plant             = '1000'
      storagelocation   = 'L001'
      batch             = 'BATCH00002'
      availablequantity = '45.500'
      baseunit          = 'KG'
      expirydate        = lv_date + 15
      noexpirysort      = 0
    ).
    APPEND ls_dummy_data TO lt_dummy_data.

    " 3. Record 3: Material A, Plant 1020, Loc 0002 - No Expiry Date Flagged
    ls_dummy_data = VALUE #(
      client            = sy-mandt
      material          = 'MAT-100-01'
      plant             = '1020'
      storagelocation   = '0002'
      batch             = 'BATCH00003'
      availablequantity = '500.000'
      baseunit          = 'KG'
      expirydate        = '00000000'
      noexpirysort      = 1
    ).
    APPEND ls_dummy_data TO lt_dummy_data.

    " 4. Record 4: Material B, Plant 1010, Loc 0001 - High Quantity
    ls_dummy_data = VALUE #(
      client            = sy-mandt
      material          = 'MAT-200-99'
      plant             = '1010'
      storagelocation   = '0001'
      batch             = 'BATCH00004'
      availablequantity = '1250.750'
      baseunit          = 'PC'
      expirydate        = lv_date + 365
      noexpirysort      = 0
    ).
    APPEND ls_dummy_data TO lt_dummy_data.

    " Insert all records into table
    INSERT zsto_batch_help FROM TABLE @lt_dummy_data.

    " Console Output
    IF sy-subrc = 0.
      out->write( |Successfully inserted { lines( lt_dummy_data ) } dummy records into zsto_batch_help.| ).
    ELSE.
      out->write( |Error inserting records. SY-SUBRC: { sy-subrc }| ).
    ENDIF.

  ENDMETHOD.
ENDCLASS.
