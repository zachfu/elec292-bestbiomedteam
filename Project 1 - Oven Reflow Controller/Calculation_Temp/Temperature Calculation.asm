$MODLP52
org 0000H
   ljmp Init

CLK  EQU 22118400
BAUD equ 115200
T1LOAD equ (0x100-(CLK/(16*BAUD)))
TIMER0_RATE	  EQU 1000
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))

CE_ADC EQU P2.0
MY_MOSI EQU P2.1
MY_MISO EQU P2.2
MY_SCLK EQU P2.3
BOOT_BUTTON EQU P4.5
LCD_RS equ P1.2
LCD_RW equ P1.3
LCD_E  equ P1.4
LCD_D4 equ P3.2
LCD_D5 equ P3.3
LCD_D6 equ P3.4
LCD_D7 equ P3.5
SOUND_OUT equ P2.7
GREEN  equ P2.6
YELLOW equ P2.5
RED    equ P2.4

	
$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$include(math32.inc) ; A library of 32 bit functions and macros
$LIST



dseg at 0x30
Timer0_Count1ms:	 ds 2 ;
Result: 	ds 2
x:  	    ds 4
y:   		ds 4
bcd:		ds 5

BSEG
mf: dbit 1

CSEG
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
    swap a
    anl a, #0fh
    orl a, #30h
    lcall putchar
    ; write least significant digit
    mov a, r0
    anl a, #0fh
    orl a, #30h
    lcall putchar
    pop acc
    ret
    
INIT_SPI:
 	setb MY_MISO ; Make MISO an input pin
 	clr MY_SCLK ; For mode (0,0) SCLK is zero
 	setb CE_ADC
 	ret
DO_SPI_G:
 	push acc
 	mov R1, #0 ; Received byte stored in R1
 	mov R2, #8 ; Loop counter (8-bits)
DO_SPI_G_LOOP:
 	mov a, R0 ; Byte to write is in R0
 	rlc a ; Carry flag has bit to write
 	mov R0, a
 	mov MY_MOSI, c
 	setb MY_SCLK ; Transmit
 	mov c, MY_MISO ; Read received bit
 	mov a, R1 ; Save received bit in R1
 	rlc a
 	mov R1, a
 	clr MY_SCLK
 	djnz R2, DO_SPI_G_LOOP
 	pop acc
 	ret
 
; Configure the serial port and baud rate using timer 1
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

; Send a character using the serial port
putchar:
    jnb TI, putchar
    clr TI
    mov SBUF, a
    ret

; Send a constant-zero-terminated string using the serial port
SendString:
    clr A
    movc A, @A+DPTR
    jz SendStringDone
    lcall putchar
    inc DPTR
    sjmp SendString
SendStringDone:
    ret

Init:
    mov SP, #7FH
    mov PMOD, #0 
    setb EA				; Enable interrupts
	lcall INIT_SPI
	lcall InitSerialPort
	lcall LCD_4BIT
Main_Loop:

    clr CE_ADC
    
	mov R0, #00000001B ; Start bit:1
	lcall DO_SPI_G
	
	mov R0, #10010000B ; Single ended, read channel 1
	lcall DO_SPI_G
	
	mov a, R1 ; R1 contains bits 8 and 9
	anl a, #00000011B ; We need only the two least significant bits
	mov Result+1, a ; Save result high.
	
	mov R0, #55H ; It doesn't matter what we transmit...
	lcall DO_SPI_G	
	
	mov Result, R1 ; R1 contains bits 0 to 7. Save result low.
	
	setb CE_ADC
	
	lcall Result_SPI_Routine	; Calls routine that calculates temperatures, displays on LCD, and sends via serial
	Wait_Milli_Seconds(#100)	; 0.1 second delay between samples 
Result_SPI_Routine:
	mov x+3, #0
	mov x+2, #0
	mov x+1, result+1
	mov x+0, result+0
	; Calculate temperature in Kelvin in binary with 4 digits of precision
	Load_Y(5000000)	;reduce the digit displaying on LCD
	lcall mul32
	Load_Y(1023)
	lcall div32
	Load_Y(454057169)	;gain*1000000
	lcall div32
	Load_Y(41)
	lcall div32
	Load_Y(1000000)
	lcall mul32
	Load_Y(100)
	lcall mul32
	lcall hex2bcd
	;result of the calculation is 100*temperature difference
	Send_BCD(bcd+2)
	Send_BCD(bcd+1)
	Display_char(#'.')
    Send_BCD(bcd)
    
    sjmp Display_Temp_LCD

Display_Temp_LCD:	
	Display_BCD(bcd+2)
	Display_BCD(bcd+1)
	Display_BCD(bcd)
    ret
end
