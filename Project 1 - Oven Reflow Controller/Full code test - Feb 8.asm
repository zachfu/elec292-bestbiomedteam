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
	
;++++++++++++++++++ CONSTANTS ++++++++++++++++++++
VLED 	EQU 207
;++++++++++++++++++ TIMER & BAUDRATE  ++++++++++++
CLK           	EQU 22118400							 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE  	  EQU 4096     							 ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD	  EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE  	  EQU 1000     							 ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD 	EQU ((65536-(CLK/TIMER2_RATE)))
BAUD 		  			EQU 115200
T1LOAD 		 			EQU (0x100-(CLK/(16*BAUD)))

SAMPLE_INTERVAL EQU 250									; Millisecond Interval when sampling (KEEP LESS THAN 256)

PWM_PERCENT			EQU 25
PWM_RELOAD_HIGH EQU (255*PWM_PERCENT/100)
PWM_RELOAD_LOW 	EQU	(255 - PWM_RELOAD_HIGH)
;------------------------------------------------

;++++++++++++++++++ SPI PINS ++++++++++++++++
CE_ADC  EQU P2.0
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
SOUND_OUT       equ P3.6	; Pin connected to speaker

;++++++++++++++++++ CONTROL BUTTONS++++++++++
CYCLE_BUTTON        equ P0.0 	; Button to change cycles
INC_BUTTON					equ P0.2
DEC_BUTTON          equ P0.4
;--------------------------------------------

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$include(math32.inc) ; A library of 32 bit functions and macros					Move_4B_to_4B (dest, origin) ----- Move_2B_to_4B ----- Move_1B_to_4B ----- Zero_4B (orig)----- Zero_2B
$include(MCP3008.inc)	;-initializing & communicating with the MCP3008			INIT_SPI ----- DO_SPI_G -----	Read_ADC_Channel (MAC): returns in "result" ----- Average_ADC_Channel (MAC)	: returns in "x"					  
$include(SerialPort.inc)	;initializing & sending data through serial port	InitSerialPort ---- putchar ----- SendString ----- Send_BCD (MAC) ----- Send_Voltage_BCD_to_PuTTY	
$include (Timer.inc) ;-initializing Timers										Timer0_Init	(OFF BY DEFAULT) ----- Timer2_Init (ON BY DEFAULT)
$LIST

	
; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
DSEG at 0x30

	Count1ms:	 				ds 2 ; Incremented every 1ms when Timer 2 ISR is triggered
	Count_Sample:			ds 1 ; Sample is taken every 250ms
	Count_PWM:				ds 1 ; PWM cycle runs every 255ms
	soak_seconds: 			ds 1
	soak_temp: 				ds 1
	reflow_seconds: 		ds 1
	reflow_temp: 			ds 1
	run_time_sec: 			ds 1
	state_time:				ds 1
	
;+++++++++ 32 bit Calculation variables +++++++++++	
	x:  	    				ds 4
	y:   							ds 4
	Result: 					ds 2
	bcd:							ds 5
	x_lm335:					ds 4
	Vcc:							ds 4
	samplesum:				ds 4
;--------------------------------------------
	state:						ds 1
	current_temp:			ds 4

	

BSEG
	mf: 							dbit 1
	one_min_flag: 		dbit 1	; Set to 1 after first 60 seconds of reflow cycle
	pwm_on: 					dbit 1	; Set to 1 to turn PWM on
	pwm_high: 				dbit 1	; Flag for when PWM output is currently high
  settings_modified_flag:		dbit 1  ; Flag for when parameters have been changed
	sample_flag:			dbit 1  ; Flag turned on every SAMPLE_INTERVAL to take a reading

CSEG
;           								1234567890123456    <- This helps determine the location of the Strings
  StartMessage:		 			db ' Reflow Control ', 0
  StartMessage2:   			db 'Start / Settings', 0
	SoakTime_Message:  		db 'Soak Time       ', 0
	SoakTemp_Message: 		db 'Soak Temperature', 0
	ReflowTime_Message: 	db 'Reflow Time     ', 0
	ReflowTemp_Message: 	db 'Reflow Temp     ', 0
	Start_Message: 			db 'Start Process?  ', 0
  Y_N_Message:					db '  - No | + Yes  ', 0
	PWM_ON_MESSAGE: 		db 'PWM IS ON       ', 0
	PWM_OFF_MESSAGE:		db 'PWM IS OFF      ', 0
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
  	Temp:					db 'Temp:', 0		
  	Time:					db 'Time:', 0
	NEWLINE: 				db '\n', 0  
  Cels: db ' ',11011111b, 'C',0
  Secs:			db ' s',0
	TestMessage: 			db ' ITS WORKING!?  ', 0
;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in ISR
	
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
	
    
  inc Count_Sample
	; Increment the 16-bit one mili second counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done_1sec
	inc Count1ms+1

	
Inc_Done_1sec:
	; Check if one second has passed
	mov a, Count1ms+0
	cjne a, #low(1000), Inc_Done_Sample ; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(1000), Inc_Done_Sample
	
	; 1 second has passed.  Set a flag so the main program knows
	
	Zero_2B (Count1ms)
  
	; total time passed for each stage (it will be set to 0 when the stage starts)
	inc run_time_sec
  ; time for state, will reset after every state
  inc state_time
  
  mov a, state_time
  cjne a,#60, Inc_Done_Sample
	setb one_min_flag

Inc_Done_Sample:
	
  mov a, Count_Sample
  cjne a, #SAMPLE_INTERVAL, Inc_Done_PWM
  
  setb sample_flag
  
  clr a
  mov Count_Sample, a

Inc_Done_PWM:
	
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
	clr sample_flag
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
  
  Load_Y(100)
  lcall div32

	;updating the temperature of OVEN variable
	Move_4B_to_4B (current_temp, x)
	
	lcall hex2bcd

;sending Oven temperature to Computer
Send_Serial:
	
	Send_BCD(bcd+1)
	Send_BCD(bcd+0)
	mov a, #'\n'
	lcall putchar
	
	Set_Cursor(1,1)
	
Display_Temp_LCD:			;TODOOO 		to be changed according to need
	Display_BCD(bcd+4)
	Display_BCD(bcd+3)
	Display_BCD(bcd+2)
	Display_BCD(bcd+1)
	Display_BCD(bcd)
	
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
	;Mac (%0 : inc/dec button    %1 : variable ) 
	jb %0, no_inc_dec_var%M
	Wait_Milli_Seconds(#50)
	jb %0, no_inc_dec_var%M
  Wait_Milli_Seconds(#200)

	inc %1
	
no_inc_dec_var%M:

ENDMAC

;------------------------------------------------------------------;
; MACRO for decrementing a variable
;------------------------------------------------------------------;
Dec_variable MAC
	;Mac (%0 : inc/dec button    %1 : variable ) 
	jb %0, no_inc_dec_var%M
	Wait_Milli_Seconds(#50)
	jb %0, no_inc_dec_var%M
	Wait_Milli_Seconds(#200)

	dec %1
	
no_inc_dec_var%M:

ENDMAC

;------------------------------------------------------------------;
; MACRO for Showing values with header on LCD
;------------------------------------------------------------------;
Show_Header_and_Value Mac
	; MAC (%0:    Constant string for the first line on LCD       %1: value to be shown on second line				%2: unit )
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
	Set_Cursor(1,1)
  Send_Constant_String(#%0)
  Set_Cursor(2,1)
  Send_Constant_String(#%1)
ENDMAC

;------------------------------------------------------------------;
; MACRO for Showing 2 values with header on LCD
;------------------------------------------------------------------;
Show_Stage_Temp_Time Mac
	; MAC (%0:    Constant string for the first line on LCD           %1: Temperature			%2: Time )
	Set_Cursor(1,1)
	Send_Constant_String(#%0)
  
  Set_Cursor(2,1)	;show temperture
	Move_1B_to_4B ( x, %1)
	lcall hex2bcd
  Display_BCD_1_digit(bcd+1)
	Display_BCD(bcd)

  Set_Cursor(2,12)	;display time in seconds TODO: put it in minute and seconds
	Move_1B_to_4B ( x, %2)
	lcall hex2bcd
  Display_BCD(bcd+1)
	Display_BCD(bcd)
  Set_Cursor(2,16)
  Display_char(#'s')
  
	Set_Cursor(2,5)
	Send_Constant_String(#Cels)
  
 
ENDMAC

;------------------------------------------------------------------;
; MACRO for checking a button and changing state
;------------------------------------------------------------------;
Check_button_for_State_change Mac
	; MAC (%0:    Constant string for the button name           %1: state to jump to if the button is pressed )
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
	;	%0: variable to check
	;	%1: value set at using the buttons
	;	%2: next state
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
		; %0 state number    %1 next state
    mov a, state
    cjne a, #%0, skipstate%M
  	sjmp no_skip_state%M
skipstate%M:
    ljmp state%1
no_skip_state%M:
ENDMAC
;------------------------------------------------------------------;
; Main program   (FSM)
;	-state 0:  Start Screen
;	-state 1:  initialization 	Soak Time  
;	-state 2:  initialization		Soak Temperature
;	-state 3:  initialization		Reflow Time
;	-state 4:  initialization		Reflow Temp
;
;	-state 5:  Storing the variables in flash memory, and asking for user confirmation to begin process				
; -state 6:  initialising Timer and resetting Global Timer
;	-state 10: Ramp to Soak
;	-state 11: Soak
;	-state 12: Ramp to reflow
;	-state 13: Reflow (Done for now, possible additions check if temperature goes too high, if so then begin cooling immediately etc.)
;	-state 14: Cooling
;	-state 15: Finished successfully
;	-state 16: ERROR State
; -state 17: Force Quit State
;------------------------------------------------------------------;
MainProgram:

	; Initialization
    mov SP, #0x7F
    mov PMOD, #0 ; Configure all ports in bidirectional mode
    lcall Timer0_Init
    lcall Timer2_Init
    clr TR2
    setb EA   ; Enable Global interrupts
    lcall INIT_SPI
	lcall InitSerialPort
    lcall LCD_4BIT  ; For convenience a few handy macros are included in 'LCD_4bit.inc':
    
		SSR_OFF()	; clears  pwm_on ------- pwm_high ------- SSR_OUT ------- in_process				

		clr settings_modified_flag
    clr one_min_flag
    clr sample_flag
    
		clr a
    mov soak_seconds, a
    mov soak_temp, a
    mov reflow_seconds, a
    mov reflow_temp, a
    mov state, a
    mov state_time, a
	
  	lcall Load_Configuration ; Read values from data flash
	
forever:	
  jnb sample_flag, state0
  lcall Take_Sample

; Main start screen appears on boot and 
state0:
	check_state (0, 1)
  
  Show_Header(StartMessage, StartMessage2)
  
  Check_button_for_State_change (CYCLE_BUTTON, 1)		; Transition to parameter select states
  Check_button_for_State_change (INC_BUTTON, 5)			; Transition to save/start confirm state
  ljmp forever
; initializing the Soak Time 
state1:
	check_state (1, 2)
	setb settings_modified_flag
  
	Show_Header_and_Value (SoakTime_Message, soak_seconds, Secs)
	Inc_variable (INC_BUTTON, soak_seconds)
	Dec_variable (DEC_BUTTON, soak_seconds)
	
	Check_button_for_State_change (CYCLE_BUTTON, 2)
	ljmp forever									
	
; initializing the Soak Temperature 
state2:
	check_state (2,3)
	Show_Header_and_Value (SoakTemp_Message, soak_temp, Cels)
	Inc_variable  (INC_BUTTON, soak_temp)
	Dec_variable (DEC_BUTTON, soak_temp)
	
	Check_button_for_State_change (CYCLE_BUTTON, 3)
	ljmp forever									

; initializing the Reflow Time 
state3:
	check_state (3,4)
	
	Show_Header_and_Value (ReflowTime_Message, reflow_seconds, Secs)	
	Inc_variable  (INC_BUTTON, reflow_seconds)
	Dec_variable (DEC_BUTTON, reflow_seconds)
	
	Check_button_for_State_change (CYCLE_BUTTON, 4)
	ljmp forever									

; initializing the Reflow Temperature 
state4:
	check_state (4,5)
	
	Show_Header_and_Value (ReflowTemp_Message, reflow_temp, Cels)		
	Inc_variable  (INC_BUTTON, reflow_temp)
	Dec_variable (DEC_BUTTON, reflow_temp)
	
	Check_button_for_State_change (CYCLE_BUTTON, 0)
	ljmp forever									
	
; Saves value in Flash Memory and Presents Confirmation Screen to Start Process
state5:
	check_state (5,6)
	
  jnb settings_modified_flag, state5AndAHalf ; Save values once, once saved skip this
  
	lcall Save_Configuration ; Call to save data to flash memory
	clr settings_modified_flag
	Show_Header (SaveToFlash_Msg, BlankMsg)
  Wait_Milli_Seconds(#250)
  Wait_Milli_Seconds(#250)
  Wait_Milli_Seconds(#250)
  Wait_Milli_Seconds(#250)
  
state5AndAHalf:	

	Show_Header	(Start_Message, Y_N_Message)
	Check_button_for_State_change (DEC_BUTTON, 0)	; Move to state 0 to reselect values
	Check_button_for_State_change (INC_BUTTON, 6)	; Start Process
	; Need beep here;
  ljmp forever	

state6:
	check_state (6,10)
  clr a
  mov run_time_sec, a
  mov state_time, a
  setb sample_flag
  setb TR2
  mov state, #10
  ljmp forever
  
state10:

	check_state (10,11)
  Check_button_for_State_change (CYCLE_BUTTON, 17)
	clr pwm_on			;100% pwm
	setb SSR_OUT		; for 100% power
  Show_Stage_Temp_Time (Ramp2Soak, current_temp, state_time)	;display the current stage and current temperature
  jnb one_min_flag, not_one_min      ;check if 60 seconds has passed
  clr one_min_flag
  mov a, current_temp
  clr c
  cjne a, #50, check_thermocouple  ;check if thermocouple degree is bigger than 50
check_thermocouple:
  jnc not_one_min   ;if not bigger than 50, c=1, jump to display error
  mov state, #16
  sjmp state10_Loop
  
not_one_min:
	mov a, soak_temp 
  clr c 
  subb a, current_temp   ;compare current_temp and soak_temp
  jnc state10_Loop
  
  mov state, #11
  clr a
	mov state_time, a	; reset state time to 0 for next state 
  ;--------------------------------------------------------------------;
  ; A short beep
  ;--------------------------------------------------------------------;

  ;TODOOOOO     Need to show the values with labels and stuff. Take sample subroutine only prints the number
	

state10_Loop:
	ljmp forever
		
; Soak Stage		
state11:
	check_state (11,12)
  Check_button_for_State_change (CYCLE_BUTTON, 17)
	setb pwm_on			;25% pwm
	Show_Stage_Temp_Time (Soak, current_temp, state_time)	;display the current stage and current temperature
	mov a, state_time
	cjne a, soak_seconds, State11_Loop
  
  mov state, #12 ;if time is equal set state to 12
  clr a
	mov state_time, a	; reset state time to 0 for next state 
  ;--------------------------------------------------------------------;
  ; A short beep
  ;--------------------------------------------------------------------;
;time_not_equal:
  ;compare temp													pattern to check temp:								       ____     
;  mov a, current_temp ;									     														____      /    \____/
;	clr c								; 																								 /    \____/     
;	subb a, soak_temp 	;                     												____/
;	jnc temp_too_low		
;	sjmp State11_done:	;									checks every temperature twice for the right one
  																			
;temp_not_low:		
;	inc current_temp
;  inc current temp
;	mov a, current_temp 
;	clr c
;	subb a, soak_temp 
;	jnc temp_too_high
;  sjmp State11_done:

;temp_too_high:  
;  dec current_temp

State11_Loop:
  ljmp forever
  
		
; Ramp to Reflow Stage, compare current_temp with reflow_temp		
state12:
	check_state (12,13)
  Check_button_for_State_change (CYCLE_BUTTON, 17)
  clr pwm_on
  setb SSR_OUT	;100% power on
  Show_Stage_Temp_Time (Ramp2Reflow, current_temp, state_time)	;display the current, temperature and running time
  mov a, reflow_temp
  clr c
  subb a, current_temp
  jnc State12Loop
  
	mov state, #13
  clr a
	mov state_time, a	; reset state time to 0 for next state 
  ;--------------------------------------------------------------------;
  ; A short beep
  ;--------------------------------------------------------------------;
State12Loop:
  ljmp forever

; Reflow stage, compare reflow_seconds to current time, move to cooling stage when complete (Still need beep code)
state13:
	check_state (13,14)
  Check_button_for_State_change (CYCLE_BUTTON, 17)
  setb pwm_on ; Set PWM to 25% power
  Show_Stage_Temp_Time (Reflow, current_temp, state_time)	;display the current stage and current temperature
  mov a, reflow_seconds
  cjne a, state_time, state13Loop
  mov state, #14	; Reflow done, move to cooling
  clr a
  mov state_time, a ; Reset state time variable
state13Loop:
	ljmp forever

; Cooling stage, power is set to 0, finish and sound multiple beeps when temperature is below 60
state14:
	check_state (14,15)
  Check_button_for_State_change (CYCLE_BUTTON, 17)
  SSR_OFF()
  Show_Stage_Temp_Time (Cooling, current_temp, state_time)
  mov a, current_temp
  clr c
  subb a, #60
  jnc state14loop ; If more than 60 degrees, not safe to touch yet
  
SafeBeep: ;If temp is safe then beeeeepppppppppppp
  ;--------------------------------------------------------------------;
  ; BEEEEEEEEEEEEEEEEEEEEEEPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP
  ;--------------------------------------------------------------------;
  mov state, #15 ; Go to done state
state14loop:
	ljmp forever
  
; Cooling completed state, accessed when temperature has cooled down to below 60C
state15:   
	check_state (15,16)
  clr TR2
  Show_Header(CompleteMsg, ConfirmMsg)
  Check_button_for_State_change(DEC_BUTTON, 0)
  ljmp forever
  
state16: 			;display error message
	check_state (16,17)
  clr TR2
  SSR_OFF()
	Show_Header(Lessthan50ErrorMsg, ConfirmMsg)	
  Check_button_for_State_change(DEC_BUTTON, 0)
  ljmp forever
  
; Force Quit state, accessed when STOP button is pressed during any reflow stage
state17:
	clr TR2
  SSR_OFF()
	Show_Header(AbortMsg, ConfirmMsg)
  Check_button_for_State_change(DEC_BUTTON, 0)
  ljmp forever
	


end ;-;

	
	
	