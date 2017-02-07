$NOLIST
$MODLP52
$LIST
; Reset vector
org 0000H
   ljmp MainProgram


; External interrupt 0 vector (not used in this code)
org 0x0003
	reti

; Timer/Counter 0 overflow interrupt vector
org 0x000B
	reti
;	ljmp Timer0_ISR
	
; External interrupt 1 vector (not used in this code)
org 0x0013
	reti

; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 0x001B
	reti

; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
	reti
	
; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR
	
	
;++++++++++++++++++ TIMER & BAUDRATE  ++++++++++++
CLK           EQU 22118400							 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 4096     							 ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE   EQU 1000     							 ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))
BAUD 		  equ 115200
T1LOAD 		  equ (0x100-(CLK/(16*BAUD)))

PWM_RELOAD_HIGH EQU 20
PWM_RELOAD_LOW EQU	(100 - PWM_RELOAD_HIGH)
;------------------------------------------------

;++++++++++++++++++ SPI PINS ++++++++++++++++
CE_ADC EQU P2.0
MY_MOSI EQU P2.1
MY_MISO EQU P2.2
MY_SCLK EQU P2.3
;--------------------------------------------

;++++++++++++++++++ LCD PINS ++++++++++++++++
LCD_RS equ P1.2
LCD_RW equ P1.3
LCD_E  equ P1.4
LCD_D4 equ P3.2
LCD_D5 equ P3.3
LCD_D6 equ P3.4
LCD_D7 equ P3.5
;--------------------------------------------


SSR_OUT    	    equ P3.7	; Pin connected to SSR
BOOT_BUTTON     equ P4.5
PWM_BUTTON      equ P0.3

;++++++++++++++++++ CONTROL BUTTONS++++++++++
SOUND_OUT     	    equ P3.6	; Pin connected to speaker
HOURS_BUTTON   	    equ P4.5	; Button to change hours value in set modes
CYCLE_BUTTON        equ P0.0 	; Button to change cycles
INC_BUTTON			equ P0.2
DEC_BUTTON          equ P0.4
POWER_BUTTON		equ P0.5
;--------------------------------------------

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$include(math32.inc) ; A library of 32 bit functions and macros					Move_4B_to_4B (dest, origin) ----- Move_2B_to_4B ----- Move_1B_to_4B ----- Zero_4B (orig)----- Zero_2B
$include(MCP3008.inc)	;-initializing & communicating with the MCP3008			INIT_SPI ----- DO_SPI_G -----	Read_ADC_Channel (MAC): returns in "result" ----- Average_ADC_Channel (MAC)	: returns in "x"					  
$include(SerialPort.inc)	;initializing & sending data through serial port	InitSerialPort ---- putchar ----- SendString ----- Send_BCD (MAC) ----- Send_Voltage_BCD_to_PuTTY	
$include (Timer.inc) ;-initializing Timers										Timer0_Init	(OFF BY DEFAULT) ----- Timer2_Init (ON BY DEFAULT)
$LIST

	
; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
dseg at 0x30

	Count1ms:	 		ds 2 ; Incremented every 1ms when Timer 2 ISR is triggered
	Count_PWM:			ds 1
	soak_seconds: 		ds 1
	soak_temp: 			ds 1
	reflow_seconds: 	ds 1
	reflow_temp: 		ds 1
	run_time_sec: 		ds 1
	Timer0_Count1ms:	ds 2 ;	DO WE NEED IT ?????????? NOT USED SO FAR		TODOOOOO
	
;+++++++++ 32 bit Calculation variables +++++++++++	
	x:  	    		ds 4
	y:   				ds 4
	Result: 			ds 2
	bcd:				ds 5
	x_lm335:			ds 4
	Vcc:				ds 4
	samplesum:			ds 4
;--------------------------------------------
	state:				ds 1
;	pwm:				ds 1		TODOOOOO			needed?
	current_temp:		ds 4

	
	
CSEG
	NEWLINE: db '\n'

BSEG
	mf: dbit 1
	one_min_flag: dbit 1
	pwm_on: dbit 1
	pwm_high: dbit 1



CSEG
;           					1234567890123456    <- This helps determine the location of the Strings
	SoakTime_Message:  		db 'Soak Time       ',0
	SoakTemp_Message: 		db 'Soak Temperature',0
	ReflowTime_Message: 	db 'Reflow Time     ',0
	ReflowTemp_Message: 	db 'Reflow Temp     ',0
	Start_Message: 			db 'Start?          ',0
	Mask_Message: 			db '                ',0
	PWM_ON_MESSAGE: 		db 'PWM IS ON       ', 0
	PWM_OFF_MESSAGE:		db 'PWM IS OFF      ', 0

	
	
;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in ISR
	
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Increment the 16-bit one mili second counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done_1sec
	inc Count1ms+1
	
Inc_Done_1sec:
	; Check if one second has passed
	mov a, Count1ms+0
	cjne a, #low(1000), Inc_PWM ; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(1000), Inc_PWM
	
	; 1 second has passed.  Set a flag so the main program knows
	Zero_2B (Count1ms)
		
	; total time passed for each stage (it will be set to 0 when the stage starts)
	inc run_time_sec

	
Inc_PWM:
	
	jnb pwm_on, Timer2_ISR_done
	inc Count_PWM
	jnb pwm_high, Inc_Done_PWM_Low

	mov a, Count_PWM
	cjne a, #PWM_RELOAD_HIGH, Timer2_ISR_done
	
	clr pwm_high
	clr SSR_OUT
	
	clr a
	mov Count_PWM, a
	
	sjmp Timer2_ISR_done
	
Inc_Done_PWM_Low:

	mov a, Count_PWM
	cjne a, #PWM_RELOAD_LOW, Timer2_ISR_done
	
	setb pwm_high
	setb SSR_OUT
	
	clr a
	mov Count_PWM, a
	
Timer2_ISR_done:
	pop psw
	pop acc
reti

;------------------------------------------------------------------;
; Subroutine to take sample from Thermocouple, LM335, and LED for Vref
;------------------------------------------------------------------;
Take_Sample:
	;reading the LED voltage for Vref
	Average_ADC_Channel(7)	
	lcall Calculate_Vref
	;fetch result from channel 0 as room temperature
	Average_ADC_Channel(0)
	lcall LM335_Result_SPI_Routine
	;fetch result from channel 1
    Average_ADC_Channel(1)
    lcall Result_SPI_Routine	; 0.5 second delay between samples
	ret

;calculating Vref from Vled	
Calculate_Vref:
	Move_2B_to_4B (y, result)
	load_X(VLED*1023)
	lcall div32
	load_Y(10000)
	lcall mul32			; Gets Vcc*10^6

	Move_4B_to_4B (Vcc, x)
	
	ret
	
;calculating cold junction temperature
LM335_Result_SPI_Routine:
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

;calculating the oven temperature and sending it to computer and LCD
Result_SPI_Routine:
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

	;updating the temperature of OVEN variable
	Move_4B_to_4B (current_temp, x)
	
	lcall hex2bcd

;sending Oven temperature to Computer
Send_Serial:
	
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



;------------------------------------------------------------------;
; MACRO for incrementing or decrementing a variable
;------------------------------------------------------------------;
Inc_dec_variable MAC
	;Mac (%0 : inc/dec button    %1 : variable ) 
	jb %0, no_inc_dec_var%M
	Wait_Milli_Seconds(#50)
	jb %0, no_inc_dec_var%M
	inc %1
	
no_inc_dec_var%M:

ENDMAC

;------------------------------------------------------------------;
; MACRO for Showing values with header on LCD
;------------------------------------------------------------------;
Show_Header_and_Value Mac
	; MAC (%0:    Constant string for the first line on LCD           %1: value to be shown on second line )
	Set_Cursor(1,1)
	Send_Constant_String(#%0)
	Set_Cursor(2,1)
	
	Move_1B_to_4B ( x, %1)
	lcall hex2bcd
  	Display_BCD(bcd+1)
	Display_BCD(bcd)
ENDMAC

;------------------------------------------------------------------;
; Main program   (FSM)
;	
;	-state 0:  setting the Soak Time
;	-state 1:  setting the Soak Temperature
;	-state 2:  setting the Reflow Time
;	-state 3:  setting the Reflow Temp
;	-state 4:  setting the 
;------------------------------------------------------------------;
MainProgram:

	; Initialization
    mov SP, #0x7F
    mov PMOD, #0 ; Configure all ports in bidirectional mode
    lcall Timer0_Init
    lcall Timer2_Init
    setb EA   ; Enable Global interrupts
    lcall INIT_SPI
	lcall InitSerialPort
    lcall LCD_4BIT  ; For convenience a few handy macros are included in 'LCD_4bit.inc':
    
	clr pwm_on
    clr pwm_high
    clr SSR_OUT
	
	mov a, #0
    mov soak_seconds, a
    mov soak_temp, a
    mov reflow_seconds, a
    mov reflow_temp, a
	
forever:

	; updating the temperature of Oven variable
	lcall Take_Sample
	Wait_Milli_Seconds(#250)		; maybe has to be put at the end TODOOOOO   or just removed
	
	mov a, state
	
; initializing the Soak Time 
state0:
	cjne a, #0, state1
	clr pwm_on
	
	
	;jb KEY.3, state0_done													;TODOOOOO
	;jnb KEY.3, $ ; Wait for key release									;TODOOOOO
	mov state, #1
state0_done:
	ljmp forever									;TODOOOOO
	
state1:


	ljmp forever

; Cycle between stages: Start->SoakTime->SoakTemp->ReflowTime->ReflowTemp	
SoakTime:	
	Show_Header_and_Value (SoakTime_Message, soak_seconds)
	Inc_dec_variable (INC_BUTTON, soak_seconds)
	Inc_dec_variable (DEC_BUTTON, soak_seconds)
	
	
	jb CYCLE_BUTTON, CB_not_pressed
	Wait_Milli_Seconds(#50)
	jb CYCLE_BUTTON, CB_not_pressed
	jnb CYCLE_BUTTON, $
	ljmp SoakTemp
CB_not_pressed:
  ljmp SoakTime

	
SoakTemp:
	Show_Header_and_Value (SoakTemp_Message, soak_temp)
	Inc_dec_variable (INC_BUTTON, soak_temp)
	Inc_dec_variable (DEC_BUTTON, soak_temp)
	
	
  	jb CYCLE_BUTTON, CB_not_pressed1
	Wait_Milli_Seconds(#50)
	jb CYCLE_BUTTON, CB_not_pressed1
	jnb CYCLE_BUTTON, $
	ljmp ReflowTime
CB_not_pressed1:
  	ljmp SoakTemp
	
ReflowTime:
	Show_Header_and_Value (ReflowTime_Message, reflow_seconds)	
	Inc_dec_variable (INC_BUTTON, reflow_seconds)
	Inc_dec_variable (DEC_BUTTON, reflow_seconds)
	
	
	jb CYCLE_BUTTON, CB_not_pressed2
	Wait_Milli_Seconds(#50)
	jb CYCLE_BUTTON, CB_not_pressed2
	jnb CYCLE_BUTTON, $
	ljmp ReflowTemp
CB_not_pressed2:
	ljmp ReflowTime


ReflowTemp:
	Show_Header_and_Value (ReflowTemp_Message, reflow_temp)		
	Inc_dec_variable (INC_BUTTON, reflow_temp)
	Inc_dec_variable (DEC_BUTTON, reflow_temp)
	
	jb CYCLE_BUTTON, CB_not_pressed3
	Wait_Milli_Seconds(#50)
	jb CYCLE_BUTTON, CB_not_pressed3
	jnb CYCLE_BUTTON, $
	ljmp Start
CB_not_pressed3:
	ljmp ReflowTemp

	
Start:
	Set_Cursor(1,1)
  Send_Constant_String(#Start_Message)
  Set_Cursor(2,1)
  Send_Constant_String(#Mask_Message)
	
	jb CYCLE_BUTTON, CB_not_pressed4 
	Wait_Milli_Seconds(#50)
	jb CYCLE_BUTTON, CB_not_pressed4
	jnb CYCLE_BUTTON, $
	ljmp SoakTime   
CB_not_pressed4:    
	jb POWER_BUTTON, PB_not_pressed
	Wait_Milli_Seconds(#50)
	jnb POWER_BUTTON, PB_not_pressed
	jnb POWER_BUTTON, $
	ljmp Reflow_Procedure
PB_not_pressed:
	ljmp Start

Reflow_Procedure:
 sjmp $

end

