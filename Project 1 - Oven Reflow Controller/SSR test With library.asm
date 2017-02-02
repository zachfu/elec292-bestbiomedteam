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

;-------------------------------------------------
;Purpose: -initializing & communicating with the MCP3008
;Functions:
;			- INIT_SPI 					  
;			- DO_SPI_G:					Send a character using the serial port						  
;			- Read_ADC_Channel MAC:		Returns 2 bytes in result
;-------------------------------------------------
$include(MCP3008.inc)	
	
;-------------------------------------------------
;Purpose: -initializing serial port 
;		  -sending data through serial port 			  
;Functions:										  
;			- InitSerialPort:	Configure the serial port and baud rate using timer 1			  
;			- putchar:			Send a character using the serial port						  
;			- SendString:		Send a constant-zero-terminated string using the serial port
;			
;			- Send_BCD mac		Send a BCD number through the serial port
;			- Send_Voltage_BCD_to_PuTTY						  
;-------------------------------------------------
$include(SerialPort.inc)	

$LIST



dseg at 0x30
Vcc:				ds 4
Timer0_Count1ms:	ds 2 
Result: 	ds 2
x:  	    ds 4
y:   		ds 4
bcd:		ds 5
x_lm335:	ds 4

BSEG
mf: dbit 1

CSEG
NEWLINE: db '\n'
   
 
Init:
    mov SP, #7FH
    mov PMOD, #0 
    setb EA				; Enable interrupts
	lcall INIT_SPI
	lcall InitSerialPort
	lcall LCD_4BIT
Main_Loop:
	Read_ADC_Channel(7)
	lcall Calculate_Vref
	;fetch result from channel 0 as room temperature
	Read_ADC_Channel(0)
	lcall LM335_Result_SPI_Routine
	;fetch result from channel 1
    Read_ADC_Channel(1)
    lcall Result_SPI_Routine
	Wait_Milli_Seconds(#250)	; 0.1 second delay between samples 
	Wait_Milli_Seconds(#250)
	setb P3.7
	sjmp Main_Loop	
	
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
	
LM335_Result_SPI_Routine:
	mov x+3, #0
    mov x+2, #0
    mov x+1, Result+1
    mov x+0, Result
    mov y+3, Vcc+3
    mov y+2, Vcc+2
    mov y+1, Vcc+1
    mov y+0, Vcc+0
    lcall mul32
    load_y (1023)
    lcall div32
    load_y (2730000)
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
	; Calculate temperature in Kelvin in binary with 4 digits of precision
    mov y+3, Vcc+3
    mov y+2, Vcc+2
    mov y+1, Vcc+1
    mov y+0, Vcc+0
	lcall mul32
	Load_Y(1023)
	lcall div32
	Load_Y(100)
	lcall mul32	
	Load_Y(454)	;gain*1000
	lcall div32
	Load_Y(41)
	lcall div32
	
	mov y+3, x_lm335+3
	mov y+2, x_lm335+2
	mov y+1, x_lm335+1
	mov y+0, x_lm335+0
	lcall add32
	lcall hex2bcd
	
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
