$NOLIST
$MODLP52
$LIST

CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

;ASSUMED FREQUENCIES FOR DIFFERENT PITCHES - UNTESTED;
C7_RATE			EQU 4186
C7		 		EQU ((65536-(CLK/C7_RATE)))
CSHARP7_RATE	EQU 4435
CSHARP7			EQU ((65536-(CLK/CSHARP7_RATE)))
D7_RATE			EQU 4699
D7				EQU ((65536-(CLK/D7_RATE)))
DSHARP7_RATE	EQU 4978
DSHARP7			EQU ((66536-(CLK/DSHARP7_RATE)))
;MORE WILL BE ADDED WHEN CONVENIENT;

SOUND_OUT     	    equ P3.6	; Pin connected to speaker
SHORT_BEEP_BUTTON   equ P0.0	; Press for short beep
LONG_BEEP_BUTTON	equ P0.2	; Press for long beep
SIX_BEEP_BUTTON		equ P0.4	; Press for 6 intermittent beeps

SHORT_BEEP_LENGTH	EQU 4	; Length of short beep (in 100s of ms)
LONG_BEEP_LENGTH 	EQU 10 	; Length of long beep	(in 100s of ms)
SIX_BEEP_LENGTH 	EQU 12	; Total length of six beep sequence (in 100s of ms)(keep at 12 until further notice)

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
Timer2_Count100ms:	 ds 1 	  ; Incremented every 1ms when Timer 2 ISR is triggered, used to determine when 0.1s has passed
Short_Beep_Counter: ds 1
Long_Beep_Counter:  ds 1
Six_Beep_Counter:	  ds 1 ;
; In the 8051 we have variables that are 1-bit in size.  We can use the setb, clr, jb, and jnb
; instructions with these variables.  This is how you define a 1-bit variable:
bseg
short_beep_flag:	dbit 1
long_beep_flag:		dbit 1
six_beep_flag:		dbit 1

cseg
LCD_RS equ P1.2
LCD_RW equ P1.3
LCD_E  equ P1.4
LCD_D4 equ P3.2
LCD_D5 equ P3.3
LCD_D6 equ P3.4
LCD_D7 equ P3.5

$NOLIST
$include(LCD_4bit.inc)
$LIST

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
	mov Timer2_Count100ms, a
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
	
	inc Timer2_Count100ms			; Increment every 1ms
	mov a, Timer2_Count100ms
	cjne a, #100, Timer2_ISR_Return	; Run following code every 100ms
	
	clr a
	mov Timer2_Count100ms, a		; Return to 0
	
	; If any of the beep flags are set, run their corresponding code
	jb short_beep_flag, Timer2_Short_Beep	
	jb long_beep_flag, Timer2_Long_Beep
	jb six_beep_flag, Timer2_Six_Beep
	sjmp Timer2_ISR_Return
	
Timer2_Short_Beep:
	setb TR0
	dec Short_Beep_Counter
	mov a, Short_Beep_Counter
	cjne a, #0, Timer2_ISR_Return
	; Once counter has reached 0
	clr TR0
	clr short_beep_flag
	mov Short_Beep_Counter, #SHORT_BEEP_LENGTH
	sjmp Timer2_ISR_Return
	
Timer2_Long_Beep:
	setb TR0
	dec Long_Beep_Counter
	mov a, Long_Beep_Counter
	cjne a, #0, Timer2_ISR_Return
	; Once counter has reached 0
	clr TR0
	clr long_beep_flag
	mov Long_Beep_Counter, #LONG_BEEP_LENGTH
	sjmp Timer2_ISR_Return
	
Timer2_Six_Beep:
	cpl TR0
	dec Six_Beep_Counter
	mov a, Six_Beep_Counter
	cjne a, #0, Timer2_ISR_Return
	; Once counter has reached 0
	clr TR0
	clr six_beep_flag
	mov Six_Beep_Counter, #SIX_BEEP_LENGTH
	sjmp Timer2_ISR_Return

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
    clr short_beep_flag
    clr long_beep_flag
    clr six_beep_flag
    setb EA   ; Enable Global interrupts
	
Main_Loop:
	lcall Check_Buttons
	sjmp Main_Loop
	
Check_Buttons:
	jb SHORT_BEEP_BUTTON, Check_Long_Button
	Wait_Milli_Seconds(#50)
	jb SHORT_BEEP_BUTTON, Check_Long_Button
	jnb SHORT_BEEP_BUTTON, $
	setb short_beep_flag
	clr long_beep_flag
	clr six_beep_flag
	
Check_Long_Button:
	jb LONG_BEEP_BUTTON, Check_Six_Button
	Wait_Milli_Seconds(#50)
	jb LONG_BEEP_BUTTON, Check_Six_Button
	jnb LONG_BEEP_BUTTON, $
	setb long_beep_flag
	clr short_beep_flag
	clr six_beep_flag

Check_Six_Button:
	jb SIX_BEEP_BUTTON, Check_Button_Return
	Wait_Milli_Seconds(#50)
	jb SIX_BEEP_BUTTON, Check_Button_Return
	jnb SIX_BEEP_BUTTON, $
	setb six_beep_flag
	clr long_beep_flag
	clr short_beep_flag
	
Check_Button_Return:
	ret
END