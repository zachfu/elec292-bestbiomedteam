#include <XC.h>
#include <sys/attribs.h>
#include <stdio.h>
#include <stdlib.h> 
#include <math.h>
#include "global.h"
#include "PIC32_LCD.h"
 
// Configuration Bits (somehow XC32 takes care of this)
#pragma config FNOSC = FRCPLL       // Internal Fast RC oscillator (8 MHz) w/ PLL
#pragma config FPLLIDIV = DIV_2     // Divide FRC before PLL (now 4 MHz)
#pragma config FPLLMUL = MUL_20     // PLL Multiply (now 80 MHz)
#pragma config FPLLODIV = DIV_2     // Divide After PLL (now 40 MHz)
#pragma config FSOSCEN = OFF		// Secondary Oscillator disabled 
#pragma config FWDTEN = OFF         // Watchdog Timer Disabled
#pragma config FPBDIV = DIV_1       // PBCLK = SYCLK


volatile unsigned char 	pwm_count;
volatile unsigned char 	base_duty = 70;
volatile unsigned char 	duty1;
volatile unsigned char 	duty2;
volatile unsigned char 	count_ms = 0;
volatile unsigned int  	Light_Counter=0; 
volatile unsigned char  Light_Status=0;
volatile unsigned char  Horn_Status=0;

volatile char 			Command=NullCommand;
volatile int 			an1;
volatile int 			an2;
volatile int 			an3;

volatile unsigned char 			StartTurnFlag=0;
volatile unsigned char 			Turn180_Flag=0;
volatile unsigned char 			Turn_L_Flag=0;
volatile unsigned char 			Turn_R_Flag=0;
volatile unsigned char 			Turn180FirstCall=0;
volatile unsigned char 			Stop_Flag = 0;
volatile unsigned char 			FirstAligned = 0;
volatile unsigned char 			DirectionL = 0;
volatile unsigned char 			DirectionLPrev = 0;
volatile unsigned char 			DirectionR = 0;
volatile unsigned char 			DirectionRPrev = 0;
volatile unsigned char			FallingEdgeBufferFlag = 0;
volatile unsigned char			buffer_valid_flag = 0;

volatile unsigned char			buffer_count = 0;

volatile union 			DISPLAY_BYTE buffer;

volatile float 			voltage1;
volatile float  		voltage2;
volatile float			voltage3;
volatile float 			Misalignment;
volatile float  		speed_adjust;
volatile float			intersect_adjust;

// Configures External Interrupts
void StartBitTriggerConfig(void)
{ 
	IEC0bits.INT1IE = 0;	// Disable external interrupt 1
	INTCONbits.INT1EP = 0;	// Set interrupt condition to falling-edge
	IPC1bits.INT1IP = 7;	// Set priority to 7, highest priority
	IPC1bits.INT1IS = 0;	// Set subpriority for shadow register to 0, unused
	IFS0bits.INT1IF = 0;	// Clear interrupt flag
	IEC0bits.INT1IE = 1;	// Enable external interrupt 1
	INT1R = 3;				// Use Pin RB10 for interrupt
	TRISBbits.TRISB10 = 1;	// Set Pin RB10 as digital input
}

void __ISR(_EXTERNAL_1_VECTOR, IPL7AUTO) StartBitTrigger(void)
{
	IFS0bits.INT1IF = 0;		// Clear interrupt flag
	T1CONbits.ON = 1; 			// Enable Timer 1 to Read Transmitted Commands
	FallingEdgeBufferFlag = 1; 	// Set a flag to cause a 5ms delay in timer0
	IEC0bits.INT1IE = 0;		// Disable external interrupt 1
}

// Briefly halts function to read command sigal detected in wire
void __ISR(_TIMER_1_VECTOR, IPL6AUTO) CommandReceive(void)
{
	count_ms++;							// Increment variable used to control read timing
	
	if( FallingEdgeBufferFlag) {
		if(count_ms==5) {				// After 5ms has passed, clear flag and begin taking 
			FallingEdgeBufferFlag = 0;	// readings at 10ms intervals
			count_ms = 0;				// Reset counter variable
		}
	}
	else
	{	
		if(count_ms==10) {				// Every 10ms
			switch(buffer_count) 		// Receive the correct bit of the character based on bit_count
			{							// Store receive bit in a char in the union buffer
				case 0: {buffer.bit0 = PORTBbits.RB10; break;};
				case 1: {buffer.bit1 = PORTBbits.RB10; break;};	
				case 2: {buffer.bit2 = PORTBbits.RB10; break;};
				case 3: {buffer.bit3 = PORTBbits.RB10; break;};
				case 4: {buffer.bit4 = PORTBbits.RB10; break;};
				case 5: {buffer.bit5 = PORTBbits.RB10; break;};
				case 6: {buffer.bit6 = PORTBbits.RB10; break;};
				case 7: {buffer.bit7 = PORTBbits.RB10; break;};
				case 8: {buffer_valid_flag = PORTBbits.RB10; break;};	// 
			 }
		
			if (buffer_count == 8) 		// If receive completed
			{
				buffer_count=0;    		// Reset bit counter
				IFS0bits.INT1IF = 0;	// Clear interrupt flag	for External Interrupt 1
				IEC0bits.INT1IE = 1;	// Renable External Interrupt 1
				T1CONbits.ON = 0;		// Disable Timer 1 
			}
			else
				buffer_count++;			// Increment buffer count to save to next char	
			
			count_ms = 0;				// Reset count
		}
	}
	
	IFS0CLR=_IFS0_T1IF_MASK; // Clear timer 1 interrupt flag, bit 4 of IFS0	
}		
// Interrupt Service Routine for Timer2 which has Interrupt Vector 8 and initalized with priority level 3
void __ISR(_TIMER_2_VECTOR, IPL5AUTO) Timer2_ISR(void)
{	
	//Handling the turn signals flashing.
	Light_Counter++;
	if (Light_Counter == 4000) //flashing every 255ms
	{
		Light_Status =  (Light_Status==0)?1 : 0 ;
		Horn_Status = (Horn_Status==0)?1 : 0 ;
		AMBER_R = Turn_R_Flag?(Light_Status) : 1 ;	// AMBER_R
		AMBER_L = Turn_L_Flag?(Light_Status) : 1 ;	// AMBER_L
		T3CONbits.ON = (DirectionL==1 && DirectionR==1)?Horn_Status:0;
		Light_Counter = 0;
	}
	
	pwm_count++;			
	
	if(pwm_count==100)
		pwm_count = 0;
	
	if(pwm_count < duty1) {
		if(!DirectionL) 	// Forward = 0, Backwards = 1
		{ 
			H11_PIN = 1;
			H12_PIN = 0;
		}
		else 
		{
			H11_PIN = 0;
			H12_PIN = 1;		
		}
	}
	else
		H11_PIN = H12_PIN;
	
	if(pwm_count < duty2){
		if(!DirectionR)
		{
			H21_PIN = 1;
			H22_PIN = 0;
		}
		else
		{
			H21_PIN = 0;
			H22_PIN = 1;
		}
	}
	else 
		H21_PIN = H22_PIN;
		
	IFS0bits.T2IF = 0;      // Clear timer2 interrupt status flag
}

//handling the Buzzer
void __ISR(_TIMER_3_VECTOR, IPL3AUTO) Timer3_Handler(void)
{
	SOUND_OUT = (SOUND_OUT==1)?0:1;
	IFS0CLR=_IFS0_T3IF_MASK; // Clear timer 3 interrupt flag, bit 4 of IFS0
}

// Configures Timer 1 for use in receiving character bits
void Timer1Configure (void)
{
	PR1 = (SYSCLK/(1000))-1;	// Every 1 ms
	TMR1 = 0;
	T1CONbits.TCKPS = 0; 		// Pre-scaler 1:1
	T1CONbits.TCS = 0;			// Clock source
	T1CONbits.ON = 0;			// Clock turned off
	IPC1bits.T1IP = 6;			// Priority 6
	IPC1bits.T1IS = 0; 			// Subpriority 0, 
	IFS0bits.T1IF = 0;			// Clear timer flag
	IEC0bits.T1IE = 1;			// Enable timer1 interrupts
}

// Enables 16bit Timer2 Interrupts, loads Timer2 Period Register and Starts the Timer
// When Timer2 Interrupts occur, the software must clear the interrupt status flag
void Timer2Configure (void)
{
	// Timer2 Interrupt Inialization from Example 16-8 of Family Reference Manual
	PR2 =(SYSCLK/(FREQ))-1; 	// since SYSCLK/FREQ = PS*(PR1+1)
	TMR2 = 0;
	T2CONbits.TCKPS = 0;		// Pre-scaler 1:1
	T2CONbits.TCS = 0; 			// Clock source
	T2CONbits.ON = 1;			// Turn On Clock
	IPC2bits.T2IP = 5;			// Priority 5
	IPC2bits.T2IS = 0; 			// Subpriority 5
	IFS0bits.T2IF = 0;			// Clear Timer2 interrupt flag
	IEC0bits.T2IE = 1;			// Enable Timer2 interrupts
}

void Timer3Configure (void) //for BUZZER 4000HZ
{
	// Explanation here:
	// https://www.youtube.com/watch?v=bu6TTZHnMPY
	//__builtin_disable_interrupts();
	PR3 =(SYSCLK/(BUZZER_FREQ))-1; // since SYSCLK/FREQ = PS*(PR3+1)
	TMR3 = 0;
	T3CONbits.TCKPS = 0; // Pre-scaler: 1:1
	T3CONbits.TCS = 0; // Clock source
	T3CONbits.ON = 1;
	IPC3bits.T3IP = 3;//***************************************************************************************
	IPC3bits.T3IS = 0;
	IFS0bits.T3IF = 0;
	IEC0bits.T3IE = 1;	//TODO, need to turn off
	
	//INTCONbits.MVEC = 1; //Int multi-vector
	//__builtin_enable_interrupts();
}

/* ADC interrupt service routines, moves ADC values from ADC buffer into variables an1-an3
 * ISR code from http://umassamherstm5.org/tech-tutorials/pic32-tutorials/pic32mx220-tutorials/adc 
*/
void __ISR(_ADC_VECTOR, IPL4AUTO) ADC_ISR(void)
{
	AD1CON1bits.ASAM = 0;           // Stop automatic sampling while reading to buffers
 			
	if( AD1CON2bits.BUFS == 1)	 	// check which buffers are being written to and read from the other set
	{    
		an1 = ADC1BUF0;				// AD1CON2bits.BUFS==1 corresponds to ADC1BUF0-7
		an2 = ADC1BUF1;
		an3 = ADC1BUF2;
	}
	else
	{								// AD1CON2bits.BUFS==0 corresponds to ADC1BUF8-F
   		an1 = ADC1BUF8;	
		an2 = ADC1BUF9;
		an3 = ADC1BUFA;
	}
	
	AD1CON1bits.ASAM = 1;           // restart automatic sampling
	IFS0CLR = 0x10000000;           // clear ADC interrupt flag	
      
}

/* UART2Configure() sets up the UART2 for the most standard and minimal operation
 *  Enable TX and RX lines, 8 data bits, no parity, 1 stop bit, idle when HIGH
 *
 * 	Input: Desired Baud Rate
 * 	Output: Actual Baud Rate from baud control register U2BRG after assignment
 */
void UART2Configure(int baud_rate)
{
    // Peripheral Pin Select
    U2RXRbits.U2RXR = 4;    //SET RX to RB8
    RPB9Rbits.RPB9R = 2;    //SET RB9 to TX

    U2MODE = 0;         	// disable autobaud, TX and RX enabled only, 8N1, idle=HIGH
    U2STA = 0x1400;     	// enable TX and RX
    U2BRG = Baud2BRG(baud_rate); // U2BRG = (FPb / (16*baud)) - 1
    
    U2MODESET = 0x8000;     // enable UART2
}

/* Configuration for ADC in Auto-Scan Mode
 * Code modified from http://umassamherstm5.org/tech-tutorials/pic32-tutorials/pic32mx220-tutorials/adc
 */
void adcConfigureAutoScan( unsigned adcPINS, unsigned numPins)
{
    AD1CON1 = 0x0000; 	// disable ADC
	ANSELA = 0;			// Don't use AN0, AN1
	ANSELB = 0x000e;	// Use AN3, AN4, AN5
    // AD1CON1<2>, ASAM    : Sampling begins immediately after last conversion completes
    // AD1CON1<7:5>, SSRC  : Internal counter ends sampling and starts conversion (auto convert)
    AD1CON1SET = 0x00e4;
 
    // AD1CON2<1>, BUFM    : Buffer configured as two 8-word buffers, ADC1BUF7-ADC1BUF0, ADC1BUFF-ADCBUF8
    // AD1CON2<10>, CSCNA  : Scan inputs
    AD1CON2 = 0x0402;
 
    // AD2CON2<5:2>, SMPI  : Interrupt flag set at after numPins completed conversions
  	// Also specifies number of locations that will be written in the results buffer (from 1-8 samples in Dual-Mode which is what we're using)
    AD1CON2SET = (numPins-1) << 2;
 
    // AD1CON3<7:0>, ADCS  : TAD = TPB * 2 * (ADCS<7:0> + 1) = 4 * TPB in this example
    // AD1CON3<12:8>, SAMC : Acquisition time = AD1CON3<12:8> * TAD = 15 * TAD in this example
    AD1CON3 = 0x0f01;
 
    // AD1CHS is ignored in scan mode
    AD1CHS = 0;
 
    // select which pins to use for scan mode
    AD1CSSL = adcPINS;
	IPC5bits.AD1IP = 4; // Set Priority 4
	IPC5bits.AD1IS = 0; // Subpriority 0
	IFS0bits.AD1IF = 0; // Clear interrupt flag
	IEC0bits.AD1IE = 1; // Enable ADC interrupt
}

/* Slows down vehicle when entering intersections and some corners, using voltage
 * readings from inductor 3
 */
void IntersectHandler( void )
{
	if( voltage3 > INTERSECT_MINVOLTAGE)	// If passed lower threshold for an intersection
	{
		speed_adjust = 1;					// Force both wheels to have the same duty cycle
		// Apply a linear scaling do decrement both duty cycles
		intersect_adjust = (1 - ((voltage3/(INTERSECT_VOLTAGE*INTERSECT_SCALING))));
	}
	
	// Limit intersect adjust to a range of variables (limits duty cycle to 0-100)
	// in case of a bad voltage reading	
	if( intersect_adjust > 1)
		intersect_adjust = 1;
	if( intersect_adjust < 0)
		intersect_adjust = 0;
}

/*	Stop motors if left and right inductors detect no magnetic field */
void NoSignalPath( void )
{ 
	duty1 = 0;
	duty2 = 0;
	LCDprint("No Signal",2,1);	// Display message
}	

/* Steering algorithm. Adjusts duty cycles of either wheel to steer using voltages
 * from left and right inductors. Calls NoSignalPath() and IntersectHandler() to 
 * make adjustments during intersections/corners and when no signal is detected
 */
void AlignPath ( void )
{
	float speed_adjust;
	
	// Apply exponential scaling to wheel closer to path
	speed_adjust = ( 1 - (pow((fabs(Misalignment)/MAX_MISALIGNMENT),SPEED_SCALING)));
	
	// Check for intersections 
	IntersectHandler();
	
	// If speed_adjust overflows bounds, force within bounds
	if( speed_adjust > 1.0)
		speed_adjust = 1.0;
	if( speed_adjust < 0.0)
		speed_adjust = 0.0;
	
	// If there's no signal, stop vehicle
	if( voltage1<0.003 && voltage2< 0.003)
	{
		NoSignalPath();
	}
	// Left wheel is closer, reduce duty cycle
	else if( (Misalignment - ALIGN_TOLERANCE) > 0.0)
	{
		duty1 = base_duty*speed_adjust*intersect_adjust;
		duty2 = base_duty*intersect_adjust;
	}
	// Right wheel is closer, reduce duty cycle
	else if( (Misalignment + ALIGN_TOLERANCE) < 0.0)
	{
		duty1 = base_duty*intersect_adjust;
		duty2 = base_duty*speed_adjust*intersect_adjust;
	}
	// Aligned, drive straight
	else
	{
		duty1 = base_duty*intersect_adjust;
		duty2 = base_duty*intersect_adjust;
	}
	if( DirectionL == 1 && DirectionR == 1)
		LCDprint("Reversing",2,1);
	if( duty1 != 0 && duty2 != 0 && Turn_L_Flag == 0 && Turn_R_Flag ==0)
		LCDprint("Following Path",2,1);
	IntersectHandler();
}
		
/* Intersection handler when a turn command has been issued. Triggers turn once a
 * voltage threshold from the center intersection inductor has been reached.
 * checks for realignment of the track from the left and righ inductor
 * to exit the turn
 */
void TurnIntersect( void )
{
	// If the interesection has not been reached, keep steering normally
	if( StartTurnFlag == 0)
	{
		AlignPath();
		if( voltage3 > (INTERSECT_VOLTAGE*0.8))
			StartTurnFlag = 1;
	}
	// Intersection detected, turn off wheel corresponding to turn direction to pivot
	else
	{
		if( Turn_L_Flag == 1)
			duty1 = 0;
		else
			duty2 = 0;
		// When left and right wheels align with path, turn is complete, only second alignment
		// is valid, (will start the turn aligned with the path)
		if( (fabs(Misalignment) < (ALIGN_TOLERANCE*3)))
		{
			if(FirstAligned==0)
			{
				FirstAligned =1;
				waitms(750);
			}
			else
			{
				// Left and right inductor are aligned with the path, and both over 
				// a voltage threshold (no signal doesn't satisfy alignment condition)
				if((fabs(Misalignment) < (ALIGN_TOLERANCE*3)) && voltage1 > ALIGN_MINVOLTAGE && voltage2 > ALIGN_MINVOLTAGE)
				{
				// Clear all flags, reset wheel duty cycles
					FirstAligned = 0;
					StartTurnFlag = 0;
					Turn_L_Flag = 0;
					Turn_R_Flag = 0;
					duty1 = base_duty;
					duty2 = base_duty;
				}
			}
		}
	}
}


// Pivots 180 degrees (until it realigns itself with the path in the other direction)
void Turn180 ( void )
{	
	// Upon first call, save movement direction prior to execution, reset wheel speed
	// Make one wheel spin forwards and the other backwards to rotate
	if(Turn180FirstCall==0)
	{
		DirectionLPrev = DirectionL;
		DirectionRPrev = DirectionR;
		Turn180FirstCall=1;
		DirectionL = 1;
		DirectionR = 0;
		duty1 = (base_duty/2);
		duty2 = (base_duty/2);
	}
	
	// Check if left and right wheels has aligned with path, but only the second time 
	// will constitute a complete turn (will begin aligned)
	if( (fabs(Misalignment) < (ALIGN_TOLERANCE*3)))
	{
		if(FirstAligned==0)
		{
			FirstAligned =1;
			waitms(750);
		}
		else
		{
			if((fabs(Misalignment) < (ALIGN_TOLERANCE*3)) && voltage1 > ALIGN_MINVOLTAGE && voltage2 > ALIGN_MINVOLTAGE)
			{
			// Clear all flags and continue to travel in origin direction
				FirstAligned = 0;
				Turn180_Flag = 0;
				Turn180FirstCall = 0;
				DirectionL = DirectionLPrev;
				DirectionR = DirectionRPrev;
			}
		}
	}
}

/* Hierarchy to control movement of the vehicle. Checks flags set by the command
 * receiver to execute movement
 */
void MovementController ( void )
{	
	// Set duty cycles to zero if stop command is issued
	if (Stop_Flag)
	{
		duty1=0;
		duty2=0;
		LCDprint("Stopped",2,1);
	}
	// Check Turn Flags to Issue a Turn Command, will not execute if currently in a 180 turn
	else if( (Turn_R_Flag==1 || Turn_L_Flag==1) && Turn180_Flag==0)
	{
		TurnIntersect();
		if(Turn_R_Flag==1)
			LCDprint("Turn Right CMD",2,1);
		else
			LCDprint("Turn Left CMD",2,1);
	}
	// Turn around if command issued
	else if( Turn180_Flag==1)
	{
		Turn180();
		LCDprint("Turning 180 Deg",2,1);
	}
	else	// No movement commands received or queued, follow path normally
		AlignPath();
}

/*	Parses bits received and read in Timer1 to set flags to control command execution */
void CommandHandler( void )
{
	// If transmitter bits are valid, then parse
	if( buffer_valid_flag==1) {
		Command = buffer.byte;	// Move buffer into char command
		buffer_valid_flag = 0;	// Reset valid flag
	}
	// Not valid, transmission ignored
	else
		Command = NullCommand;
	
	if( Command == TurnLeft)	// Turn left command received
		Turn_L_Flag =1;
	else if( Command == TurnRight)	// Turn right command received
		Turn_R_Flag =1;
	else if( Command == StopCommand) // Stop command received, if already stopped then clear flag
		Stop_Flag =(Stop_Flag==1)?0:1;
	else if( Command == ReverseCommand)	// Reverse direction command received
	{
		DirectionL = (DirectionL==1)?0:1;
		DirectionR = (DirectionR==1)?0:1;
	}
	else if( Command == Turn180Command)	// Turn 180 command received
		Turn180_Flag = 1;
	else if  (Command == Speed_Up)		// Accelerate command received
		base_duty = ((base_duty==100)?100:(base_duty+10)); // Increment base duty by 10 (max of 100)
	else if (Command==Speed_Down)		// Deccelerate command received
		base_duty = ((base_duty==0)?0:(base_duty-10)); // Decrement base duty by 10 (min of 0)
	else								// Command received was not recognized, ignored
		Command = NullCommand;
}
 
void PinConfigure(void)
{
	// Output pins to drive H-bridges
	TRISBbits.TRISB12 = 0; // Pins RB12,RB13 controls left wheel
  	TRISBbits.TRISB13 = 0;
  	TRISBbits.TRISB14 = 0; // Pins RB14,RB15 controls right wheel
  	TRISBbits.TRISB15 = 0;
	
	TRISBbits.TRISB0 = 0;	// SOUND_OUT 
	TRISAbits.TRISA0 = 0;	// AMBER_R
	TRISAbits.TRISA1 = 0;	// AMBER_L
	SOUND_OUT = 0;	
	AMBER_R = 1;   
	AMBER_L = 1; 
}

// Performs all ISR and non-ISR configurations
void ConfigureAll( void )
{
	CFGCON = 0;				 // Enables writing to control registers
	PinConfigure();			 // Configure input and output pins
    UART2Configure(115200);  // Configure UART2 for a baud rate of 115200
 	
	StartBitTriggerConfig(); // Configure External Interrupt 1 for command receive detection
	INTCONbits.MVEC = 1;	 // Enable multi-vector interrupts
	
	Timer1Configure();		 // Configure Timer 1 to read command transmission
	Timer2Configure();		 // Configure Timer 2 for PWM and turn signals
	Timer3Configure();	     // Configure Timer 3 for buzzer
	
	LCD_4BIT();				 // Configure LCD
	adcConfigureAutoScan( 0x0038, 3); // Using pins RB1,RB2,RB3 as ADC inputs
	AD1CON1SET = 0x8000;              // Start ADC
	__builtin_enable_interrupts();
}

// Calculates voltages of each inductor and the misalignment of the left and right inductors
void CalculateVolts ( void )
{
	voltage1=an1*VREF/1023.0; 			// conversions from ADC inputs to voltages
	voltage2=an2*VREF/1023.0;
	voltage3=an3*VREF/1023.0;
	
	Misalignment=(voltage1-voltage2);	// Used for alignment and turn calculations
}

void main(void)
{
	// Buffer to hold strings for printing to LCD
	char LCDstring[17];
	
	ConfigureAll();	
	while(1)
	{	
		CalculateVolts();	// Voltage conversions from ADC readings
		CommandHandler();	// Parses received transmission bits from transmiter into commands
		MovementController(); // Execute commands/movement
		
		printf("Command = %c\r\n", Command);	// Prints received characters to serial
		// Prints inductor voltages and duty cycles to serial
		printf("V1:%.3f V2:%.3f V3:%.3f Duty1:%d Duty2: %d\r\n", voltage1, voltage2, voltage3, duty1,duty2);
		sprintf(LCDstring, "V1:%.3f V2:%.3f", voltage1, voltage2);	
		LCDprint(LCDstring,1,1);	// Prints left and right inductor voltages to LCD
	}
}

    