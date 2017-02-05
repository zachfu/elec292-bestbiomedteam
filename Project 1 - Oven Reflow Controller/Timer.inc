$NOLIST
cseg
;--------------------------------------------------------------------------------------------------
;Purpose: 	-initializing Timers
;Functions:
;			- Timer0_Init:			Timer 0 is OFF by default. TR0 has to be set to 1 for proper functionality				  
;			- Timer2_Init			Timer 2 is ON  by default.
;--------------------------------------------------------------------------------------------------

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
; Routine to initialize the ISR   ;
; for timer 2                     ;
;---------------------------------;
	
Timer2_Init:
	mov T2CON, #0 						; Stop timer/counter.  Autoreload mode.
	mov RCAP2H, #high(TIMER2_RELOAD)
	mov RCAP2L, #low(TIMER2_RELOAD)
	; Init One millisecond interrupt counter.  It is a 16-bit variable made with two 8-bit parts
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Enable the timer and interrupts
	setb ET2  ; Enable timer 2 interrupt
	setb TR2  ; Enable timer 2
ret

$LIST
