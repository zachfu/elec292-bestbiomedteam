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
;++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
;Purpose: -32bit math functions
;NEW Functions:
;			- Move_4B_to_4B (Destination - Origin)
;			- Move_2B_to_4B (Destination - Origin)
;			- Zero_4B (4B Data): make the 4B value 0
;--------------------------------------------------------------------------------------------------
$include(math32.inc) ; A library of 32 bit functions and macros
;++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
;Purpose: -initializing & communicating with the MCP3008
;Functions:
;			- INIT_SPI 					  
;			- DO_SPI_G:					Send a character using the serial port						  
;			- Read_ADC_Channel MAC:		Returns 2 bytes in result
;--------------------------------------------------------------------------------------------------
$include(MCP3008.inc)	
;++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
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
$include(SerialPort.inc)	

$LIST



dseg at 0x30
Vcc:				ds 4
Timer0_Count1ms:	ds 2 
Result: 	ds 2
x:  	    ds 4
y:   		ds 4
<<<<<<< HEAD
samplesum:  ds 4
=======
samplesum:	ds 4
>>>>>>> eb006521b020f6cd5199b14eb916759c9f513c0a
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
	clr a
	Zero_4B (samplesum)
	
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
	Move_2B_to_4B (y, result)
	load_X(VLED*1023)
	lcall div32
	load_Y(10000)
	lcall mul32			; Gets Vcc*10^6

	Move_4B_to_4B (Vcc, x)
	
	ret
	
LM335_Result_SPI_Routine:
	Move_2B_to_4B (x, result)
	Move_4B_to_4B (y, Vcc)

    lcall mul32			; Vout*10^6 = ADC*(Vcc*10^6)/1023
    load_y (1023)	
    lcall div32
    load_y (2730000)	; T*10^4 = (Vout*10^6-2.73*10^6)/100
    lcall sub32
    load_y (100)		
    lcall div32

	Move_4B_to_4B (x_lm335, x)
	
	ret

Result_SPI_Routine:
	Move_2B_to_4B (x, result)
	Move_4B_to_4B (y, Vcc)
	
	lcall mul32
	Load_Y(1023)
	lcall div32
	Load_Y(100)
	lcall mul32	
	Load_Y(454)	;Gain 
	lcall div32
	Load_Y(41)	;Since calculations have been scaled up by 10^6, this is equivalent to dividing by 41*10^-6
	lcall div32
	

	Move_4B_to_4B (y, x_lm335)
	lcall add32
	
	Move_4B_to_4B (y, samplesum)
	lcall add32
	
	Move_4B_to_4B (samplesum, x)
	ret

Calculate_Average:
	Move_4B_to_4B (x, samplesum)
	
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