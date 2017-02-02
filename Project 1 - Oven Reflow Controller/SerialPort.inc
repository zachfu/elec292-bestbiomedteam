$NOLIST
;--------------------------------------------------------------------------------------------------
;Purpose: -initializing serial port 
;		  -sending data through serial port 			  
;Functions:										  
;			- InitSerialPort:	Configure the serial port and baud rate using timer 1			  
;			- putchar:			Send a character using the serial port						  
;			- SendString:		Send a constant-zero-terminated string using the serial port
;			
;			- Send_BCD mac		Send a BCD number through the serial port
;			- Send_Voltage_BCD_to_PuTTY						  
;--------------------------------------------------------------------------------------------------

CSEG
;----------------------------------------------------
; Configure the serial port and baud rate using timer 1
;----------------------------------------------------
InitSerialPort:
    ; Since the reset button bounces, we need to wait a bit before
    ; sending messages, or risk displaying gibberish!
    mov R1, #222
    mov R0, #166
    djnz R0, $   ; 3 cycles->3*45.21123ns*166=22.51519us
    djnz R1, $-4 ; 22.51519us*222=4.998ms
    ; Now we can safely proceed with the configuration
	clr	TR1
	anl	TMOD, #0x0f
	orl	TMOD, #0x20
	orl	PCON,#0x80
	mov	TH1,#T1LOAD
	mov	TL1,#T1LOAD
	setb TR1
	mov	SCON,#0x52
    ret

	
;----------------------------------------------------
; Send a character using the serial port
;----------------------------------------------------
putchar:
    jnb TI, putchar
    clr TI
    mov SBUF, a
    ret

	
	
;----------------------------------------------------
; Send a constant-zero-terminated string using the serial port
;----------------------------------------------------
SendString:
    clr A
    movc A, @A+DPTR
    jz SendStringDone
    lcall putchar
    inc DPTR
    sjmp SendString
SendStringDone:
    ret
 
	
;---------------------------------;
; Send a BCD number to PuTTY      ;
;---------------------------------;
Send_BCD mac
    push ar0
    mov r0, %0
    lcall ?Send_BCD
    pop ar0
endmac
?Send_BCD:
    push acc
    ; Write most significant digit
    mov a, r0
    swap a				; to move the upper half, to lower half
    anl a, #0fh			; to remove the upper half
    orl a, #30h			; to add 48 (ascii code for 0)
    lcall putchar
    ; write least significant digit
    mov a, r0
    anl a, #0fh
    orl a, #30h
    lcall putchar
    pop acc
ret
	
;---------------------------------
; Send 4-digit BCD number to PuTTY (Volts)
;---------------------------------
; Sends 4-digit Voltage in BCD number in bcd to PuTTY
Send_Voltage_BCD_to_PuTTY:

	;Send_BCD(bcd+4)
	;Send_BCD(bcd+3)
	;Send_BCD(bcd+2)
	Send_BCD(bcd+1)
	Send_BCD(bcd+0)
	; Replace all the zeros to the left with blanks
;	Left_blank(bcd+4, skip_blank)
;	Left_blank(bcd+3, skip_blank)
;	Left_blank(bcd+2, skip_blank)
;	Left_blank(bcd+1, skip_blank)
;	mov a, bcd+0
;	anl a, #0f0h
;	swap a
;	jnz skip_blank
;	Display_char(#' ')
;skip_blank:

ret

$LIST