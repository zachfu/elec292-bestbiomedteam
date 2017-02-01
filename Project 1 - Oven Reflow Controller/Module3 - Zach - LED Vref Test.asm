; Author: Zachary Fu
; Student#: 10869155
;
; Module3 - Zach.asm: Thermometer - Reads data from temperature sensor through ADC,
; displays it on LCD, and sends temperature to connected serial communication program
; Can display temperature in Celsius, Kelvin, and Fahrenheit, and has light and sound
; indicators for different temperature ranges

$MODLP52
org 0000H
   ljmp Init

CLK  EQU 22118400
VLED EQU 207
BAUD equ 115200
T1LOAD equ (0x100-(CLK/(16*BAUD)))
TIMER0_RATE	  EQU 1000
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))

; These ’EQU’ must match the wiring between the microcontroller and ADC
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

org 0x0B
	ljmp Timer0_ISR
	
$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$include(math32.inc) ; A library of 32 bit functions and macros
$LIST



dseg at 0x30
Timer0_Count1ms:	 ds 2 ;
Vcc:		ds 4
Result: 	ds 2
x:  	    ds 4
y:   		ds 4
dC:			ds 4
dF:			ds 4
dK:			ds 4
bcd:		ds 5
bcdC: 		ds 5
bcdK:		ds 5
spistring: 	ds 10

BSEG
mf: dbit 1
CelsiusFlag: dbit 1
FahrenFlag: dbit 1
KelvinFlag: dbit 1

CSEG
Cels: db ' ',11011111b, 'C',0
Fahr: db ' ',11011111b, 'F',0
Kelv: db ' ',11011111b, 'K',0
	
bcd2ascii MAC
	mov a, bcd+%0
	mov R1, a
	anl a, #0x0F
	add a, #0x30
	mov spistring+%1, a
	mov a, R1
	anl a, #0xF0
	swap a
	add a, #0x30
	mov spistring+%2, a
ENDMAC

sendserialstring MAC
	mov a, spistring+6
	lcall putchar
	mov a, spistring+5
	lcall putchar
	mov a, spistring+4
	lcall putchar
	mov a, spistring+3
	lcall putchar
	mov a, spistring+2
	lcall putchar
	mov a, spistring+1
	lcall putchar
	mov a, spistring+0
	lcall putchar
	mov a, #'\n'
	lcall putchar
ENDMAC

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
	
Timer0_Init:
	mov a, TMOD
	anl a, #0xf0 ; Clear the bits for timer 0
	orl a, #0x01 ; Configure timer 0 as 16-timer
	mov TMOD, a
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	; Enable the timer and interrupts
    setb ET0  ; Enable timer 0 interrupt
    clr TR0  ; Disable timer 0 by default
	ret
	
Timer0_ISR:
	; Generates tone when TR0 = 1
	clr TR0
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	setb TR0
	cpl SOUND_OUT 

	reti
	
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
    lcall Timer0_Init
    setb CelsiusFlag	; Display in Celsius by default (only one of the three flags here is 1 at a time)
    clr FahrenFlag
    clr KelvinFlag
    setb RED			; LEDs operate in negative logic, all off initially, but later only one is 1 at a time
    setb YELLOW
    setb GREEN
	lcall INIT_SPI
	lcall InitSerialPort
	lcall LCD_4BIT
Main_Loop:
	Read_ADC_Channel(7)
	lcall Calculate_Vref
	
    Read_ADC_Channel(0)
	
	lcall Result_SPI_Routine	; Calls routine that calculates temperatures, displays on LCD, and sends via serial
	Wait_Milli_Seconds(#100)	; 0.1 second delay between samples
	
	mov a, bcdC+2				; Look at 'tens' and 'ones' place digits of temperature in Celsius
	cjne a, #0x40, Compared_40C
Compared_40C:
	; If temperature less than 40C, turn on green light
	jc Green_Light
	cjne a, #0x60, Compared_60C
Compared_60C:
	; If between 40C and 60C, turn on yellow light
	jc Yellow_Light
	cjne a, #0x80, Compared_80C
Compared_80C:
	; If between 60C and 80C, turn on yellow light
	jc Red_Light
	; Otherwise, above 80C, flash red light and sound alarm
	setb GREEN
	setb YELLOW
	cpl RED
	cpl TR0			
	sjmp Button_Poll
Green_Light:
	clr GREEN
	setb YELLOW
	setb RED
	clr TR0
	sjmp Button_Poll
Yellow_Light:
	setb GREEN
	clr YELLOW
	setb RED
	clr TR0
	sjmp Button_Poll
Red_Light:
	setb GREEN
	setb YELLOW
	clr RED
	clr TR0
	
Button_Poll:
	; Poll button
	jb BOOT_BUTTON, Main_Loop
	Wait_Milli_Seconds(#50)
	jb BOOT_BUTTON, Main_Loop
	Wait_Milli_Seconds(#50)
	; Cycle between temperature scales: Celsius->Fahrenheit->Kelvin->Celsius
	jb FahrenFlag, Kelvin
	jb CelsiusFlag, Fahrenheit
	clr KelvinFlag
	setb CelsiusFlag
	ljmp Main_Loop
Kelvin:
	clr FahrenFlag
	setb KelvinFlag
	ljmp Main_Loop
Fahrenheit:
	clr CelsiusFlag
	setb FahrenFlag
	ljmp Main_Loop

Calculate_Vref:
	mov y+3, #0
	mov y+2, #0
	mov y+1, result+1
	mov y+0, result+0
	load_X(VLED*1023)
	lcall div32
	load_Y(10000)
	lcall mul32
	mov Vcc+3, x+3
	mov Vcc+2, x+2
	mov Vcc+1, x+1
	mov Vcc+0, x+0
	
	ret

Result_SPI_Routine:
	; Load 10-bit result into 32-bit x variable
	mov x+3, #0
	mov x+2, #0
	mov x+1, result+1
	mov x+0, result+0
	; Calculate temperature in Kelvin in binary with 4 digits of precision
	;mov y+3, Vcc+3
	;mov y+2, Vcc+2
	;mov y+1, Vcc+1
	;mov y+0, Vcc+0
	Load_Y(5000000)
	lcall mul32
	Load_Y(1023)
	lcall div32
	; Convert binary Kelvin to BCD, and store in variable
	lcall hex2bcd
	mov bcdK+3, bcd+3
	mov bcdK+2, bcd+2
	mov bcdK+1, bcd+1
	mov bcdK+0, bcd+0
	; Calculate temperature in Celsius
	Load_Y(2730000)
	lcall sub32
	; Convert binary Celsius to BCD, and store in variable
	lcall hex2bcd
	mov bcdC+3, bcd+3
	mov bcdC+2, bcd+2
	mov bcdC+1, bcd+1
	mov bcdC+0, bcd+0	
	; Convert BCD Celsius to ASCII, and send using serial
	bcd2ascii(0,0,1)
	bcd2ascii(1,2,3)
	bcd2ascii(2,4,5)
	bcd2ascii(3,6,7)
	bcd2ascii(4,8,9)	
	; Calls macro to send spistring via serial
	sendserialstring()
	; Calculate temperature in Fahrenheit
	Load_Y(9)
	lcall mul32
	Load_Y(5)
	lcall div32
	Load_Y(320000)
	lcall add32
	; Convert binary Fahrenheit to BCD
	lcall hex2bcd
	Set_Cursor(1,10)
	; Display in the selected temperature scale
	jb FahrenFlag, Display_F
	jb CelsiusFlag, Display_C
	mov bcd+3, bcdK+3
	mov bcd+2, bcdK+2
	mov bcd+1, bcdK+1
	mov bcd+0, bcdK+0
	Send_Constant_String(#Kelv)
	sjmp Display_Temp_LCD
Display_F:
	Send_Constant_String(#Fahr)
	sjmp Display_Temp_LCD
Display_C:
	mov bcd+3, bcdC+3
	mov bcd+2, bcdC+2
	mov bcd+1, bcdC+1
	mov bcd+0, bcdC+0
	Send_Constant_String(#Cels)

Display_Temp_LCD:	
	mov a, bcd+3
	cjne a, #0, Display_Hundreds	; If temperature is not in the hundreds, don't display hundreds digit (don't show the 0)
	sjmp Display_Clear_Hundreds
Display_Hundreds:
	Set_Cursor(1,1)
	Display_BCD(bcd+3)
	Set_Cursor(1,1)
	Display_char(#' ')
	sjmp Display_Tens
Display_Clear_Hundreds:
	Set_Cursor(1,1)
	Display_char(#' ')
	Display_char(#' ')
Display_Tens:
	Set_Cursor(1,3)
	Display_BCD(bcd+2)
	Display_char(#'.')
	Display_BCD(bcd+1)
	Display_BCD(bcd+0)
	
	ret


end