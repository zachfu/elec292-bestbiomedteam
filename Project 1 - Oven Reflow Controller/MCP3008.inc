$NOLIST
;+++++++++++++++++++++++++++++++++++++++++++++++++++
;Purpose: -initializing & communicating with the MCP3008
;Functions:
;			- INIT_SPI 					  
;			- DO_SPI_G:					Send a character using the serial port						  
;			- Read_ADC_Channel MAC:		Returns 2 bytes in result
;---------------------------------------------------
CSEG
;----------------------------------------------------
;to initialize the MCP3008
;----------------------------------------------------
INIT_SPI:
	setb MY_MISO ; Make MISO an input pin
	clr MY_SCLK ; For mode (0,0) SCLK is zero
ret



;----------------------------------------------------	
;	Reading from MCP3008
;----------------------------------------------------
DO_SPI_G:
	push acc
	mov R1, #0 ; Received byte stored in R1
	mov R2, #8 ; Loop counter (8-bits)
	
DO_SPI_G_LOOP:
	mov a, R0 ; Byte to write is in R0
	rlc a ; Carry flag has bit to write
	mov R0, a
	mov MY_MOSI, c
	setb MY_SCLK ; Transmit
	mov c, MY_MISO ; Read received bit
	mov a, R1 ; Save received bit in R1
	rlc a
	mov R1, a
	clr MY_SCLK
	djnz R2, DO_SPI_G_LOOP
	pop acc
	
ret

;----------------------------------------------------
;	Read from a channel using Macro
;
;	Returns a 2 byte value in result
;----------------------------------------------------
Read_ADC_Channel MAC
	mov b, #%0
	lcall _Read_ADC_Channel
ENDMAC
	
_Read_ADC_Channel:
	clr CE_ADC
	mov R0, #00000001B ; Start bit:1
	lcall DO_SPI_G
	mov a, b
	swap a
	anl a, #0F0H
	setb acc.7 ; Single mode (bit 7).
	mov R0, a
	lcall DO_SPI_G
	mov a, R1 ; R1 contains bits 8 and 9
	anl a, #00000011B ; We need only the two least significant bits
	mov result+1, a ; Save result high.
	mov R0, #55H ; It doesn't matter what we transmit...
	lcall DO_SPI_G
	mov result+0, R1 ; R1 contains bits 0 to 7. Save result low.
	setb CE_ADC
	
ret

$LIST
	