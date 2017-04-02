/*
	Code for transmitter microcontroller in project 2
	
	TIMERS:
		Timer 0 => Command Signal
		Timer 1 => putty
		Timer 2 => Guid Signal
		Timer 3 => waitms
*/

#include <C8051F38x.h>
#include <stdio.h>
#include "lcd.h"
#include "global.h"


/********* Global Variables ***********/

volatile bit wave_on =1;
volatile bit transmitting=0;

volatile int overflow_count=0;

volatile unsigned char bit_count=0;
volatile char command_char;

//Macro for checking a button being pressed for transmitting the corresponding command
#define TransmitChar(Button, Char) {	if(Button == 0){ 			\
											waitms(50); 			\
											if (Button == 0){		\
												transmitting = 1;	\
												command_char = Char;\
												printf("Transmitting command : %c \n\r", command_char ); \
												TR0=1;} } }

void main (void)
{
	volatile int state=0;
	char speed=0;
	char speed_str[9];
	// Configure the LCD;
	LCD_4BIT();
	
   

	while(1)
	{
	
		if (state==0)
		{
			LCDprint("Set speed",1,1);
			sprintf(speed_str,"%d", (int)speed);
			LCDprint(speed_str,2,1);
			
			command_char=speed;
			
			if(SPEED_UP==0){
				waitms(50);
				if (SPEED_UP == 0){
					if(speed>=100)speed=0;
					else speed++;
					sprintf(speed_str,"%d",(int) speed);
					LCDprint(speed_str,2,1);
					printf("speed=%d",(int)speed);
				}
			}
			
			else if(SPEED_DOWN==0){
				waitms(50);
				if (SPEED_DOWN == 0){
					if(speed>=100)speed=0;
					else speed--;
					sprintf(speed_str,"%d", (int)speed);
					LCDprint(speed_str,2,1);
				}
			}
			
		}	
	
	
		if(state==1)
		{
			LCDprint("Turn Right",1,1);
			LCDprint(" ",2,1);
			command_char='r';
		}
		
		if(state==2)
		{	LCDprint("Turn Left",1,1);
			command_char='l';
		}
		
		if(state==3)
		{
			LCDprint("Stop/Go",1,1);
			command_char='s';
		}
		 
		if(state==4)
		{
			LCDprint("Reverse",1,1);
			command_char='v';
		}
		
		if(state==5)
		{
			LCDprint("Turn around",1,1);
			command_char='o';
		}
	 
	 	if(NEXT==0)
	 	{
	 		waitms(50);
			while(NEXT==0);
			state=(state==5)?0:(state+1);
	 	}
		
		if(SEND==0)
		{
			waitms(50);
			while(SEND==0);
			TR0=1;
		}
		
	  	
	  	/*
	  	//Transmitting signals if not busy
	  	if( transmitting == 0 )
	  	{
		  	TransmitChar(R_TURN, 'R')	//Right turn command
	  		TransmitChar(L_TURN, 'L')	//Left turn command
	  		TransmitChar(STOP  , 'S')	//STOP command
	  		TransmitChar(CONTINUE, 'C')	//forward Command
			TransmitChar(TURN_180, 'O')	//180 degrees return
			TransmitChar(SPEED_UP, 'U')	//Increase the speed
			TransmitChar(SPEED_DOWN, 'D')	//Decrease the speed
			
	  	}
	  	
	  	*/
	}
}

// Timer 0 interrupts every 1ms for transmitting the command signal bits every 10ms
void Timer0_ISR (void) interrupt INTERRUPT_TIMER0
{
	PUSH_SFRPAGE;
	SFRPAGE=0x0;
	// Timer 0 in 16-bit mode doesn't have auto reload
	TH0=(0x10000L-(SYSCLK/(1*TIMER_0_FREQ)))/0x100;
	TL0=(0x10000L-(SYSCLK/(1*TIMER_0_FREQ)))%0x100;
	
    overflow_count++; //1ms has passed
    if(overflow_count==10)// if 10ms has passed (for baudrate 100)
    { 
  	
    	overflow_count=0; //reset counter
  	
    	switch(bit_count) //transmit the correct bit of the character based on bit_count
    	{
  
    		case 0: {wave_on=0; break;}
      		case 1: {ACC = command_char; wave_on = ACC_0; break;}	
      		case 2: {ACC = command_char; wave_on = ACC_1; break;}	
      		case 3: {ACC = command_char; wave_on = ACC_2; break;}	
      		case 4: {ACC = command_char; wave_on = ACC_3; break;}	
      		case 5: {ACC = command_char; wave_on = ACC_4; break;}	
      		case 6: {ACC = command_char; wave_on = ACC_5; break;}	
      		case 7: {ACC = command_char; wave_on = ACC_6; break;}	
      		case 8: {ACC = command_char; wave_on = ACC_7; break;}	
      		case 9: {wave_on = 1; break;}	
      	}
    
	    if (bit_count == 9) // if transmit finished
	    {
	      bit_count=0; //reset bit counter
	      TR0=0;	   //turn of timer 0 until another transmit starts
	      transmitting = 0; //transmitting finished
	    }
	    else bit_count++;
	    
	    TEST_PIN = wave_on; //to test the output
  	}
  
	POP_SFRPAGE;
}

//Timer 2 is for Signal generation
void Timer2_ISR (void) interrupt INTERRUPT_TIMER2
{
	PUSH_SFRPAGE;
	SFRPAGE=0x0;
	TF2H = 0; // Clear Timer2 interrupt flag
	
	GUID_SIG=!GUID_SIG; //Guid signal always oscillates
	
	if(wave_on==1)// If Command Signal is IDLE or its bit is 1, it oscillates
		COMMAND_SIG=GUID_SIG;// To be synchronized with the Guid signal to prevent destructive interference
	else
		COMMAND_SIG=0;// If command signal bit is 0, no oscillation
	
	POP_SFRPAGE;
}