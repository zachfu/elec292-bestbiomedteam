; File: Oven Controller - Final.asm
; ELEC 292 BIOMEDICAL ENGINEERING DESIGN STUDIO 
; PROJECT 1 - OVEN REFLOW CONTROLLER  
; TEAM A1:
; ZACHARY FU		HOOMAN VASELI
; KAY XI			DANIEL ZHOU
; ANGUS TSANG		SALLY WANG

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
	ljmp Timer0_ISR
	
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
	
;++++++++++++++++++ CONSTANTS ++++++++++++++++++++
VLED 				EQU 207							; Typical LED voltage drop (*100)
;++++++++++++++++++ TIME SENSITIVE +++++++++++++++
CLK           		EQU 22118400							 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE  	  	EQU 4096     							 ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD	  	EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE  	  	EQU 1000     							 ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD 		EQU ((65536-(CLK/TIMER2_RATE)))
BAUD 		  		EQU 115200
T1LOAD 		 		EQU (0x100-(CLK/(16*BAUD)))

SAMPLE_INTERVAL 	EQU 250						; Millisecond Interval when sampling (KEEP LESS THAN 256)

PWM_PERCENT			EQU 20						; % of each PWM cycle that output is high
PWM_RELOAD_HIGH 	EQU (255*PWM_PERCENT/100)	
PWM_RELOAD_LOW 		EQU	(255 - PWM_RELOAD_HIGH)

SHORT_BEEP_LENGTH	EQU 4	; Length of short beep (in 100s of ms)
LONG_BEEP_LENGTH 	EQU 10 	; Length of long beep (in 100s of ms)
SIX_BEEP_LENGTH 	EQU 12	; Total length of six beep sequence (in 100s of ms) (Keep at 12)
;------------------------------------------------

;++++++++++++++++++ SPI PINS ++++++++++++++++
CE_ADC  EQU P2.0
MY_MOSI EQU P2.1
MY_MISO EQU P2.2
MY_SCLK EQU P2.3
;--------------------------------------------

;++++++++++++++++++ LCD PINS ++++++++++++++++
LCD_RS EQU P1.2
LCD_RW EQU P1.3
LCD_E  EQU P1.4
LCD_D4 EQU P3.2
LCD_D5 EQU P3.3
LCD_D6 EQU P3.4
LCD_D7 EQU P3.5
;--------------------------------------------

;++++++++++++++++++ I/O +++++++++++++++++++++
GREEN 	EQU P2.4	; Green LED
YELLOW 	EQU P2.5	; Yellow LED
RED		EQU	P2.6	; Red LED
BLUE	EQU P2.7	; Blue LED

SSR_OUT    	    EQU P3.7	; Pin connected to SSR
SOUND_OUT       EQU P1.0	; Pin connected to speaker
BOOT_BUTTON     EQU P4.5	; Boot button (unused aside from bootloader)
							; ----- BEFORE REFLOW ------ / --- DURING SELECTION AND REFLOW --- ;
CYCLE_BUTTON    EQU P0.0 	; Cycle through parameters   / Abort reflow process
INC_BUTTON		EQU P0.2	; Increment parameter values / Confirm choices
DEC_BUTTON      EQU P0.4	; Decrement parameter values / Decline choices
;--------------------------------------------

$NOLIST
$include(LCD_4bit.inc) 	; LCD related functions and utility macros
$include(math32.inc) 	; 32 bit functions and macros					
$include(MCP3008.inc)	; Initializing & communicating with the MCP3008						  
$include(SerialPort.inc); Initializing & sending data through serial port

DSEG at 0x30

	Count1ms:	 		ds 2 ; Incremented every 1ms when Timer 2 ISR is triggered, used to determine when 1s has passed
	Count100ms:			ds 1 ; Incremented every 1ms when Timer 2 ISR is triggered, used to determine when 0.1s has passed
	Count_Sample:		ds 1 ; Sample is taken every 250ms
	Count_PWM:			ds 1 ; PWM cycle runs every 255ms
	soak_seconds: 		ds 1 ; Parameter for run-time of soak stage
	soak_temp: 			ds 1 ; Parameter for target temperature of soak stage
	reflow_seconds: 	ds 1 ; Parameter for run-time of reflow stage
	reflow_temp: 		ds 1 ; Parameter for target temperature of reflow stage
  	run_time_min:		ds 1 ; Total process run-time (minutes)
	run_time_sec: 		ds 1 ; Total process run-time (seconds)
	state_time:			ds 1 ; Run-time for each stage of process
	Short_Beep_Counter:	ds 1 ; Duration/Rhythm counter for short beep
	Long_Beep_Counter:  ds 1 ; Duration/Rhythm counter for long beep
	Six_Beep_Counter:	ds 1 ; Duration/Rhythm counter for six intermittent beeps
	
;+++++++++ Calculation variables +++++++++++	
	x:  	    	ds 4	; Operand 1 of math macros
	y:   			ds 4	; Operand 2 of math macros
	Result: 		ds 2	; Variable storing result of ADC read calls
	bcd:			ds 5	; Variable storing result of hex2bcd macro calls
	x_lm335:		ds 4	; Cold junction temperature (from LM335)
	Vcc:			ds 4	; Vcc * 10^6
;--------------------------------------------
	state:			ds 1
	current_temp:	ds 4

	

BSEG
	mf: 					dbit 1	; Math flag - required for math32.inc
	one_min_flag: 			dbit 1	; Flag set after first 60 seconds of run-time
	pwm_on: 				dbit 1	; Flag set to turn PWM on
	pwm_high: 				dbit 1	; Flag set when PWM output is currently high
 	settings_modified_flag:	dbit 1  ; Flag set when parameters have been changed
	sample_flag:			dbit 1  ; Flag set every SAMPLE_INTERVAL milliseconds to take a reading
  	short_beep_flag:		dbit 1	; Flag set to play a short beep
	long_beep_flag:			dbit 1	; Flag set to play a long beep
	six_beep_flag:			dbit 1	; Flag set to play six intermittent beeps
	led_flag:				dbit 1	; Flag used to flash LEDs in some situations

CSEG
							;   1234567890123456    <- This helps determine the location of the Strings
  	StartMessage:		 	db ' Reflow Control ', 0
  	StartMessage2:   		db 'Start / Settings', 0
	SoakTime_Message:  		db 'Soak Time       ', 0
	SoakTemp_Message: 		db 'Soak Temperature', 0
	ReflowTime_Message: 	db 'Reflow Time     ', 0
	ReflowTemp_Message: 	db 'Reflow Temp     ', 0
	Start_Message: 			db 'Start Process?  ', 0
  	Y_N_Message:			db '  - No | + Yes  ', 0
  	TempTooHighMsg:			db ' Cooling...     ', 0
  	TempTooHighMsg2:      	db ' Please Wait    ', 0
  	SaveToFlash_Msg:		db '   Data Saved   ', 0
  	Stopped:				db 'Process Stopped ', 0
  	BlankMsg:				db '                ', 0
  	ChooseChangeValueMsg:	db '- Reselect Vals	', 0
  	ChooseStartMsg:			db '+	Start Reflow', 0
  	Ramp2Reflow:			db 'Ramp to Reflow  ', 0
  	Ramp2Soak:				db 'Ramp to Soak    ', 0
  	Soak:					db 'Preheat / Soak  ', 0
  	Reflow:					db 'Reflow          ', 0
  	Cooling:				db 'Cooling         ', 0
  	CompleteMsg:			db 'Reflow Complete!', 0
  	Lessthan50ErrorMsg:  	db 'Check T-Couple! ', 0
  	AbortMsg:				db 'Process Aborted!', 0
  	ConfirmMsg: 			db '- Continue?     ', 0
	BurnMsg:				db 'PCB Burn Warning', 0
  	StopMsg:				db ' Press Stop     ', 0
  	
  	Cels: 					db ' ',11011111b, 'C',0
  	Secs:					db ' s',0
  
  ;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 0                     ;
;---------------------------------;
Timer0_Init:
	mov a, TMOD
	anl a, #0xf0 						; Clear the bits for timer 0
	orl a, #0x01 						; Configure timer 0 as 16-timer
	mov TMOD, a
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	; Enable the timer and interrupts
	setb ET0  							; Enable timer 0 interrupt
	clr TR0  							; Disable timer 0 by default
ret
	
;---------------------------------;
; ISR for timer 0.  Set to execute;
; every 1/4096Hz to generate a    ;
; 2048 Hz square wave at pin P1,0 ;
;---------------------------------;
Timer0_ISR:
	;clr TF0  ; According to the data sheet this is done for us already.
	; In mode 1 we need to reload the timer.
	clr TR0
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	setb TR0
	cpl SOUND_OUT ; Connect speaker to P3.6!
	reti
  
;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 2                     ;
;---------------------------------;
	
Timer2_Init:
	mov T2CON, #0 						; Stop timer/counter.  Autoreload mode.
	mov RCAP2H, #high(TIMER2_RELOAD)
	mov RCAP2L, #low(TIMER2_RELOAD)
	; Init One millisecond interrupt counter.  It is a 16-bit variable made with two 8-bit parts
	; Initialize all time-sensitive variables
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	mov Count_PWM, a
	mov Count_Sample, a
  	mov soak_seconds, a
  	mov soak_temp, a
  	mov reflow_seconds, a
  	mov reflow_temp, a
  	mov state, a
  	mov state_time, a
  	mov run_time_sec, a
  	mov run_time_min, a
  	mov Count100ms, a
  	mov Short_Beep_Counter, #SHORT_BEEP_LENGTH
  	mov Long_Beep_Counter, #LONG_BEEP_LENGTH
  	mov Six_Beep_Counter, #SIX_BEEP_LENGTH
	; Enable the timer and interrupts
	setb ET2  ; Enable timer 2 interrupt
	setb TR2  ; Enable timer 2
ret

  
;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in ISR
	
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Increment every 1ms  	
  	inc Count100ms		
  	inc Count_Sample		
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Timer2_Inc_100ms
	inc Count1ms+1
  
Timer2_Inc_100ms:

	mov a, Count100ms
	cjne a, #100, Inc_Done_1sec
	; Run following code every 100ms
	clr a
	mov Count100ms, a		; Return to 0
	
	; If any of the beep flags are set, run their corresponding code
	jb short_beep_flag, Timer2_Short_Beep
	jb long_beep_flag, Timer2_Long_Beep
	jb six_beep_flag, Timer2_Six_Beep
	sjmp Inc_Done_1sec
	
Timer2_Short_Beep:	; Plays a short beep
	setb TR0	; Turn on speaker
	dec Short_Beep_Counter		; Decrement from SHORT_BEEP_LENGTH to 0
	mov a, Short_Beep_Counter
	cjne a, #0, Inc_Done_1sec
	; Once counter has reached 0
	clr TR0		; Turn off speaker
	clr short_beep_flag
	mov Short_Beep_Counter, #SHORT_BEEP_LENGTH	; Reload beep counter when done
	sjmp Inc_Done_1sec
	
Timer2_Long_Beep:	; Plays a long beep
	setb TR0	; Turn on speaker
	dec Long_Beep_Counter		; Decrement from LONG_BEEP_LENGTH to 0
	mov a, Long_Beep_Counter
	cjne a, #0, Inc_Done_1sec
	; Once counter has reached 0
	clr TR0		; Turn off speaker
	clr long_beep_flag
	mov Long_Beep_Counter, #LONG_BEEP_LENGTH	; Reload beep counter when done
	sjmp Inc_Done_1sec
	
Timer2_Six_Beep:
	cpl TR0		; Turn speaker on and off every 100ms
	dec Six_Beep_Counter		; Decrement from SIX_BEEP_LENGTH to 0
	mov a, Six_Beep_Counter
	cjne a, #0, Inc_Done_1sec
	; Once counter has reached 0
	clr TR0		; Turn off speaker for good
	clr six_beep_flag
	mov Six_Beep_Counter, #SIX_BEEP_LENGTH		; Reload beep counter when done
	
Inc_Done_1sec:
	; Check if one second has passed
	mov a, Count1ms+0
	cjne a, #low(1000), Inc_Done_Sample
	mov a, Count1ms+1
	cjne a, #high(1000), Inc_Done_Sample
	
	cpl led_flag	; When toggle LEDs every second, when flag is in use
	
	Zero_2B (Count1ms)	; Clear Count1ms bytes 
	
  	inc state_time	; Increment the state run-time, is reset to 0 every state transition
  
	; If 60 seconds has passed, set one_min_flag to check if temperature > 50C
  	mov a, state_time
  	cjne a, #60, Inc_Done_Run_Time	
	setb one_min_flag
	
Inc_Done_Run_Time:
	; Increment total run-time each second
  	inc run_time_sec
  	mov a, run_time_sec
  	cjne a, #60, Inc_Done_Sample
  	; When seconds reaches 60, restore to 0 and increment minutes
 	clr a
  	mov run_time_sec, a
  	inc run_time_min

Inc_Done_Sample:
	; Take a temperature sample and send over serial every SAMPLE_INTERVAL milliseconds
  	mov a, Count_Sample
  	cjne a, #SAMPLE_INTERVAL, Inc_Done_PWM
  
  	setb sample_flag
  
  	clr a
  	mov Count_Sample, a

Inc_Done_PWM:
	; PWM subroutine
	jnb pwm_on, Timer2_ISR_done
	inc Count_PWM
	jnb pwm_high, Inc_Done_PWM_Low

	mov a, Count_PWM
	cjne a, #PWM_RELOAD_HIGH, Timer2_ISR_done
	; When PWM has been high for PWM_RELOAD_HIGH milliseconds, set it to low
	clr pwm_high
	clr SSR_OUT
	
	clr a
	mov Count_PWM, a
	
	sjmp Timer2_ISR_done
	
Inc_Done_PWM_Low:

	mov a, Count_PWM
	cjne a, #PWM_RELOAD_LOW, Timer2_ISR_done
	; When PWM has been low for PWM_RELOAD_LOW milliseconds, set it to high
	setb pwm_high
	setb SSR_OUT
	
	clr a
	mov Count_PWM, a
	
Timer2_ISR_done:
	; Return from timer 2 interrupt
	pop psw
	pop acc
reti

;------------------------------------------------------------------;
; Subroutine to take sample from Thermocouple, LM335, and LED for Vcc
;------------------------------------------------------------------;
Take_Sample:
	clr sample_flag
	; Reading the LED voltage for Vcc
	Average_ADC_Channel(7)	
	lcall Calculate_Vcc
	
	; Reading the cold junction temperature from the LM335
	Average_ADC_Channel(0)
	lcall LM335_Result_SPI_Routine
	
	; Reading the thermocouple temperature
  	Average_ADC_Channel(1)
  	lcall Result_SPI_Routine	; Calculate oven temperature and send over serial
	ret

; Calculates Vcc from measured LED voltage
Calculate_Vcc:
	; Vcc*10^6 = VLED*1023*10000/result 	- Where 'result' is the ADC value of the LED voltage (typically 2.07V*1023/Vcc)
	Move_2B_to_4B (y, result)
	load_X(VLED*1023)
	lcall div32
	load_Y(10000)
	lcall mul32			

	Move_4B_to_4B (Vcc, x)
	
	ret
	
; Calculates cold junction temperature
LM335_Result_SPI_Routine:
	; x_lm335 = Cold Junction Temp * 100 = ((LM335*Vcc*10^6/102300) - 27300)	- Where 'LM335' is the ADC value of the cold junction voltage
	Move_4B_to_4B (y, Vcc)
	lcall mul32			
    load_y (1023)	
    lcall div32
    load_y (2730000)
    lcall sub32
    load_y (100)		
    lcall div32

	Move_4B_to_4B (x_lm335, x)
	
	ret

; Calculates the oven temperature
Result_SPI_Routine:
	; x_kt = Thermocouple Temp * 100 = (KT*Vcc*10^6*1000)/(1023*3133*41) = 100 * (KT*Vcc)/(1023*313.3*41*10^-6)		- Where 'KT' is the ADC value of the thermocouple voltage
	Move_4B_to_4B (y, Vcc)
	
	lcall mul32
	Load_Y(1023)
	lcall div32
	Load_Y(1000)
	lcall mul32	
	Load_Y(3133)	; Gain*10 
	lcall div32
	Load_Y(41)	; Since calculations have been scaled up by 10^6, this is equivalent to dividing by 41*10^-6
	lcall div32
	
	; current_temp = (x_kt + x_lm335)/100
	Move_4B_to_4B (y, x_lm335)
	lcall add32
	Load_Y(100)
	lcall div32

	;update the oven temperature variable
	Move_4B_to_4B (current_temp, x)
	
	lcall hex2bcd

; Sends oven temperature and reflow stage over serial
Send_Serial:
	; Only concerned with three digits of temperature reading
	Send_BCD(bcd+1)
	Send_BCD(bcd)
	mov a, #'\n'
	lcall putchar
	
	; Send state number
	Move_1B_to_4B (x, state)
	lcall hex2bcd
	Send_BCD(bcd)
	mov a, #'\n'
	lcall putchar
ret

;Saving variables to Flash Memory
Save_Configuration:
	; Erase FDATA page 1
	clr EA ; Disables interrupts to allow access to flash memory
	mov MEMCON, #01011000B ; AERS=1, MWEN=1, DMEN=1, 
  ; ^ Erases page in flash memory, enables programming to nonvolatie mem location
  ; Enables nonvolatile data memory and maps it into FDATA space
	mov DPTR, #0x0000 ; Set data pointer to start of flash memory
	mov a, #0xff			; Write 1111 1111 to flash mem
	movx @DPTR, A
	; Load page
	mov MEMCON, #00111000B ; LDPG=1, MWEN=1, DMEN=1
	; Enables loading of multiple bytes to temporary page buffer
	; Enables programming of nonvolatile memory location
	; Enables nonvolatile data memory and map it into FDATA space
	; Save variables
	mov a, soak_temp	; Move soak temperature to accumulator
	movx @DPTR, A			; Save data in buffer
	inc DPTR					; Increment data pointer
	mov a, soak_seconds ; Repeat for remaining variables
	movx @DPTR, A
	inc DPTR
	mov a, reflow_temp
	movx @DPTR,A
	inc DPTR
	mov a, reflow_seconds
	movx @DPTR, A
	; Write Validation Keys to flash memory (Check upon write)
	inc DPTR
	mov a, #0x55 ; First key value (0101 0101)
	movx @DPTR, A
	inc DPTR
	mov a, #0xAA ; Second key value (1010 1010)
	movx @DPTR, A
	; Copy Buffer to Flash
	mov MEMCON, #00011000B ; Copy page to flash
	mov a, #0xff
	movx @DPTR, A
	mov MEMCON, #00000000B ; Disable access to data flash
	setb EA ; Re-enable interrupts
	ret

; Reading variables from flash memory
Load_Configuration:
	mov MEMCON, #00001000B ; Enable read access to data flash
  
	mov dptr, #0x0004 ; Move dptr to first key value location
	movx a, @dptr
	cjne a, #0x55, Load_Defaults ; If keys do not match, write to flash failed, load default values
	inc dptr ; Second key value location
	movx a, @dptr
	cjne a, #0xAA, Load_Defaults ; Check if second keys match or not, if not then load defaults
	; Keys match. Now load saved values from flash
	mov dptr, #0x0000
	movx a, @dptr
	mov soak_temp, a	; Load soak temperature
	inc dptr
	movx a, @dptr
	mov soak_seconds, a ; Load soak time
	inc dptr
	movx a, @dptr
	mov reflow_temp, a ; Load reflow temperature
	inc dptr
	movx a, @dptr
	mov reflow_seconds, a ; Load reflow time
	mov MEMCON, #00000000B ; Disables access to data flashx
	ret
  
; Default (optimal) values for soldering profile
Load_Defaults: ; Load defaults if keys are incorrect
	mov soak_temp, #150
	mov soak_seconds, #45
	mov reflow_temp, #225
	mov reflow_seconds, #30
	mov MEMCON, #00000000B ; Disables access to data flash
	ljmp forever 
 
;------------------------------------------------------------------;
; ********************MACRO LIST***********************************;
;------------------------------------------------------------------;

;------------------------------------------------------------------;
; MACRO for incrementing a variable
;------------------------------------------------------------------;
Inc_variable MAC
	; %0 : inc/dec button    
	; %1 : variable 
	jb %0, no_inc_dec_var%M
	Wait_Milli_Seconds(#50)
	jb %0, no_inc_dec_var%M
	Wait_Milli_Seconds(#100)

	inc %1
	
no_inc_dec_var%M:

ENDMAC

;------------------------------------------------------------------;
; MACRO for decrementing a variable
;------------------------------------------------------------------;
Dec_variable MAC
	; %0 : inc/dec button   
	; %1 : variable 
	jb %0, no_inc_dec_var%M
	Wait_Milli_Seconds(#50)
	jb %0, no_inc_dec_var%M
	Wait_Milli_Seconds(#100)

	dec %1
	
no_inc_dec_var%M:

ENDMAC

;------------------------------------------------------------------;
; MACRO for Showing values with header on LCD
;------------------------------------------------------------------;
Show_Header_and_Value Mac
	; %0: Constant string for the first line on LCD      
	; %1: Value to be shown on second line				
	; %2: Unit
	Set_Cursor(1,1)
	Send_Constant_String(#%0)
	Set_Cursor(2,1)
	Move_1B_to_4B ( x, %1)
	lcall hex2bcd
	Display_BCD_1_digit(bcd+1)
	Display_BCD(bcd)
	Set_Cursor(2,5)
	Send_Constant_String(#%2)
ENDMAC


;------------------------------------------------------------------;
; MACRO for Showing messages with header on LCD
;------------------------------------------------------------------;
Show_Header Mac
	; %0: Top message
	; %1: Bottom message
	Set_Cursor(1,1)
	Send_Constant_String(#%0)
	Set_Cursor(2,1)
	Send_Constant_String(#%1)
ENDMAC

;------------------------------------------------------------------;
; MACRO for Showing 2 values with header on LCD
;------------------------------------------------------------------;
Show_Stage_Temp_Time Mac
	; %0:    Constant string for the first line on LCD         
	; %1: Temperature		
	; %2: Time (minutes)  
	; %3: Time (seconds)
	Set_Cursor(1,1)
	Send_Constant_String(#%0)
  
	Set_Cursor(2,1)	;show temperture
	Move_1B_to_4B ( x, %1)
	lcall hex2bcd
	Display_BCD_1_digit(bcd+1)
	Display_BCD(bcd)

	Set_Cursor(2,5)
	Send_Constant_String(#Cels)

	Set_Cursor(2,11)
	Move_1B_to_4B (x, %2)
	lcall hex2bcd
	Display_BCD(bcd)
	Display_char(#':')
	Move_1B_to_4B (x, %3)
	lcall hex2bcd
	Display_BCD(bcd)

  
 
ENDMAC

;------------------------------------------------------------------;
; MACRO for checking a button and changing state
;------------------------------------------------------------------;
Check_button_for_State_change Mac
	; %0: Constant string for the button name         
	; %1: State to jump to if the button is pressed
	jb %0, no_button_pressed%M
	Wait_Milli_Seconds(#50)
	jb %0, no_button_pressed%M
	jnb %0, $
	
	mov state, #%1
	WriteCommand(#0x01)
	Wait_Milli_Seconds(#2)
no_button_pressed%M:

ENDMAC

;------------------------------------------------------------------;
; MACRO for comparing 2 values and changing state
;------------------------------------------------------------------;
Compare_Values_for_State_Change MAC
	; %0: variable to check
	; %1: value set at using the buttons
	; %2: next state
	mov a, %0
	clr c
	subb a, %1
	jnc values_not_equal%M
	mov state, #%2
	WriteCommand(#0x01)
	Wait_Milli_Seconds(#2)
values_not_equal%M:

ENDMAC
;------------------------------------------------------------------;
; MACRO for turning the SSR off
;------------------------------------------------------------------;
SSR_OFF MAC
    clr pwm_on
    clr pwm_high
    clr SSR_OUT
ENDMAC

;------------------------------------------------------------------;
; MACRO for going to next state
;------------------------------------------------------------------;
check_state MAC
	; %0: State number   
	; %1: Next state
    mov a, state
    cjne a, #%0, skipstate%M
  	sjmp no_skip_state%M
skipstate%M:
    ljmp state%1
no_skip_state%M:
ENDMAC

Over_Limit MAC
	; %0: Parameter
	; %1: Limit
	mov a, %0
	clr c
	dec a
	subb a, #%1			
	jc	Not_over_Limit%M
	; If limit is met, keep parameter at that limit
	mov %0, #%1	
  
Not_over_Limit%M:  
ENDMAC
;------------------------------------------------------------------;
; Main program   (FSM)
;	-state 0:  Start Screen
;	-state 1:  Initialization 	Soak Time  
;	-state 2:  Initialization	Soak Temperature
;	-state 3:  Initialization	Reflow Time
;	-state 4:  Initialization	Reflow Temp
;
;	-state 5:  Storing parameters in flash memory (if changed), and asking for user confirmation to begin process				
; 	-state 6:  Initialising timer and resetting run-time variables
;	-state 10: Ramp to Soak
;	-state 11: Soak
;	-state 12: Ramp to reflow
;	-state 13: Reflow
;	-state 14: Cooling
;	-state 15: Finished successfully
;	-state 16: ERROR State
; 	-state 17: User Abort State
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
    
	SSR_OFF()	; clears  pwm_on ------- pwm_high ------- SSR_OUT ------- in_process				

	clr settings_modified_flag
    clr one_min_flag
    clr sample_flag
    clr short_beep_flag
    clr long_beep_flag
    clr six_beep_flag
    clr led_flag
	clr GREEN
	clr YELLOW
	clr RED
	clr BLUE
	
  	lcall Load_Configuration ; Read values from data flash
	
forever:	
	jnb sample_flag, state0
	lcall Take_Sample

; Main start screen appears on boot 
; Can cycle through each parameter setting or begin process from here
state0:
	check_state (0, 1)	; Check if state is '0', otherwise check if 1, and so on
	; LEDs operate in negative logic - All on at start screen
  	clr GREEN
  	clr YELLOW
  	clr RED
  	clr BLUE
  	
	Show_Header(StartMessage, StartMessage2)	; "Reflow Control || Start / Settings"
  
	Check_button_for_State_change (CYCLE_BUTTON, 1)		; Transition to parameter select states
	Check_button_for_State_change (INC_BUTTON, 5)		; Transition to save/start confirm state
	ljmp forever
	
; Changing Soak Time Parameter
state1:
	check_state (1, 2)
	setb settings_modified_flag	; Set flag to indicate settings have been modified and to trigger flash memory save
	; All LEDs flash on and off in parameter select stages
	jb led_flag, state1ledon	; led_flag is complemented every 1 second in Timer 2 ISR
	setb GREEN
	setb YELLOW
	setb RED
	setb BLUE
	sjmp state1b
state1ledon:
  	clr GREEN
  	clr YELLOW
  	clr RED
  	clr BLUE
state1b:
	Show_Header_and_Value (SoakTime_Message, soak_seconds, Secs)
	; Poll for +/- buttons to modify parameter
	Inc_variable (INC_BUTTON, soak_seconds)
	Dec_variable (DEC_BUTTON, soak_seconds)
	
	; Poll for cycle button to cycle to next parameter stage
	Check_button_for_State_change (CYCLE_BUTTON, 2)
	ljmp forever									
	
; Changing Soak Temperature Parameter
state2:
	check_state (2,3)
	jb led_flag, state2ledon
	setb GREEN
	setb YELLOW
	setb RED
	setb BLUE
	sjmp state2b
state2ledon:
  	clr GREEN
  	clr YELLOW
  	clr RED
  	clr BLUE
state2b:
	Show_Header_and_Value (SoakTemp_Message, soak_temp, Cels)
	Inc_variable  (INC_BUTTON, soak_temp)
	Dec_variable (DEC_BUTTON, soak_temp)
	
	Check_button_for_State_change (CYCLE_BUTTON, 3)
	ljmp forever									

; Changing Reflow Time Parameter
state3:
	check_state (3,4)
	jb led_flag, state3ledon
	setb GREEN
	setb YELLOW
	setb RED
	setb BLUE
	sjmp state3b
state3ledon:
  	clr GREEN
  	clr YELLOW
  	clr RED
  	clr BLUE
state3b:
	Show_Header_and_Value (ReflowTime_Message, reflow_seconds, Secs)	
	Inc_variable  (INC_BUTTON, reflow_seconds)
	Dec_variable (DEC_BUTTON, reflow_seconds)
	
	Over_Limit (reflow_seconds, 45)	; Caps reflow time at 45 seconds max
  
	Check_button_for_State_change (CYCLE_BUTTON, 4)
	ljmp forever									

; Changing Reflow Temperature Parameter
state4:
	check_state (4,5)
	jb led_flag, state4ledon
	setb GREEN
	setb YELLOW
	setb RED
	setb BLUE
	sjmp state4b
state4ledon:
  	clr GREEN
  	clr YELLOW
  	clr RED
  	clr BLUE
state4b:
	Show_Header_and_Value (ReflowTemp_Message, reflow_temp, Cels)		
	Inc_variable  (INC_BUTTON, reflow_temp)
	Dec_variable (DEC_BUTTON, reflow_temp)
	
	Over_Limit (reflow_temp, 235) ; Caps reflow temperature at 235C max
  
	; Poll cycle button to return to start screen
	Check_button_for_State_change (CYCLE_BUTTON, 0)
	ljmp forever									
	
; Saves value in Flash Memory and Presents Confirmation Screen to Start Process
state5:
	check_state (5,6)
	; All LEDs off
	setb GREEN
	setb YELLOW
	setb RED
	setb BLUE
	; If settings have been modified, save into flash memory only once
	jnb settings_modified_flag, state5TempSet
  
	lcall Save_Configuration ; Call to save data to flash memory
	clr settings_modified_flag
	Show_Header (SaveToFlash_Msg, BlankMsg)	; Show "Data Saved" for one second
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
  
state5TempSet:
	mov a, current_temp
	clr c 
	subb a, soak_temp ; Compare to soak temperature parameter
	jc state5AndThreeQuarters ; If temp is too high, do not allow user to continue
	Show_Header (TempTooHighMsg, TempTooHighMsg2) ; Display cooling message, prevent user from starting reflow process
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
	ljmp forever
	
state5AndThreeQuarters:
	Show_Header	(Start_Message, Y_N_Message)		; Ask user for start confirmation
	Check_button_for_State_change (DEC_BUTTON, 0)	; Return to start screen 
	Check_button_for_State_change (INC_BUTTON, 6)	; Or start process
	ljmp forever	

state6:
	check_state (6,10)
	; Clear relevant variables
	clr one_min_flag
	clr a
	mov run_time_sec, a
	mov run_time_min, a
	mov state_time, a
	mov state, #10
	; Play a short beep when starting process
	setb short_beep_flag
	ljmp forever

; Ramp to soak stage - Oven power at 100% until soak temperature is reached
state10:
	check_state (10,11)
	; Flash yellow LED
	jb led_flag, state10ledon
	setb GREEN
	setb YELLOW
	setb RED
	setb BLUE
	sjmp state10b
state10ledon:
  	setb GREEN
  	clr YELLOW
  	setb RED
  	setb BLUE
	
state10b:
	Check_button_for_State_change (CYCLE_BUTTON, 17) ; Poll for abort button
	clr pwm_on		; PWM not used
	setb SSR_OUT	; Oven at 100% power
	
	Show_Stage_Temp_Time (Ramp2Soak, current_temp, run_time_min, run_time_sec)	; Display current stage, temperature, and run-time
	
	jnb one_min_flag, not_one_min      ; Check if 60 seconds has passed
	clr one_min_flag
	mov a, current_temp
	clr c
	cjne a, #50, check_thermocouple  ; Check if thermocouple degree is bigger than 50
check_thermocouple:
	jnc not_one_min   ; If after 60 seconds, temperature is not greater than 50C, thermocouple is likely misplaced. Jump to error stage
	mov state, #16
	setb long_beep_flag	; Play long beep for error
	sjmp state10_Loop
  
not_one_min:
	mov a, soak_temp 
	clr c 
	subb a, current_temp   ; Check if current temperature >= soak temperature
	jnc state10_Loop		; If so, transition to soak stage
  
	mov state, #11
	clr a
	mov state_time, a	; Reset state time to 0 for next state 
 
	setb short_beep_flag ; Play short beep for stage transition
	
state10_Loop:
	ljmp forever
		
; Soak Stage - Oven powered with PWM running at PWM_PERCENT% power	
state11:
	check_state (11,12)
	; Yellow LED solid brightness
	clr YELLOW
	
	Check_button_for_State_change (CYCLE_BUTTON, 17)
	setb pwm_on		; PWM on at PWM_PERCENT% power
	Show_Stage_Temp_Time (Soak, current_temp, run_time_min, run_time_sec)
	mov a, state_time 
	clr c
	subb a, soak_seconds ; Check if soak has been on for the set amount of time
	jc	State11_Loop
  
	mov state, #12 ; If soak time is met, transition to ramp to reflow stage
	clr a
	mov state_time, a	; Reset state time to 0 for next state 
  
	setb short_beep_flag
 

State11_Loop:
	ljmp forever
  
		
; Ramp to Reflow Stage - Oven at 100% power until reflow temperature is reached		
state12:
	check_state (12,13)
	; Flash red LED
	jb led_flag, state12ledon
	setb GREEN
	setb YELLOW
	setb RED
	setb BLUE
	sjmp state12b
state12ledon:
  	setb GREEN
  	setb YELLOW
  	clr RED
  	setb BLUE
state12b:
	Check_button_for_State_change (CYCLE_BUTTON, 17)
	clr pwm_on		; PWM not used
	setb SSR_OUT	; Oven at 100% power
	Show_Stage_Temp_Time (Ramp2Reflow, current_temp, run_time_min, run_time_sec)	;display the current, temperature and running time
	mov a, reflow_temp
	clr c
	subb a, current_temp	; If reflow temperature is reached, transition to reflow stage
	jnc State12Loop
  
	mov state, #13
	setb short_beep_flag
	clr a
	mov state_time, a	; Reset state time to 0 for next state 
  
State12Loop:
	ljmp forever

; Reflow stage - Oven is powered at PWM_PERCENT% power until reflow time is met
state13:
	check_state (13,14)
	clr RED
	Check_button_for_State_change (CYCLE_BUTTON, 17)
	setb pwm_on ; Oven at PWM_PERCENT% power
	Show_Stage_Temp_Time (Reflow, current_temp, run_time_min, run_time_sec);display the current stage and current temperature
  
	; Compare the temperature with 235 degree for safety consideration
	mov a, current_temp
	clr c
	subb a, #235
	jc no_Burn_Warning							;if current temperature >= 235, display warning
	Show_Header(BurnMsg, StopMsg)		;displaying warning message and ask the user to press STOP button to stop reflow process
	setb short_beep_flag				
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
  
no_Burn_Warning: 
	mov a, reflow_seconds
	clr c
	subb a, state_time 
	jnc state13Loop ; Compare if time elapsed = reflow time
	mov state, #14	; Reflow done, move to cooling
	clr a
	mov state_time, a ; Reset state time variable
	setb long_beep_flag	; Long beep to indicate cooling stage
state13Loop:
	ljmp forever

; Cooling stage, power is set to 0, finish and sound multiple beeps when temperature is below 60
state14:
	check_state (14,15)
	; Blue LED solid brightness
	clr BLUE
	setb GREEN
	setb YELLOW
	setb RED
	Check_button_for_State_change (CYCLE_BUTTON, 17)
	SSR_OFF()
	Show_Stage_Temp_Time (Cooling, current_temp, run_time_min, run_time_sec)
	mov a, current_temp
	clr c
	subb a, #60
	jnc state14loop ; If more than 60 degrees, not safe to touch yet
	; Else, six intermittent beeps
	setb six_beep_flag
	mov state, #15 ; Go to done state
state14loop:
	ljmp forever
  
; Cooling completed state, accessed when temperature has cooled down to below 60C
state15:   
	check_state (15,16)
	; Green LED solid brightness
	clr GREEN
	setb YELLOW
	setb RED
	setb BLUE
	Show_Header(CompleteMsg, ConfirmMsg)
	Check_button_for_State_change(DEC_BUTTON, 0)
	ljmp forever
  
; Error state, accessed when measured temperature of thermocouple does not exceed 50C in the first 60 seconds
state16: 			;display error message
	check_state (16,17)
	; Red LED solid brightness
	clr RED
	setb GREEN
	setb YELLOW
	setb BLUE
	SSR_OFF()
	Show_Header(Lessthan50ErrorMsg, ConfirmMsg)	; Error message
	; User acknowledges error and returns to start screen
	Check_button_for_State_change(DEC_BUTTON, 0)
	ljmp forever
  
; Force Quit state, accessed when STOP button is pressed during any reflow stage
state17:
	SSR_OFF()
	; Red LED solid brightness
  	clr RED
	setb GREEN
	setb YELLOW
	setb BLUE
	Show_Header(AbortMsg, ConfirmMsg)
	; User acknowledges abort and returns to start screen
	Check_button_for_State_change(DEC_BUTTON, 0)
	ljmp forever

end

	
	