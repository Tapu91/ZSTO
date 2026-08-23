CLASS zcl_update_sto_config DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES if_oo_adt_classrun .
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_update_sto_config IMPLEMENTATION.


  METHOD if_oo_adt_classrun~main.

    DATA lt_cust TYPE STANDARD TABLE OF zsto_stepcust.

    lt_cust = VALUE #(
      ( step_seq = 1 step_name = 'REQUEST'  handler_class = ''
        status_on_success = '10' is_active = abap_true )
      ( step_seq = 2 step_name = 'PO'       handler_class = 'ZCL_STO_STEP_PO'
        status_on_success = '20' is_active = abap_true )
      ( step_seq = 3 step_name = 'DELIVERY' handler_class = 'ZCL_STO_STEP_DELIVERY'
        status_on_success = '30' is_active = abap_true )
      ( step_seq = 4 step_name = 'PGI'      handler_class = 'ZCL_STO_STEP_PGI'
        status_on_success = '40' is_active = abap_true )
      ( step_seq = 5 step_name = 'BILLING'  handler_class = 'ZCL_STO_STEP_BILLING'
        status_on_success = '50' only_intercompany = abap_true is_active = abap_true )
      ( step_seq = 6 step_name = 'GR'       handler_class = 'ZCL_STO_STEP_GR'
        status_on_success = '60' is_active = abap_true ) ).

    MODIFY zsto_stepcust FROM TABLE @lt_cust.
    COMMIT WORK.

  ENDMETHOD.
ENDCLASS.
