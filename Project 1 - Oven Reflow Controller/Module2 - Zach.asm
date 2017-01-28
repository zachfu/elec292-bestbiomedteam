; Author: Zachary Fu
; Student#: 10869155
;
; Module2 - Zach.asm: Alarm Clock - Has configurable clock and alarm times, 
; and 12/24-hour formats

$NOLIST
$MODLP52
$LIST

CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

SOUND_OUT     	    equ P3.7	; Pin connected to speaker
HOURS_BUTTON   	    equ P4.5	; Button to change hours value in set modes
MINUTES_BUTTON      equ P0.7	; Button to change minutes value in set modes
SECONDS_BUTTON      equ P0.4	; Button to change seconds value in set modes
HR24_BUTTON  	    equ P0.1	; Button to toggle between time formats
TIME_SEL_BUTTON     equ P2.4	; Button to enter clock set mode
ALARM_SEL_BUTTON    equ P2.1	; Button to enter alarm set mode
ALARM_TOGGLE_BUTTON equ P2.0	; Button to turn alarm on and off


; Reset vector
org 0x0000
    ljmp init

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

; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
dseg at 0x30
Timer2_Count1ms:	 ds 2 ; Incremented every 1ms when Timer 2 ISR is triggered
Timer2_Count1to100ms:ds 1 ; Incremented every 1ms when Timer 2 ISR is triggered, used to determine when 0.1s has passed
Alarm_Rhythm_Step:   ds 1 ; Variable that stores number of 'beats' for the alarm rhythm
Seconds:  	  ds 1 ; Holds the 'seconds' value of clock
Minutes:	  ds 1 ; Holds the 'minutes' value of clock
Hours:		  ds 1 ; Holds the 'hours' value of clock
Alarm_Seconds:ds 1 ; Holds the 'seconds' value of alarm
Alarm_Minutes:ds 1 ; Holds the 'minutes' value of alarm
Alarm_Hours:  ds 1 ; Holds the 'hours' value of alarm

; In the 8051 we have variables that are 1-bit in size.  We can use the setb, clr, jb, and jnb
; instructions with these variables.  This is how you define a 1-bit variable:
bseg
one_second_flag:   dbit 1 ; Set to one in the ISR every time 1s has passed
pm_flag:     	   dbit 1 ; Set to one if time is in pm
pm_flag_alarm:     dbit 1 ; Set to one if the alarm set time is in pm
hr24_flag:		   dbit 1 ; Set to one if time is displayed in 24-hour format
time_alarm_blink:  dbit 1 ; Controls the blinking of the clock display when in time/alarm select mode
stop_clock:		   dbit 1 ; Set to one to stop clock from incrementing
alarm_on:		   dbit 1 ; Set to one when alarm is set
alarm_active:	   dbit 1 ; Set to one when alarm is sounding

cseg
; These 'equ' must match the wiring between the microcontroller and the LCD!
LCD_RS equ P1.2
LCD_RW equ P1.3
LCD_E  equ P1.4
LCD_D4 equ P3.2
LCD_D5 equ P3.3
LCD_D6 equ P3.4
LCD_D7 equ P3.5
$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

;                     1234567890123456    <- This helps determine the location of the counter
Clock_Spacing:    db '  hh:mm:ss      ', 0
AM:			      db 'AM', 0
PM:				  db 'PM', 0
Empty_Line:		  db '                ', 0
Time_Set:         db '    SET TIME    ', 0
Alarm_Set:		  db '    SET ALARM   ', 0
Alarm_Is_On:	  db '    ALARM ON    ', 0
Alarm_Is_Active:  db '****ALARM ON****', 0

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 0                     ;
;---------------------------------;
Timer0_Init:
	mov a, TMOD
	anl a, #0xf0 ; Clear the bits for timer 0
	orl a, #0x01 ; Configure timer 0 as 16-timer
	mov TMOD, a
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	; Enable the timer and interrupts
    setb ET0  ; Enable timer 0 interrupt
    clr TR0   ; Timer 0 off initially
	ret

;---------------------------------;
; ISR for timer 0.  Set to execute;
; every 1/4096Hz to generate a    ;
; 2048 Hz square wave at pin P3.7 ;
;---------------------------------;
Timer0_ISR:
	;clr TF0  ; According to the data sheet this is done for us already.
	; In mode 1 we need to reload the timer.
	clr TR0
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	setb TR0
	cpl SOUND_OUT ; Connect speaker to P3.7!
	reti

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 2                     ;
;---------------------------------;
Timer2_Init:
	mov T2CON, #0 ; Stop timer/counter.  Autoreload mode.
	mov RCAP2H, #high(TIMER2_RELOAD)
	mov RCAP2L, #low(TIMER2_RELOAD)
	; Init One millisecond interrupt counter.  It is a 16-bit variable made with two 8-bit parts
	clr a
	mov Timer2_Count1ms+0, a
	mov Timer2_Count1ms+1, a
	; Enable the timer and interrupts
    setb ET2  ; Enable timer 2 interrupt
    setb TR2  ; Enable timer 2
	ret

;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in ISR
	cpl P3.6 ; To check the interrupt rate with oscilloscope. It must be precisely a 1 ms pulse.
	
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	jnb alarm_active, Timer2_Inc_Count1ms
	inc Timer2_Count1to100ms
	mov a, Timer2_Count1to100ms
	cjne a, #100, Timer2_Inc_Count1ms
	dec Alarm_Rhythm_Step
	mov a, Alarm_Rhythm_Step
	cjne a, #4, Timer2_Alarm_Step_Compared
	
Timer2_Alarm_Step_Compared:
	jc Timer2_Alarm_Step_LT4
	cpl TR0
	sjmp Timer2_Alarm_Step_Return
	
Timer2_Alarm_Step_LT4:
	clr TR0
	cjne a, #0, Timer2_Alarm_Step_Return
	mov Alarm_Rhythm_Step, #12
	
Timer2_Alarm_Step_Return:
	clr a
	mov Timer2_Count1to100ms, a
	
Timer2_Inc_Count1ms:
	inc Timer2_Count1ms+0    ; Increment the low 8-bits first
	mov a, Timer2_Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Timer2_Check_Half_Second
	inc Timer2_Count1ms+1

Timer2_Check_Half_Second:
	mov a, Timer2_Count1ms+0
	cjne a, #low(500), Timer2_Check_Second; Warning: this instruction changes the carry flag!
	mov a, Timer2_Count1ms+1
	cjne a, #high(500), Timer2_Check_Second
	cpl time_alarm_blink	; Complemented every 0.5s, used to blink the ':' when in time set modes
Timer2_Check_Second:
	mov a, Timer2_Count1ms+0
	cjne a, #low(1000), Timer2_ISR_Return ; Warning: this instruction changes the carry flag!
	mov a, Timer2_Count1ms+1
	cjne a, #high(1000), Timer2_ISR_Return
	; 1 second have passed.  Set a flag so the main program knows
	setb one_second_flag ; Let the main program know second has passed
	cpl time_alarm_blink
Timer2_Check_Second_b:
	; Reset to zero the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Timer2_Count1ms+0, a
	mov Timer2_Count1ms+1, a
	
	jb stop_clock, Timer2_ISR_Return
	
	; Increment the clock variables
	mov a, Seconds
	inc a
	clr c	; The result of da instruction is affected by whether or not
	clr ac	; c and ac are 1, so clear them both before using da
	da a
	cjne a, #0x60, Inc_Seconds_Done	; Check if the incremented 'seconds' value is 60 in BCD
	mov Seconds, #0x00					; if so, reset to '00', and increment 'minutes'
	mov a, Minutes
	inc a
	clr c
	clr ac
	da a
	cjne a, #0x60, Inc_Minutes_Done	; Check if the incremented 'minutes' value is 60 in BCD
	mov Minutes, #0x00					; if so, reset to '00', and increment 'hours'
	mov a, Hours
	inc a 
	clr c
	clr ac
	da a
	jb hr24_flag, Inc_Hours_24hr_Check_12	; If flag for 24-hour format is set, use 24-hour rules in incrementing 'hours'
	; Otherwise, use 12-hour rules
	cjne a, #0x12, Inc_Hours_12_to_1		; If new 'hours' is 12 in BCD, set it to '01'
	cpl pm_flag									; also complement the 'pm_flag' to switch between AM/PM
	sjmp Inc_Hours_Done
Inc_Hours_12_to_1:
	cjne a, #0x13, Inc_Hours_Done			; If incremented value is 13 (current value is 12)
	mov Hours, #0x01							; Set 'hours' to '01'
	sjmp Timer2_Check_Alarm
	; 24-hour rules
Inc_Hours_24hr_Check_12:
	cjne a, #0x12, Inc_Hours_24hr_Check_24	; If new 'hours' is 12 in BCD
	setb pm_flag								; Set 'pm_flag' so it remains consistent when switching back to 12-hour
	sjmp Inc_Hours_Done
Inc_Hours_24hr_Check_24:
	cjne a, #0x24, Inc_Hours_Done			; If new 'hours' is 24 in BCD
	mov Hours, #0x00							; Reset 'hours' to '00'
	clr pm_flag									; Clear 'pm_flag' so it remains consistent when switching back to 12-hour
	sjmp Timer2_Check_Alarm
Inc_Hours_Done:
	mov Hours, a				; Move new hours value into memory
	sjmp Timer2_Check_Alarm
Inc_Minutes_Done:
	mov Minutes, a				; Move new minutes value into memory
	sjmp Timer2_Check_Alarm
Inc_Seconds_Done:
	mov Seconds, a				; Move new seconds value into memory
Timer2_Check_Alarm:
	jnb alarm_on, Timer2_ISR_Return		; Don't do anything if alarm isn't set/turned on
	mov a, Alarm_Seconds
	cjne a, Seconds, Timer2_ISR_Return	; Check if clock seconds matches alarm seconds
	mov a, Alarm_Minutes
	cjne a, Minutes, Timer2_ISR_Return 	; Check if clock minutes matches alarm minutes
	mov a, Alarm_Hours
	cjne a, Hours, Timer2_ISR_Return	; Check if clock hours matches alarm hours
	jb pm_flag, Timer2_Check_Alarm_pm	; Check if clock AM/PM matches alarm AM/PM
	jb pm_flag_alarm, Timer2_ISR_Return
	sjmp Timer2_Turn_On_Alarm				; If all of the above checks hold true, set the alarm flag, so alarm will sound
Timer2_Check_Alarm_pm:							; Otherwise, end ISR
	jnb pm_flag_alarm, Timer2_ISR_Return	
Timer2_Turn_On_Alarm:
	setb alarm_active
Timer2_ISR_Return:
	pop psw
	pop acc
	reti

;---------------------------------;
; Main program. Includes hardware ;
; initialization and 'forever'    ;
; loop.                           ;
;---------------------------------;
init:
	; Initialization
    mov SP, #0x7F
    mov PMOD, #0 ; Configure all ports in bidirectional mode
    lcall Timer0_Init
    lcall Timer2_Init
    setb EA   ; Enable Global interrupts
    lcall LCD_4BIT
    ; For convenience a few handy macros are included in 'LCD_4bit.inc':
    setb one_second_flag
	mov Hours, #0x12			; Initialize clock to 12:00:00 AM
	mov Minutes, #0x00
	mov Seconds, #0x00
	mov Alarm_Hours, #0x11		; Initialize alarm to 11:59:59 AM, but alarm is off by default
	mov Alarm_Minutes, #0x59
	mov Alarm_Seconds, #0x59
	mov Alarm_Rhythm_Step, #12
	clr pm_flag
	clr pm_flag_alarm
	clr hr24_flag				; Start in 12-hour format
	clr time_alarm_blink
	clr stop_clock
	clr alarm_on
	clr alarm_active

main_loop_a:
	; Poll for time set button
	jb TIME_SEL_BUTTON, main_loop_b
	Wait_Milli_Seconds(#50)
	jb TIME_SEL_BUTTON, main_loop_b
	Set_Cursor(2, 1)
	Send_Constant_String(#Time_Set)
	ljmp time_sel
	
main_loop_b:
	; Poll for alarm set button
	jb ALARM_SEL_BUTTON, main_loop_c
	Wait_Milli_Seconds(#50)
	jb ALARM_SEL_BUTTON, main_loop_c
	Set_Cursor(2,1)
	Send_Constant_String(#Alarm_Set)
	ljmp alarm_sel_a

main_loop_c:
	; Poll for alarm on/off button
	jb ALARM_TOGGLE_BUTTON, main_loop_d
	Wait_Milli_Seconds(#50)
	jb ALARM_TOGGLE_BUTTON, main_loop_d
	ljmp alarm_toggle	
	
main_loop_d:
	; Poll for 12/24 format toggle button
	jb HR24_BUTTON, main_loop_e1
	Wait_Milli_Seconds(#50)
	jb HR24_BUTTON, main_loop_e1
	ljmp format_toggle
	
main_loop_e1:
	Set_Cursor(2, 1)
	jnb alarm_on, main_loop_e3
	jnb TR0, main_loop_e2
	; If alarm is on and sounding, flash "***" around "ALARM SET" with the alarm rhythm
	Send_Constant_String(#Alarm_Is_Active)
	sjmp main_loop_f
main_loop_e2:
	; If alarm is turned on, but isn't sounding, print "ALARM SET"
	Send_Constant_String(#Alarm_Is_On)
	sjmp main_loop_f
main_loop_e3:
	; If alarm isn't turned on, print nothing in second line
	Send_Constant_String(#Empty_Line)
main_loop_f:
	jnb one_second_flag, main_loop_return
    clr one_second_flag ; We clear this flag in the main loop, but it is set in the ISR for timer 2
    lcall update_LCD
main_loop_return:
	ljmp main_loop_a
	
update_LCD:
	Set_Cursor(1, 1)
    Send_Constant_String(#Clock_Spacing)	; Print the ":"s for the time display on the LCD
update_LCD_without_colons:
	; Print the clock time
	Set_Cursor(1, 3)     
	Display_BCD(Hours) 
	Set_Cursor(1, 6)
	Display_BCD(Minutes)
	Set_Cursor(1, 9)
	Display_BCD(Seconds)
	jb hr24_flag, update_return	; If in 24-hour format, don't print AM/PM
	; Print AM/PM
	Set_Cursor(1, 12)
	jb pm_flag, display_pm
	Send_Constant_String(#AM)	; AM if pm_flag = 0
	ret
display_pm:
	Send_Constant_String(#PM)	; PM if pm_flag = 1
update_return:
    ret
    
time_sel:
	; Turn off the alarm and stop the clock
	clr alarm_active
	clr TR0
	setb stop_clock
	Wait_Milli_Seconds(#200)	; 0.2s delay to make sure button isn't registered as being pressed twice
	jb time_alarm_blink, time_sel_blink	; Alternate every 0.5s printing and unprinting ':'
	Set_Cursor(1, 5)
	Display_Char(#':')
	Set_Cursor(1, 8)
	Display_Char(#':')
	sjmp time_sel_poll
time_sel_blink:
	Set_Cursor(1, 5)
	Display_Char(#' ')
	Set_Cursor(1, 8)
	Display_Char(#' ')
time_sel_poll:
	; Poll for hours button
	jb HOURS_BUTTON, time_minute_sel
	Wait_Milli_Seconds(#50)
	jb HOURS_BUTTON, time_minute_sel
	mov a, Hours
	inc a
	clr c
	clr ac
	da a
	jb hr24_flag, time_hour_sel_24hr_check_12 ; If in 24-hour format, jump to 24-hour rules
	; 12-hour rules, same as in Timer2_ISR
	cjne a, #0x12, time_hour_sel_12_to_1	
	cpl pm_flag	
	sjmp time_hour_sel_done
time_hour_sel_12_to_1:
	cjne a, #0x13, time_hour_sel_done
	mov a, #0x01
	sjmp time_hour_sel_done
time_hour_sel_24hr_check_12:
	; 24-hour rules, same as in Timer2_ISR
	cjne a, #0x12, time_hour_sel_24hr_check_24
	setb pm_flag
	sjmp time_hour_sel_done
time_hour_sel_24hr_check_24:
	cjne a, #0x24, time_hour_sel_done
	mov Hours, #0x00
	clr pm_flag
	sjmp time_minute_sel
time_hour_sel_done:
	mov Hours, a
	sjmp time_sel_loopback
	
time_minute_sel:
	; Poll for minutes button
	jb MINUTES_BUTTON, time_second_sel
	Wait_Milli_Seconds(#50)
	jb MINUTES_BUTTON, time_second_sel
	mov a, Minutes
	inc a
	clr c
	clr ac
	da a
	cjne a, #0x60, time_minute_sel_done
	mov a, #0x00
time_minute_sel_done:
	mov Minutes, a
	sjmp time_sel_loopback
	
time_second_sel:
	; Poll for seconds button
	jb SECONDS_BUTTON, time_sel_return_poll
	Wait_Milli_Seconds(#50)
	jb SECONDS_BUTTON, time_sel_return_poll
	mov a, Seconds
	inc a
	clr c
	clr ac
	da a
	cjne a, #0x60, time_second_sel_done
	mov a, #0x00
time_second_sel_done:
	mov Seconds, a
	sjmp time_sel_loopback
	
time_sel_return_poll:
	; Poll for time set button to be pressed again
	jb TIME_SEL_BUTTON, time_sel_loopback
	Wait_Milli_Seconds(#50)
	jb TIME_SEL_BUTTON, time_sel_loopback
	; Resume clock
	clr stop_clock
	Set_Cursor(2, 1)
	Send_Constant_String(#Empty_Line)
	Wait_Milli_Seconds(#200)	; Another delay to ensure button isn't registered twice
	ljmp main_loop_a

time_sel_loopback:
	; Update the displayed time without interrupting the ':' flashing, then loop back
	lcall update_LCD_without_colons
	ljmp time_sel

alarm_sel_a:
	; All the same logic as in time_sel, only using alarm variables
	clr alarm_on
	clr alarm_active
	clr TR0
	Set_Cursor(1, 3)
	Display_BCD(Alarm_Hours)
	Set_Cursor(1, 6)
	Display_BCD(Alarm_Minutes)
	Set_Cursor(1, 9)
	Display_BCD(Alarm_Seconds)
	jb hr24_flag, alarm_sel_b
	Set_Cursor(1, 12)
	jb pm_flag_alarm, alarm_display_pm
	Send_Constant_String(#AM)
	sjmp alarm_sel_b
alarm_display_pm:
	Send_Constant_String(#PM)
alarm_sel_b:
	jb time_alarm_blink, alarm_sel_blink
	Set_Cursor(1, 5)
	Display_Char(#':')
	Set_Cursor(1, 8)
	Display_Char(#':')
	sjmp alarm_sel_poll
alarm_sel_blink:
	Set_Cursor(1, 5)
	Display_Char(#' ')
	Set_Cursor(1, 8)
	Display_Char(#' ')
alarm_sel_poll:
	Wait_Milli_Seconds(#200)
	jb HOURS_BUTTON, alarm_minute_sel
	Wait_Milli_Seconds(#50)
	jb HOURS_BUTTON, alarm_minute_sel
	mov a, Alarm_Hours
	inc a
	clr c
	clr ac
	da a
	jb hr24_flag, alarm_hour_sel_24hr_check_12
	cjne a, #0x12, alarm_hour_sel_12_to_1
	cpl pm_flag_alarm
	sjmp alarm_hour_sel_done
alarm_hour_sel_12_to_1:
	cjne a, #0x13, alarm_hour_sel_done
	mov a, #0x01
	sjmp alarm_hour_sel_done
alarm_hour_sel_24hr_check_12:
	cjne a, #0x12, alarm_hour_sel_24hr_check_24
	setb pm_flag_alarm
	sjmp alarm_hour_sel_done
alarm_hour_sel_24hr_check_24:
	cjne a, #0x24, alarm_hour_sel_done
	mov Alarm_Hours, #0x00
	clr pm_flag_alarm
	sjmp alarm_minute_sel
alarm_hour_sel_done:
	mov Alarm_Hours, a
	sjmp alarm_sel_loopback
	
alarm_minute_sel:
	jb MINUTES_BUTTON, alarm_second_sel
	Wait_Milli_Seconds(#50)
	jb MINUTES_BUTTON, alarm_second_sel
	mov a, Alarm_Minutes
	inc a
	clr c
	clr ac
	da a
	cjne a, #0x60, alarm_minute_sel_done
	mov a, #0x00
alarm_minute_sel_done:
	mov Alarm_Minutes, a
	sjmp alarm_sel_loopback
	
alarm_second_sel:
	jb SECONDS_BUTTON, alarm_sel_return_poll
	Wait_Milli_Seconds(#50)
	jb SECONDS_BUTTON, alarm_sel_return_poll
	mov a, Alarm_Seconds
	inc a
	clr c
	clr ac
	da a
	cjne a, #0x60, alarm_second_sel_done
	mov a, #0x00
alarm_second_sel_done:
	mov Alarm_Seconds, a
	sjmp alarm_sel_loopback
	
alarm_sel_return_poll:
	jb ALARM_SEL_BUTTON, alarm_sel_loopback
	Wait_Milli_Seconds(#50)
	jb ALARM_SEL_BUTTON, alarm_sel_loopback
	setb alarm_on
	Set_Cursor(2, 1)
	Send_Constant_String(#Alarm_Is_On)
	Wait_Milli_Seconds(#200)
	ljmp main_loop_a

alarm_sel_loopback:
	ljmp alarm_sel_a

alarm_toggle:
	; If alarm is on/off, turn alarm off/on
	jb alarm_on, alarm_turn_off
	; Turn alarm on, set flag
	setb alarm_on
	Wait_Milli_Seconds(#200)	; Delay to prevent button from being registered twice
	ljmp main_loop_a
alarm_turn_off:
	; Turn alarm off, clear all the alarm flags and the timer 0 enable
	clr alarm_on
	clr alarm_active
	clr TR0
	Wait_Milli_Seconds(#200)
	ljmp main_loop_a
	
format_toggle:
	Wait_Milli_Seconds(#200)
	; Switch between 12 and 24-hour formats (This logic is hard to document, requires a whole flow diagram)
	jnb hr24_flag, hr24
	; Time is in 24hr format ;
	mov a, Hours
	jb pm_flag, ampm_pm
	; Time is between 0:00 and 11:59 ;
	cjne a, #0x00, ampm_alarm
	mov Hours, #0x12
	sjmp ampm_alarm
ampm_pm:
	; Time is between 12:00 and 23:59 ;
	cjne a, #0x12, ampm_pm_not_12
	sjmp ampm_alarm
ampm_pm_not_12:
	add a, #0x88
	clr c
	clr ac
	da a
	mov Hours, a
ampm_alarm:
	mov a, Alarm_Hours
	jb pm_flag_alarm, ampm_pm_alarm
	; Time is between 0:00 and 11:59 ;
	cjne a, #0x00, ampm_return
	mov Alarm_Hours, #0x12
	sjmp ampm_return
ampm_pm_alarm:
	; Time is between 12:00 and 23:59 ;
	cjne a, #0x12, ampm_pm_alarm_not_12
	sjmp ampm_return
ampm_pm_alarm_not_12:
	add a, #0x88
	clr c
	clr ac
	da a
	mov Alarm_Hours, a
ampm_return:
	clr hr24_flag
	lcall update_LCD
	ljmp main_loop_a
hr24:
	mov a, Hours
	jb pm_flag, hr24_pm
	; Time is AM, so convert to 24hr format accordingly ;
	cjne a, #0x12, hr24_alarm
	clr a
	mov Hours, a
	sjmp hr24_alarm
hr24_pm:
	cjne a, #0x12, hr24_pm_not_12
	sjmp hr24_alarm
hr24_pm_not_12:
	add a, #0x12
	clr c
	clr ac
	da a
	mov Hours, a
hr24_alarm:
	mov a, Alarm_Hours
	jb pm_flag_alarm, hr24_pm_alarm
	; Time is AM, so convert to 24hr format accordingly ;
	cjne a, #0x12, hr24_return
	clr a
	mov Alarm_Hours, a
	sjmp hr24_return
hr24_pm_alarm:
	cjne a, #0x12, hr24_pm_alarm_not_12
	sjmp hr24_return
hr24_pm_alarm_not_12:
	add a, #0x12
	clr c
	clr ac
	da a
	mov Alarm_Hours, a
hr24_return:
	setb hr24_flag
	lcall update_LCD
	ljmp main_loop_a

END