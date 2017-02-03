$MODLP52
org 0000H
   ljmp Init

VLED EQU 207
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
Vcc:				ds 4
Timer0_Count1ms:	ds 2 
Result: 	ds 2
x:  	    ds 4
y:   		ds 4
samplesum:	ds 4
bcd:		ds 5
x_lm335:	ds 4

BSEG
mf: dbit 1

CSEG
NEWLINE: db '\n'

Read_ADC_Channel MAC
	mov b, #%0
	lcall _Read_ADC_Channel
	ENDMAC
_Read_ADC_Channel:
	clr CE_ADC
	mov R0, #00000001B ; Start bit:1
	lcall DO_SPI_G
	mov a, b
	swap a
	anl a, #0F0H
	setb acc.7 ; Single mode (bit 7).
	mov R0, a
	lcall DO_SPI_G
	mov a, R1 ; R1 contains bits 8 and 9
	anl a, #00000011B ; We need only the two least significant bits
	mov result+1, a ; Save result high.
	mov R0, #55H ; It doesn't matter what we transmit...
	lcall DO_SPI_G
	mov result+0, R1 ; R1 contains bits 0 to 7. Save result low.
	setb CE_ADC
	
	ret
	

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
	clr a
	mov samplesum+3, a
	mov samplesum+2, a
	mov samplesum+1, a
	mov samplesum+0, a
	
	lcall Take_Sample
	lcall Take_Sample
	lcall Take_Sample
	lcall Take_Sample
	lcall Calculate_Average
	 
	setb P3.7
	sjmp Main_Loop	
	
	
Take_Sample:
	Read_ADC_Channel(7)
	lcall Calculate_Vref
	;fetch result from channel 0 as room temperature
	Read_ADC_Channel(0)
	lcall LM335_Result_SPI_Routine
	;fetch result from channel 1
    Read_ADC_Channel(1)
    lcall Result_SPI_Routine
	Wait_Milli_Seconds(#125)	; 0.1 second delay between samples
	ret
Calculate_Vref:
	mov y+3, #0
	mov y+2, #0
	mov y+1, result+1
	mov y+0, result+0
	load_X(VLED*1023)
	lcall div32
	load_Y(10000)
	lcall mul32			; Gets Vcc*10^6
	mov Vcc+3, x+3
	mov Vcc+2, x+2
	mov Vcc+1, x+1
	mov Vcc+0, x+0
	
	ret
	
LM335_Result_SPI_Routine:
	mov x+3, #0
    mov x+2, #0
    mov x+1, result+1
    mov x+0, result+0
    mov y+3, Vcc+3
    mov y+2, Vcc+2
    mov y+1, Vcc+1
    mov y+0, Vcc+0
    lcall mul32			; Vout*10^6 = ADC*(Vcc*10^6)/1023
    load_y (1023)	
    lcall div32
    load_y (2730000)	; T*10^4 = (Vout*10^6-2.73*10^6)/100
    lcall sub32
    load_y (100)		
    lcall div32
    mov x_lm335+3, x+3
	mov x_lm335+2, x+2
	mov x_lm335+1, x+1
	mov x_lm335+0, x+0
	ret

Result_SPI_Routine:
	mov x+3, #0
	mov x+2, #0
	mov x+1, result+1
	mov x+0, result+0
    mov y+3, Vcc+3
    mov y+2, Vcc+2
    mov y+1, Vcc+1
    mov y+0, Vcc+0
	lcall mul32
	Load_Y(1023)
	lcall div32
	Load_Y(100)
	lcall mul32	
	Load_Y(454)	;Gain 
	lcall div32
	Load_Y(41)	;Since calculations have been scaled up by 10^6, this is equivalent to dividing by 41*10^-6
	lcall div32
	
	mov y+3, x_lm335+3
	mov y+2, x_lm335+2
	mov y+1, x_lm335+1
	mov y+0, x_lm335+0
	lcall add32
	
	mov y+3, samplesum+3
	mov y+2, samplesum+2
	mov y+1, samplesum+1
	mov y+0, samplesum+0
	
	lcall add32
	
	mov samplesum+3, x+3
	mov samplesum+2, x+2
	mov samplesum+1, x+1
	mov samplesum+0, x+0
	
	ret

Calculate_Average:
	mov x+3, samplesum+3
	mov x+2, samplesum+2
	mov x+1, samplesum+1
	mov x+0, samplesum+1
	
	Load_Y(4)
	lcall div32
	lcall hex2bcd
	
	Send_BCD(bcd+2)
	Send_BCD(bcd+1)
	mov a, #'\n'
	lcall putchar
	
	Set_Cursor(1,1)
	
	

Display_Temp_LCD:
	Display_BCD(bcd+4)
	Display_BCD(bcd+3)
	Display_BCD(bcd+2)
	Display_BCD(bcd+1)
	Display_BCD(bcd)
    ret
end
