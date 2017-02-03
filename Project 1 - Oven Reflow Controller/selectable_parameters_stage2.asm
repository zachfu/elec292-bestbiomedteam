$NOLIST
$MODLP52
$LIST


CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))
BAUD 		  equ 115200
T1LOAD 		  equ (0x100-(CLK/(16*BAUD)))

CE_ADC EQU P2.0
MY_MOSI EQU P2.1
MY_MISO EQU P2.2
MY_SCLK EQU P2.3
LCD_RS equ P1.2
LCD_RW equ P1.3
LCD_E  equ P1.4
LCD_D4 equ P3.2
LCD_D5 equ P3.3
LCD_D6 equ P3.4
LCD_D7 equ P3.5

SOUND_OUT     	    equ P3.7	; Pin connected to speaker
HOURS_BUTTON   	    equ P4.5	; Button to change hours value in set modes
CYCLE_BUTTON        equ P0.0 ;button to change cycles
INC_BUTTON			equ P0.2
DEC_BUTTON          equ P0.4
POWER_BUTTON		equ P0.5

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
Timer0_Count1ms:	 ds 2 ;
Result: 	ds 2
x:  	    ds 4
y:   		ds 4
bcd:		ds 5
x_lm335:	ds 4



BSEG
mf: dbit 1
one_min_flag: dbit 1


CSEG
SoakTime_Message:  db 'Soak Time       ', 0
SoakTemp_Message:  db 'Soak Temperature', 0
ReflowTime_Message: db 'Reflow Time       ',0
ReflowTemp_Message: db 'Reflow Temp       ',0
Start_Message: 		db 'Start?            ',0
Mask_Message: db '                ',0

Send_BCD mac
    push ar0
    mov r0, %0
    lcall ?Send_BCD
    pop ar0
endmac

?Send_BCD:
    push acc
    ; Write most significant digit
    mov a, r0
    swap a
    anl a, #0fh
    orl a, #30h
    lcall putchar
    ; write least significant digit
    mov a, r0
    anl a, #0fh
    orl a, #30h
    lcall putchar
    pop acc
    ret

	
$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$include(math32.inc) ; A library of 32 bit functions and macros
$LIST




;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 2                     ;
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
  clr TR0  ; Disable timer 0 by default
	ret
	
Timer2_Init:
	mov T2CON, #0 ; Stop timer/counter.  Autoreload mode.
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

putchar:
  jnb TI, putchar
  clr TI
  mov SBUF, a
	ret

; Send a constant-zero-terminated string using the serial port
SendString:
  clr A
  movc A, @A+DPTR
  jz SendStringDone
  lcall putchar
  inc DPTR
  sjmp SendString
SendStringDone:
  ret
    
LM335_Result_SPI_Routine:
	mov x+3, #0
  mov x+2, #0
  mov x+1, Result+1
  mov x+0, Result
  load_y (5000000)
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
	Load_Y(5000000)
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
	Send_BCD(bcd+2)
  Send_BCD(bcd+1)
  Send_BCD(bcd)
	
Display_Temp_LCD:	
	mov a, bcd+2
	cjne a, #0, Display_Hundreds	; If temperature is not in the hundreds, don't display hundreds digit (don't show the 0)
	sjmp Display_Clear_Hundreds
Display_Hundreds:
	Set_Cursor(1,1)
	Display_BCD(bcd+2)
	Set_Cursor(1,1)
	Display_char(#' ')
	sjmp Display_Tens
Display_Clear_Hundreds:
	Set_Cursor(1,1)
	Display_char(#' ')
	Display_char(#' ')
Display_Tens:
	Set_Cursor(1,3)
	Display_BCD(bcd+1)
	Display_char(#'.')
	Display_BCD(bcd+0)	
	ret	

	
init:

	; Initialization
    mov SP, #0x7F
    mov PMOD, #0 ; Configure all ports in bidirectional mode
    lcall Timer0_Init
    lcall Timer2_Init
    setb EA   ; Enable Global interrupts
    lcall LCD_4BIT  ; For convenience a few handy macros are included in 'LCD_4bit.inc':
    mov a, #0x00
    mov soak_seconds, #0x00
    mov soak_seconds+1, #0x00
    mov soak_temp, #0x00
    mov soak_temp+1, #0x00
    mov reflow_seconds, #0x00
    mov reflow_Seconds+1, #0x00
    mov reflow_temp, #0x00
    mov reflow_temp+1, #0x00


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


