$NOLIST
$MODLP52
$LIST

VLED 			EQU 207
CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))
PWM_PERCENT EQU 20
PWM_RELOAD_HIGH EQU 255*PWM_PERCENT/100
PWM_RELOAD_LOW EQU	(255 - PWM_RELOAD_HIGH)
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

SSR_OUT    	    equ P3.7	; Pin connected to SSR
BOOT_BUTTON     equ P4.5
PWM_BUTTON      equ P0.3


; Reset vector
org 0x0000
    ljmp init

; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR
	
	
; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
dseg at 0x30
Count1ms:	 ds 2 ; Incremented every 1ms when Timer 2 ISR is triggered
Count_PWM:		ds 1
Vcc:				ds 4
Result: 	ds 2
x:  	    ds 4
y:   		ds 4
bcd:		ds 5
x_lm335:	ds 4


BSEG
mf: 	dbit 1
pwm_on: dbit 1
pwm_high: dbit 1

CSEG
				;   123456789ABCDEF
PWM_ON_MESSAGE: db 'PWM IS ON      ', 0
PWM_OFF_MESSAGE:db 'PWM IS OFF     ', 0
NEWLINE: db '\n'

	
$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$include(math32.inc) ; A library of 32 bit functions and macros					Move_4B_to_4B (dest, origin) ----- Move_2B_to_4B ----- Zero_4B (orig)----- Zero_2B
$include(MCP3008.inc)	;-initializing & communicating with the MCP3008			INIT_SPI ----- DO_SPI_G -----	Read_ADC_Channel (MAC): returns in "result" ----- Average_ADC_Channel (MAC)	: returns in "x"					  
$include(SerialPort.inc)	;initializing & sending data through serial port	InitSerialPort ---- putchar ----- SendString ----- Send_BCD (MAC) ----- Send_Voltage_BCD_to_PuTTY	
$include (Timer.inc) ;-initializing Timers										Timer0_Init	(OFF BY DEFAULT) ----- Timer2_Init (ON BY DEFAULT)
$LIST




;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in ISR
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Increment the 16-bit one milli second counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_PWM
	inc Count1ms+1
	
Inc_Done_1sec:

	mov a, Count1ms+0
	cjne a, #low(1000), Inc_PWM ; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(1000), Inc_PWM
	
	; 1 second has passed ;

	Zero_2B (Count1ms)

Inc_PWM:
	
	jnb pwm_on, Timer2_ISR_done
	inc Count_PWM
	jnb pwm_high, Inc_Done_PWM_Low

	mov a, Count_PWM
	cjne a, #PWM_RELOAD_HIGH, Timer2_ISR_done
	
	clr pwm_high
	clr SSR_OUT
	setb P3.6
	
	clr a
	mov Count_PWM, a
	
	sjmp Timer2_ISR_done

Inc_Done_PWM_Low:

	mov a, Count_PWM
	cjne a, #PWM_RELOAD_LOW, Timer2_ISR_done
	
	setb pwm_high
	setb SSR_OUT
	clr P3.6
	
	clr a
	mov Count_PWM, a

	
Timer2_ISR_done:
	pop psw
	pop acc
	reti


init:
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
    
Main_Loop:
	lcall Check_SSR_Toggle
	lcall Check_PWM_Toggle
	lcall Take_Sample
	Wait_Milli_Seconds(#250)
	sjmp Main_Loop	

Check_SSR_Toggle:
	jb BOOT_BUTTON, SSR_Toggle_Return
	Wait_Milli_Seconds(#50)
	jb BOOT_BUTTON, SSR_Toggle_Return
	clr pwm_on
	cpl SSR_OUT
	Set_Cursor(2,1)
	Send_Constant_String(#PWM_OFF_MESSAGE)
	Wait_Milli_Seconds(#200)
SSR_Toggle_Return:
	ret
	
Check_PWM_Toggle:
	jb PWM_BUTTON, PWM_Toggle_Return
	Wait_Milli_Seconds(#50)
	jb PWM_BUTTON, PWM_Toggle_Return
	jnb PWM_BUTTON, $
	jb pwm_on, PWM_Off
	; Otherwise, turn PWM on ;
	setb pwm_on
	Set_Cursor(2,1)
	Send_Constant_String(#PWM_ON_MESSAGE)
	Wait_Milli_Seconds(#200)
	sjmp PWM_Toggle_Return
PWM_Off:
	clr pwm_on
	clr SSR_OUT
	Set_Cursor(2,1)
	Send_Constant_String(#PWM_OFF_MESSAGE)
	Wait_Milli_Seconds(#200)
PWM_Toggle_Return:
	ret
	
Take_Sample:
	Average_ADC_Channel(7)
	lcall Calculate_Vref
	;fetch result from channel 0 as room temperature
	Average_ADC_Channel(0)
	lcall LM335_Result_SPI_Routine
	;fetch result from channel 1
    Average_ADC_Channel(1)
    lcall Result_SPI_Routine	; 0.5 second delay between samples
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

	lcall hex2bcd

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
end