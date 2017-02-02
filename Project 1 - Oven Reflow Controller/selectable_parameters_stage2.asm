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
CYCLE_BUTTON        equ P0.7 ;button to change cycles
INC_BUTTON			equ P0.6
DEC_BUTTON          equ P0.5
POWER_BUTTON		equ P0.4

; Reset vector
org 0x0000
    ljmp init

; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR
	
	
; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
dseg at 0x30
Count1ms:	 ds 2 ; Incremented every 1ms when Timer 2 ISR is triggered
soak_seconds: ds 2
soak_temp: ds 2
reflow_seconds: ds 2
reflow_temp: ds 2
sec: ds 2


BSEG
mf: dbit 1
one_min_flag dbit 1


CSEG
SoakTime_Message:  db 'Soak Time:', 0
SoakTemp_Message: db 'Soak Temperature', 0
ReflowTime_Message: db 'Reflow Time', 0
ReflowTemp_Message: db 'Reflow Temperature',0
Start_Message: db 'Start?'


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


	
$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$include(math32.inc) ; A library of 32 bit functions and macros
$LIST




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
	
	; Increment the 16-bit one mili second counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1
	
Inc_Done:
	; Check if half second has passed
	mov a, Count1ms+0
	cjne a, #low(1000), Timer2_ISR_done ; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(1000), Timer2_ISR_done
	
	; 500 milliseconds have passed.  Set a flag so the main program knows
	;setb half_seconds_flag ; Let the main program know half second had passed
	; Reset to zero the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
		
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
	
	
	
	
	
Main_loop:

	; Initialization
    mov SP, #0x7F
    mov PMOD, #0 ; Configure all ports in bidirectional mode
    lcall Timer0_Init
    lcall Timer2_Init
    setb EA   ; Enable Global interrupts
    lcall LCD_4BIT  ; For convenience a few handy macros are included in 'LCD_4bit.inc':


; Cycle between stages: Start->SoakTime->SoakTemp->ReflowTime->ReflowTemp	
SoakTime:	
	Set_Cursor(1,1)
	Send_Constant_String(#SoakTime_Message)
	Set_Cursor(2,1)
	Display_BCD(soak_seconds)
	
	jb INC_BUTTON, no_inc
	Wait_Milli_Seconds(#50)
	jb INC_BUTTON, no_inc
	mov a, soak_seconds
	inc a
	clr c
	clr ac
	da a
	mov soak_seconds, a
	
no_inc:
	jb DEC_BUTTON, no_dec
	Wait_Milli_Seconds(#50)
	jb DEC_BUTTON, no_dec	
	mov a, soak_seconds
	dec a
	clr c
	clr ac
	da a
	mov soak_seconds, a
	
no_dec:
	jnb CYCLE_BUTTON, SoakTemp
	Wait_Milli_Seconds(#50)
	jnb CYCLE_BUTTON, SoakTemp
	ljmp SoakTime

	
SoakTemp:
	Set_Cursor(1,1)
	Send_Constant_String(#SoakTemp_Message)
	Set_Cursor(2,1)
	Display_BCD(soak_temp)
	
	jb INC_BUTTON, no_inc
	Wait_Milli_Seconds(#50)
	jb INC_BUTTON, no_inc
	mov a, soak_temp
	inc a
	clr c
	clr ac
	da a
	mov soak_temp, a
	
no_inc:
	jb DEC_BUTTON, no_dec
	Wait_Milli_Seconds(#50)
	jb DEC_BUTTON, no_dec	
	mov a, soak_temp
	dec a
	clr c
	clr ac
	da a
	mov soak_temp, a

no_dec:	
	jnb CYCLE_BUTTON, ReflowTime
	Wait_Milli_Seconds(#50)
	jnb CYCLE_BUTTON, ReflowTime
	ljmp SoakTemp
	
ReflowTime:
	Set_Cursor(1,1)
	Send_Constant_String(#ReflowTime_Message)
	Set_Cursor(2,1)
	Display_BCD(reflow_seconds)
	
	jb INC_BUTTON, no_inc
	Wait_Milli_Seconds(#50)
	jb INC_BUTTON, no_inc
	mov a, reflow_seconds
	inc a
	clr c
	clr ac
	da a
	mov reflow_seconds, a
	
no_inc:
	jb DEC_BUTTON, no_dec
	Wait_Milli_Seconds(#50)
	jb DEC_BUTTON, no_dec	
	mov a, reflow_seconds
	dec a
	clr c
	clr ac
	da a
	mov reflow_seconds, a
	
no_dec:
	jnb CYCLE_BUTTON, ReflowTemp
	Wait_Milli_Seconds(#50)
	jnb CYCLE_BUTTON, ReflowTemp
	ljmp Reflow_Time

ReflowTemp:
	Set_Cursor(1,1)
	Send_Constant_String(#ReflowTemp_Message)
	Set_Cursor(2,1)
	Display_BCD(reflow_temp)
	
	jb INC_BUTTON, no_inc
	Wait_Milli_Seconds(#50)
	jb INC_BUTTON, no_inc
	mov a, reflow_temp
	inc a
	clr c
	clr ac
	da a
	mov reflow_temp, a
	
no_inc:
	jb DEC_BUTTON, no_dec
	Wait_Milli_Seconds(#50)
	jb DEC_BUTTON, no_dec	
	mov a, reflow_temp
	dec a
	clr c
	clr ac
	da a
	mov reflow_temp, a
	
no_dec:
	jnb CYCLE_BUTTON, Start
	Wait_Milli_Seconds(#50)
	jnb CYCLE_BUTTON, Start
	ljmp  Reflow_Temp
	
Start:
	Set_Cursor(1,1)
	Send_Constant_Temp(#Start_Message)
	
	jnb CYCLE_BUTTON, SoakTime
	Wait_Milli_Seconds(#50)
	jnb CYCLE_BUTTON, SoakTime
	
	jnb POWER_BUTTON, RampSoak
	Wait_Milli_Seconds(#50)
	jnb POWER_BUTTON, RampSoak
	ljmp Start

	
RampSoak:
	mov R1, soak_temp
	mov a, 
	cjne a, 01h, check_temp ;if sensor temp<soak_temp c=1
check_temp:
	jnc PreheatSoak  	; If c=0 go to next stage preheat soak
	ljmp RampSoak       ;else loop back to continue checking


PreheatSoak:
	mov R1, soak_time
	mov a, sec
	cjne, a, 01h, check_time     ;if timer seconds<soak_time c=1
check_time:
	jnc Reflow           ;if c=0 go to reflow stage
	ljmp PreheatSoak	 ;else loop back to continue checking
	
Reflow:
	




end