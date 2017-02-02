; Author: Zachary Fu
; Student#: 10869155
;
; Module1 - Zach.asm: Initializes and uses an LCD in 4-bit mode
; using the most common procedure found on the internet.
; Modified from provided LCD_test_4bit.asm
; 
; Displays name and student number, and cycles through a custom message with button 1
; Runs a 'falling arrow' simulation with button 2, controlled with left and right buttons

$NOLIST
$MODLP52
$LIST

org 0000H
    ljmp myprogram

org 001bH
    ljmp 181bH

; These 'equ' must match the hardware wiring
LCD_RS equ P1.2
LCD_RW equ P1.3 ; Not used in this code
LCD_E  equ P1.4
LCD_D4 equ P3.2
LCD_D5 equ P3.3
LCD_D6 equ P3.4
LCD_D7 equ P3.5
BUTTON1 equ P2.2
BUTTON2 equ P4.5
BUTTONL equ P2.4
BUTTONR equ P2.3

; Strings
MY_NAME:
	db 'Zachary Fu',0
MY_ID:
	db '10869155',0
HELLO_WORLD:
	db 'Hello world',0
KONNICHIWA:
	db 0xBA,0xDD,0xC6,0xC1,0xDC,0xA4,0xBE,0xB6,0xB2,0

; When using a 22.1184MHz crystal in fast mode
; one cycle takes 1.0/22.1184MHz = 45.21123 ns

;---------------------------------;
; Wait 40 microseconds            ;
;---------------------------------;
Wait40uSec:
    push AR0
    mov R0, #177
L0:
    nop
    nop
    djnz R0, L0 ; 1+1+3 cycles->5*45.21123ns*177=40us
    pop AR0
    ret

;---------------------------------;
; Wait 'R2' milliseconds          ;
;---------------------------------;
WaitmilliSec:
    push AR0
    push AR1
L3: mov R1, #45
L2: mov R0, #166
L1: djnz R0, L1 ; 3 cycles->3*45.21123ns*166=22.51519us
    djnz R1, L2 ; 22.51519us*45=1.013ms
    djnz R2, L3 ; number of millisecons to wait passed in R2
    pop AR1
    pop AR0
    ret

;---------------------------------;
; Toggles the LCD's 'E' pin       ;
;---------------------------------;
LCD_pulse:
    setb LCD_E
    lcall Wait40uSec
    clr LCD_E
    ret

;---------------------------------;
; Writes data to LCD              ;
;---------------------------------;
WriteData:
    setb LCD_RS
    ljmp LCD_byte

;---------------------------------;
; Writes command to LCD           ;
;---------------------------------;
WriteCommand:
    clr LCD_RS
    ljmp LCD_byte

;---------------------------------;
; Writes acc to LCD in 4-bit mode ;
;---------------------------------;
LCD_byte:
    ; Write high 4 bits first
    mov c, ACC.7
    mov LCD_D7, c
    mov c, ACC.6
    mov LCD_D6, c
    mov c, ACC.5
    mov LCD_D5, c
    mov c, ACC.4
    mov LCD_D4, c
    lcall LCD_pulse

    ; Write low 4 bits next
    mov c, ACC.3
    mov LCD_D7, c
    mov c, ACC.2
    mov LCD_D6, c
    mov c, ACC.1
    mov LCD_D5, c
    mov c, ACC.0
    mov LCD_D4, c
    lcall LCD_pulse
    ret

;---------------------------------;
; Configure LCD in 4-bit mode     ;
;---------------------------------;
LCD_4BIT:
    clr LCD_E   ; Resting state of LCD's enable is zero
    clr LCD_RW  ; We are only writing to the LCD in this program

    ; After power on, wait for the LCD start up time before initializing
    ; NOTE: the preprogrammed power-on delay of 16 ms on the AT89LP52
    ; seems to be enough.  That is why these two lines are commented out.
    ; Also, commenting these two lines improves simulation time in Multisim.
    ; mov R2, #40
    ; lcall WaitmilliSec

    ; First make sure the LCD is in 8-bit mode and then change to 4-bit mode
    mov a, #0x33
    lcall WriteCommand
    mov a, #0x33
    lcall WriteCommand
    mov a, #0x32 ; change to 4-bit mode
    lcall WriteCommand

    ; Configure the LCD
    mov a, #0x28
    lcall WriteCommand
    mov a, #0x0c
    lcall WriteCommand
ClearLCD:
    mov a, #0x01 ;  Clear screen command (takes some time)
    lcall WriteCommand

    ;Wait for clear screen command to finish. Usually takes 1.52ms.
    mov R2, #2
    lcall WaitmilliSec
    ret
;-----------------------------;
; Writes string pointed to by ;
; DPTR to LCD				  ;
;-----------------------------;
WriteString:
	clr a
	movc a, @a + DPTR
	jz WSdone
	lcall WriteData
	inc DPTR
	sjmp WriteString
WSdone:
	ret
	
;---------------------------------;
; Main loop.  Initialize stack,   ;
; ports, LCD, and displays        ;
; name and student # on the LCD   ;
;---------------------------------;
myprogram:
    mov SP, #7FH
    mov PMOD, #0 ; Configure all ports in bidirectional mode
    lcall LCD_4BIT
    
    mov a, #0x80 ; Move cursor to line 1 column 1
    lcall WriteCommand
 	mov DPTR, #MY_NAME
 	lcall WriteString
 	
 	mov a, #0xC0 ; Move cursor to line 2 column 1
 	lcall WriteCommand
 	mov DPTR, #MY_ID
 	lcall WriteString
 	
 	mov R2, #200
 	lcall WaitmilliSec

;-----------------------;
; Polls buttons 1 and 2 ;
;-----------------------;
watchbutton:
	jnb BUTTON1, message_part1
	jnb BUTTON2, gravity
    sjmp watchbutton

;--------------------------;
; Routine that is run when ;
; button 1 is pressed      ;
;--------------------------;
message_part1:
	lcall ClearLCD
	mov a, #0x80
	lcall WriteCommand
	mov DPTR, #HELLO_WORLD
	lcall WriteString
	
	mov R2, #200
	lcall WaitmilliSec
	
message_poll1:
	jnb BUTTON1, message_part2
	sjmp message_poll1
	
message_part2:
	mov a, #0xC0
	lcall WriteCommand
	mov DPTR, #KONNICHIWA
	lcall WriteString
	
	lcall WaitmilliSec

message_poll2:
	jnb BUTTON1, myprogram
	sjmp message_poll2

;--------------------------;
; Routine that is run when ;
; button 2 is pressed      ;
;--------------------------;

gravity:
	lcall ClearLCD
	mov R2, #200
	lcall WaitmilliSec	;  Wait 0.2 seconds for button to be released before continuing
	
gravity_poll:
	jnb BUTTONL, drop_left	;  Poll loop that checks three buttons for action to occur
	jnb BUTTONR, drop_right
	jnb BUTTON2, myprogram
	sjmp gravity_poll

drop_left:	;  Draws falling arrow on left column (top row)
	mov a, #0x8F
	sjmp fall

drop_right:  ;  Draws falling arrow on right column (bottom row)
	mov a, #0xCF
	sjmp fall
	
fall:
	lcall WriteCommand
	mov a, #0x7F
	lcall WriteData  ;  Draw arrow in selected column
	
	mov R1, #15   ;  fall_loop repeats 16 times
	mov a, #0x18  ;  Shift display left command
	mov R2, #250  ;  Arrow falls 4 blocks per second
	
fall_loop:	;  Loops until arrow reaches 1 block from bottom of LCD
	lcall WaitmilliSec
	lcall WriteCommand
	djnz R1, fall_loop
	
	mov R2, #50		;  Arrow reaches bottom of LCD
	lcall WaitmilliSec
	lcall WriteCommand
	
	mov a, #'*'
	lcall WriteData
	lcall WaitmilliSec
	mov a, #0x10
	lcall WriteCommand
	mov a, #'x'
	lcall WriteData
	lcall WaitmilliSec
	mov a, #0x10
	lcall WriteCommand
	mov a, #'|'
	lcall WriteData
	lcall WaitmilliSec
	
	sjmp gravity
	
END