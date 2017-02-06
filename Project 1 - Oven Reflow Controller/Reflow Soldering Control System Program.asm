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
BAUD equ 115200
T1LOAD equ (0x100-(CLK/(16*BAUD)))
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

;++++++++++++++++++ CONTROL BUTTONS++++++++++
SOUND_OUT     	    equ P3.7	; Pin connected to speaker
HOURS_BUTTON   	    equ P4.5	; Button to change hours value in set modes
CYCLE_BUTTON        equ P0.0 	; Button to change cycles
INC_BUTTON			equ P0.2
DEC_BUTTON          equ P0.4
POWER_BUTTON		equ P0.5
;--------------------------------------------

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$include(math32.inc) ; A library of 32 bit functions and macros					Move_4B_to_4B (dest, origin) ----- Move_2B_to_4B ----- Zero_4B (orig)----- Zero_2B
$include(MCP3008.inc)	;-initializing & communicating with the MCP3008			INIT_SPI ----- DO_SPI_G -----	Read_ADC_Channel (MAC): returns in "result"							  
$include(SerialPort.inc)	;initializing & sending data through serial port	InitSerialPort ---- putchar ----- SendString ----- Send_BCD (MAC) ----- Send_Voltage_BCD_to_PuTTY	
$include (Timer.inc) ;-initializing Timers										Timer0_Init	(OFF BY DEFAULT) ----- Timer2_Init (ON BY DEFAULT)
$LIST

	
; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
dseg at 0x30

	Count1ms:	 		ds 2 ; Incremented every 1ms when Timer 2 ISR is triggered
	soak_seconds: 		ds 1
	soak_temp: 			ds 1
	reflow_seconds: 	ds 1
	reflow_temp: 		ds 1
	sec: 				ds 2
	Timer0_Count1ms:	ds 2 ;	DO WE NEED IT ?????????? NOT USED SO FAR
	
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
	pwm:				ds 1
	
CSEG
	NEWLINE: db '\n'

BSEG
	mf: dbit 1
	one_min_flag: dbit 1


CSEG
;           					1234567890123456    <- This helps determine the location of the Strings
	SoakTime_Message:  		db 'Soak Time       ',0
	SoakTemp_Message: 		db 'Soak Temperature',0
	ReflowTime_Message: 	db 'Reflow Time     ',0
	ReflowTemp_Message: 	db 'Reflow Temp     ',0
	Start_Message: 			db 'Start?          ',0
	Mask_Message: 			db '                ',0

	
	
;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in ISR
	cpl P3.6 ; To check the interrupt rate with oscilloscope. It must be precisely a 1 ms pulse.
	
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Increment the 16-bit one mili second counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1
	
Inc_Done:
	; Check if one second has passed
	mov a, Count1ms+0
	cjne a, #low(1000), Timer2_ISR_done ; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(1000), Timer2_ISR_done
	
	; 1000 milliseconds have passed.  Set a flag so the main program knows
	;setb ome_seconds_flag ; Let the main program know one second had passed
	; Reset to zero the milli-seconds counter, it is a 16-bit variable
	Zero_2B (Count1ms)
		
	mov a, sec
	inc a
	da a
	mov sec, a
	cjne a,#60, Timer2_ISR_done
	setb one_min_flag
	
Timer2_ISR_done:
	pop psw
	pop acc
reti



MainProgram:

	; Initialization
    mov SP, #0x7F
    mov PMOD, #0 ; Configure all ports in bidirectional mode
    lcall Timer0_Init
    lcall Timer2_Init
    setb EA   ; Enable Global interrupts
    lcall LCD_4BIT  ; For convenience a few handy macros are included in 'LCD_4bit.inc':
    mov a, #0
    mov soak_seconds, a
    mov soak_temp, a
    mov reflow_seconds, a
    mov reflow_temp, a

	
forever:

	mov a, state
	
; initialization state
state0:
	cjne a, #0, state1
	mov pwm, #0
	;jb KEY.3, state0_done													;TODOOOOO
	;jnb KEY.3, $ ; Wait for key release									;TODOOOOO
	mov state, #1
state0_done:
	ljmp forever									;TODOOOOO
	
state1:


	ljmp forever

; Cycle between stages: Start->SoakTime->SoakTemp->ReflowTime->ReflowTemp	
SoakTime:	
	Set_Cursor(1,1)
	Send_Constant_String(#SoakTime_Message)
	Set_Cursor(2,1)
  	Display_BCD(soak_seconds+1)
	Display_BCD(soak_seconds)
  
	
	jb INC_BUTTON, no_inc_soak_sec
	Wait_Milli_Seconds(#50)
	jb INC_BUTTON, no_inc_soak_sec
	Wait_Milli_Seconds(#200)
	mov bcd+3, #0
	mov bcd+2, #0
  	mov bcd+1, soak_seconds+1
	mov bcd+0, soak_seconds+0
	lcall bcd2hex
  	load_y(1)
  	lcall add32
    lcall hex2bcd
  	mov soak_seconds+1, bcd+1
	mov soak_seconds+0, bcd+0
	
no_inc_soak_sec:
	jb DEC_BUTTON, no_dec_soak_sec
	Wait_Milli_Seconds(#50)
	jb DEC_BUTTON, no_dec_soak_sec
	Wait_Milli_Seconds(#200)
 	mov bcd+3, #0
	mov bcd+2, #0
  	mov bcd+1, soak_seconds+1
	mov bcd+0, soak_seconds+0
	lcall bcd2hex
  	load_y (1)
  	lcall sub32
  	mov bcd, x
  	mov bcd+1, x+1
    lcall hex2bcd
  	mov soak_seconds+1, bcd+1
	mov soak_seconds+0, bcd+0
	
	
no_dec_soak_sec:
  jb CYCLE_BUTTON, CB_not_pressed
	Wait_Milli_Seconds(#50)
	jb CYCLE_BUTTON, CB_not_pressed
	jnb CYCLE_BUTTON, $
	ljmp SoakTemp
CB_not_pressed:
  ljmp SoakTime

	
SoakTemp:
	Set_Cursor(1,1)
	Send_Constant_String(#SoakTemp_Message)
	Set_Cursor(2,1)
  Display_BCD(soak_temp+1)
	Display_BCD(soak_temp)
	
	jb INC_BUTTON, no_inc_soak_temp
	Wait_Milli_Seconds(#50)
	jb INC_BUTTON, no_inc_soak_temp
	Wait_Milli_Seconds(#200)
 	mov bcd+3, #0
	mov bcd+2, #0
  	mov bcd+1, soak_temp+1
	mov bcd+0, soak_temp+0
	lcall bcd2hex
 	load_y (1)
  	lcall add32
    lcall hex2bcd
  	mov soak_temp+1, bcd+1
	mov soak_temp+0, bcd+0
	
no_inc_soak_temp:
	jb DEC_BUTTON, no_dec_soak_temp
	Wait_Milli_Seconds(#50)
	jb DEC_BUTTON, no_dec_soak_temp	
	Wait_Milli_Seconds(#200)
 	mov bcd+3, #0
	mov bcd+2, #0
  	mov bcd+1, soak_temp+1
	mov bcd+0, soak_temp+0
	lcall bcd2hex
  	load_y (1)
  	lcall sub32
    lcall hex2bcd
  	mov soak_temp+1, bcd+1
	mov soak_temp+0, bcd+0

no_dec_soak_temp:	
  	jb CYCLE_BUTTON, CB_not_pressed1
	Wait_Milli_Seconds(#50)
	jb CYCLE_BUTTON, CB_not_pressed1
	jnb CYCLE_BUTTON, $
	ljmp ReflowTime
CB_not_pressed1:
  	ljmp SoakTemp
	
ReflowTime:
	Set_Cursor(1,1)
	Send_Constant_String(#ReflowTime_Message)
	Set_Cursor(2,1)
  	Display_BCD(reflow_seconds+1)
	Display_BCD(reflow_seconds)
	
	jb INC_BUTTON, no_inc_reflow_time
	Wait_Milli_Seconds(#50)
	jb INC_BUTTON, no_inc_reflow_time
	Wait_Milli_Seconds(#200)
 	mov bcd+3, #0
	mov bcd+2, #0
  	mov bcd+1, reflow_seconds+1
	mov bcd+0, reflow_seconds+0
	lcall bcd2hex
  	load_y (1)
  	lcall add32
    lcall hex2bcd
  	mov reflow_seconds+1, bcd+1
	mov reflow_seconds+0, bcd+0
	
no_inc_reflow_time:
	jb DEC_BUTTON, no_dec_reflow_time
	Wait_Milli_Seconds(#50)
	jb DEC_BUTTON, no_dec_reflow_time	
	Wait_Milli_Seconds(#200)
 	mov bcd+3, #0
	mov bcd+2, #0
  	mov bcd+1, reflow_seconds+1
	mov bcd+0, reflow_seconds+0
	lcall bcd2hex
  	load_y (1)
  	lcall sub32
    lcall hex2bcd
  	mov reflow_seconds+1, bcd+1
	mov reflow_seconds+0, bcd+0
	
no_dec_reflow_time:
	jb CYCLE_BUTTON, CB_not_pressed2
	Wait_Milli_Seconds(#50)
	jb CYCLE_BUTTON, CB_not_pressed2
	jnb CYCLE_BUTTON, $
	ljmp ReflowTemp
CB_not_pressed2:
	ljmp ReflowTime


ReflowTemp:
	Set_Cursor(1,1)
	Send_Constant_String(#ReflowTemp_Message)
	Set_Cursor(2,1)
  	Display_BCD(reflow_temp+1)
	Display_BCD(reflow_temp)
	
	jb INC_BUTTON, no_inc_reflow_temp
	Wait_Milli_Seconds(#50)
	jb INC_BUTTON, no_inc_reflow_temp
	Wait_Milli_Seconds(#200)
 	mov bcd+3, #0
	mov bcd+2, #0
  	mov bcd+1, reflow_temp+1
	mov bcd+0, reflow_temp+0
	lcall bcd2hex
  	load_y (1)
  	lcall add32
    lcall hex2bcd
  	mov reflow_temp+1, bcd+1
	mov reflow_temp+0, bcd+0
	
no_inc_reflow_temp:
	jb DEC_BUTTON, no_dec_reflow_temp
	Wait_Milli_Seconds(#50)
	jb DEC_BUTTON, no_dec_reflow_temp	
	Wait_Milli_Seconds(#200)
 	mov bcd+3, #0
	mov bcd+2, #0
  	mov bcd+1, reflow_temp+1
	mov bcd+0, reflow_temp+0
	lcall bcd2hex
  	load_y (1)
  	lcall sub32
    lcall hex2bcd
  	mov reflow_temp+1, bcd+1
	mov reflow_temp+0, bcd+0
	
no_dec_reflow_temp:
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

