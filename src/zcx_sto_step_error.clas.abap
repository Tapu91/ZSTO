CLASS zcx_sto_step_error DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES if_t100_dyn_msg.
    INTERFACES if_t100_message.

    DATA mv_step_name TYPE zsto_step_name READ-ONLY.
    DATA mt_bapiret   TYPE zsto_bapiret2     READ-ONLY.

    METHODS constructor
      IMPORTING
        textid    LIKE if_t100_message=>t100key OPTIONAL
        previous  LIKE previous                 OPTIONAL
        step_name TYPE zsto_step_name           OPTIONAL
        bapiret   TYPE zsto_bapiret2              OPTIONAL
        text      TYPE string                   OPTIONAL.

    "! Condenses the BAPI return table into a single line that fits
    "! ZSTO_PROCESS_STEP-ERROR_MESSAGE (220 chars) for display on the
    "! ProcessFlow node.
    METHODS get_short_text
      RETURNING VALUE(rv_text) TYPE zsto_error_message.

    "! CX_ROOT implements IF_MESSAGE, so this is a redefinition - it must be
    "! declared here or the class will not activate.
    METHODS if_message~get_text REDEFINITION.

    "! Convenience factory: raises only if the BAPI return table contains
    "! an E / A / X message. Returns quietly otherwise.
    CLASS-METHODS raise_if_error
      IMPORTING
        it_bapiret TYPE zsto_bapiret2
        iv_step    TYPE zsto_step_name
      RAISING
        zcx_sto_step_error.

    CLASS-METHODS has_error
      IMPORTING
        it_bapiret      TYPE zsto_bapiret2
      RETURNING
        VALUE(rv_error) TYPE abap_bool.

  PRIVATE SECTION.
    DATA mv_text TYPE string.

ENDCLASS.


CLASS zcx_sto_step_error IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.
    super->constructor( previous = previous ).

    me->mv_step_name = step_name.
    me->mt_bapiret   = bapiret.
    me->mv_text      = text.

    CLEAR me->textid.
    IF textid IS INITIAL.
      if_t100_message~t100key = if_t100_message=>default_textid.
    ELSE.
      if_t100_message~t100key = textid.
    ENDIF.
  ENDMETHOD.


  METHOD has_error.
    rv_error = xsdbool( line_exists( it_bapiret[ type = 'E' ] )
                     OR line_exists( it_bapiret[ type = 'A' ] )
                     OR line_exists( it_bapiret[ type = 'X' ] ) ).
  ENDMETHOD.


  METHOD raise_if_error.
    IF has_error( it_bapiret ) = abap_false.
      RETURN.
    ENDIF.

    RAISE EXCEPTION NEW zcx_sto_step_error( step_name = iv_step
                                            bapiret   = it_bapiret ).
  ENDMETHOD.


  METHOD get_short_text.
    DATA lv_text TYPE string.

    IF mv_text IS NOT INITIAL.
      lv_text = mv_text.
    ELSE.
      LOOP AT mt_bapiret ASSIGNING FIELD-SYMBOL(<ls_ret>)
           WHERE type CA 'EAX'.
        IF lv_text IS INITIAL.
          lv_text = <ls_ret>-message.
        ELSE.
          lv_text = |{ lv_text } / { <ls_ret>-message }|.
        ENDIF.
      ENDLOOP.
    ENDIF.

    IF lv_text IS INITIAL.
      lv_text = |Step { mv_step_name } failed without a message|.
    ENDIF.

    rv_text = lv_text.   " truncates to 220 by assignment
  ENDMETHOD.


  METHOD if_message~get_text.
    result = CONV #( get_short_text( ) ).
  ENDMETHOD.

ENDCLASS.


