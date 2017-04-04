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

volatile char 			Command;
volatile int 			an1;
volatile int 			an2;
volatile int 			an3;

volatile char 			StartTurnFlag=0;
volatile char 			Turn180_Flag=0;
volatile char 			Turn_L_Flag=0;
volatile char 			Turn_R_Flag=0;
volatile char 			Turn180FirstCall=0;
volatile char 			Stop_Flag = 0;
volatile char 			FirstAligned = 0;
volatile char 			DirectionL = 0;
volatile char 			DirectionLPrev = 0;
volatile char 			DirectionR = 0;
volatile char 			DirectionRPrev = 0;	

volatile float 			voltage1;
volatile float  		voltage2;
volatile float			voltage3;
volatile float 			Misalignment;
volatile float  		speed_adjust;
volatile float			intersect_adjust;

void StartBitTriggerConfig(void)
{
	IEC0bits.INT1IE = 0;	// Disable external interrupt 1
	INTCONbits.INT1EP = 0;	// Set interrupt condition to falling-edge
	IPC1bits.INT1IP = 7;
	IPC1bits.INT1IS = 0;
	IFS0bits.INT1IF = 0;	// Clear interrupt flag
	IEC0bits.INT1IE = 1;	// Enable external interrupt 1
	INT1R = 3;				// Use Pin A0 for interrupt
	TRISBbits.TRISB10 = 1;
}

void __ISR(_EXTERNAL_1_VECTOR, IPL7AUTO) StartBitTrigger(void)
{
	LATAbits.LATA1 = !LATAbits.LATA1;
	IFS0bits.INT1IF = 0;
}

// Interrupt Service Routine for Timer2 which has Interrupt Vector 8 and initalized with priority level 3
void __ISR(_TIMER_2_VECTOR, IPL6AUTO) Timer2_ISR(void)
{	
	pwm_count++;
	
	if(pwm_count==100)
		pwm_count = 0;
	
	if(pwm_count < duty1) {
		if(!DirectionL) // Direction = 0, Forward
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

// Configures Timer 1 for use in receiving character bits
void Timer1Configure (void)
{
	PR1 = (SYSCLK/(FREQ))-1;
	TMR1 = 0;
	T1CONbits.TCKPS = 0; // Pre-scaler 1:1
	T1CONbits.TCS = 0;	// Clock source
	IPC1bits.T1IP = 7;	// Top priority
	IPC1bits.T1IS = 0; 
	IFS0bits.T1IF = 0;	// Clear timer flag
	IEC0bits.T1IE = 0;	// No interrupts
}
// Enables 16bit Timer2 Interrupts, loads Timer2 Period Register and Starts the Timer
// When Timer2 Interrupts occur, the software must clear the interrupt status flag
void Timer2Configure (void)
{
	// Timer2 Interrupt Inialization from Example 16-8 of Family Reference Manual
	PR2 =(SYSCLK/(FREQ))-1; // since SYSCLK/FREQ = PS*(PR1+1)
	TMR2 = 0;
	T2CONbits.TCKPS = 0; // Pre-scaler 1:1
	T2CONbits.TCS = 0; // Clock source
	T2CONbits.ON = 1;
	IPC2bits.T2IP = 5;	// Second priority
	IPC2bits.T2IS = 0; 
	IFS0bits.T2IF = 0;
	IEC0bits.T2IE = 1;
}

void __ISR(_ADC_VECTOR, IPL5AUTO) ADC_ISR(void)
{
	AD1CON1bits.ASAM = 0;           // stop automatic sampling (essentially shut down ADC in this mode) while reading from buffers
 			
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
 * Input: Desired Baud Rate
 * Output: Actual Baud Rate from baud control register U2BRG after assignment*/
void UART2Configure( int desired_baud)
{
	
	
	U2RXRbits.U2RXR = 4;    //SET RX to RB8
    RPB9Rbits.RPB9R = 2;    //SET RB9 to TX

	U2MODE = 0;         // disable autobaud, TX and RX enabled only, 8N1, idle=HIGH
    U2STA = 0x1400;     // enable TX and RX
    U2BRG = Baud2BRG(desired_baud); // U2BRG = (FPb / (16*baud)) - 1
    
    //UART Rx INTERRUPT CONFIGURATION
    IFS1bits.U2RXIF = 0; //clear the receiving interrupt Flag
    IFS1bits.U2TXIF = 0; //clear the transmitting interrupt flag
	
    IEC1bits.U2RXIE = 1;  //enable Rx interrupt
  	//IEC1bits.U2TXIE = 1;  //Enable Tx interrupt	-- theoretically we dont need this?
    IEC1bits.U2EIE = 1;
    IPC9bits.U2IP = 2; //priority level
    IPC9bits.U2IS = 0; //sub priority level
    INTCONbits.MVEC = 1;
    __builtin_enable_interrupts();
    U2MODESET = 0x8000;     // enable UART2
}

// Configuration for ADC in Auto-Scan Mode
// Code modiefied from http://umassamherstm5.org/tech-tutorials/pic32-tutorials/pic32mx220-tutorials/adc
void adcConfigureAutoScan( unsigned adcPINS, unsigned numPins)
{
    AD1CON1 = 0x0000; // disable ADC
 
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
	IPC5bits.AD1IP = 5; // Set Priority 5
	IPC5bits.AD1IS = 0; 
	IFS0bits.AD1IF = 0; // Clear interrupt flag
	IEC0bits.AD1IE = 1; // Enable ADC interrupt
}

// Uses the changes in voltage of inductor 3 to detect when a sharp corner is upcoming
// Then tries to slow the duty cycles of the vehicle to account for the corner
// Voltage3 approach approximately 1.25V as it reaches the closest point 
// to the corner

void IntersectHandler( void )
{
	// If no turn command issued, apply linear scaling to slow car when approaching intersect
	if( !Turn_L_Flag && !Turn_R_Flag)
		intersect_adjust = (1 - ((voltage3/(INTERSECT_VOLTAGE*2))));
	else 
	// Else apply a harder exponential scaling down to a min of 20% base duty
		intersect_adjust = (1 - (pow(((voltage3/(INTERSECT_VOLTAGE)*1.75)),INTERSECT_SCALING)));
	
	// As you approach the intersection, go straight
	if( voltage3 > INTERSECT_MINVOLTAGE)
		speed_adjust = 1;
}

// If there is no signal in the path, then stop the motors
void NoSignalPath( void )
{ 
	duty1 = 0;
	duty2 = 0;
}	
// Adjusts duty cycles to realign vehicle with the path. 
// Takes the voltage difference in inductors 1 and 2 then scales down the speed of the wheel
// closest to the wire to steer in that direction. Models the scaling after 1-x^(1/n)
// where n is the scaling factor.
/*                  __..-======-------..__
              . '    ______    ___________`.
            .' .--. '.-----.`. `.-----.-----`.
           / .'   | ||      `.` \\     \     \\            _
         .' /     | ||        \\ \\_____\_____\\__________[_]
        /   `-----' |'---------`\  .'                       \
       /============|============\'-------------------.._____|
    .-`---.         |-==.        |'.__________________  =====|-._
  .'        `.      |            |      .--------.    _` ====|  _ .
 /     __     \     |            |   .'           `. [_] `.==| [_] \
[   .`    `.  |     |            | .'     .---.     \      \=|     |
|  | / .-. '  |_____\___________/_/     .'---. `.    |     | |     |
 `-'| | O |'..`------------------'.....'/ .-. \ |    |       ___.--'
     \ `-' / /   `._.'                 | | O | |'___...----''___.--'
      `._.'.'                           \ `-' / [___...----''_.'
                                         `._.'.' */
// vroom 
void AlignPath ( void )
{
	float speed_adjust;
	
	// Apply exponential scaling to wheel closer to path, corresponding to 1 - x^(1/n)
	speed_adjust = ( 1 - (pow((fabs(Misalignment)/MAX_MISALIGNMENT),SPEED_SCALING)));
	
	// Check for intersections or if the signal has disappeared
	IntersectHandler();

	
	// If speed_adjust overflows bounds, force within bounds
	if( speed_adjust > 1.0)
		speed_adjust = 1.0;
	if( speed_adjust < 0.0)
		speed_adjust = 0.0;
	
	// If Left wheel is closer to path, slow down left wheel
	if( voltage1<0.001 && voltage2< 0.001)
	{
		NoSignalPath();
	}
	else if( (Misalignment - ALIGN_TOLERANCE) > 0.0)
	{
		duty1 = base_duty*speed_adjust*intersect_adjust;
		duty2 = base_duty*intersect_adjust;
	}
	// If Right wheel is closer to path, slow down right wheel
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
}
		
// Checks for intersections in the track and depending on any commands from the transmitter system
// either ignores the intersection, turns left or turns right. Priority is higher than generic
// realignment function. Checks voltage of inductor 3 to see if there is some form of intersection.
// Check if voltage3>threshold (threshold determined through testing to see what constitutes an arbitrarily
// large intersection. Then pivots on the wheel corresponding to the turn direction until
// the wheels align with the new path 
void TurnIntersect( void )
{
	// If the interesection has not been reached, keep steering normally
	if( !StartTurnFlag )
	{
		AlignPath();
		if( voltage3 > INTERSECT_VOLTAGE)
			StartTurnFlag = 1;
	}
	// Intersection detected, turn off wheel corresponding to turn direction
	else
	{
		if( Turn_L_Flag)
			duty1 = 0;
		else
			duty2 = 0;
		// When left and right wheels align with path, turn is complete, only second alignment
		// is valid, (will start the turn aligned)
		if( fabs(Misalignment) < ALIGN_TOLERANCE*2)
		{
			if(!FirstAligned)
			{
				FirstAligned =1;
				waitms(500);
			}
			else
			{
				// Clear all flags, reset wheels speeds
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


// Pivots 180 degrees (until it realigns itself with the path in the other direction)
void Turn180 ( void )
{	
	// Upon first call, save movement direction prior to execution, reset wheel speed
	// Make one wheel spin forwards and the other backwards to rotate
	if(!Turn180FirstCall)
	{
		DirectionLPrev = DirectionL;
		DirectionRPrev = DirectionR;
		Turn180FirstCall=1;
		DirectionL = 1;
		DirectionR = 0;
		duty1 = base_duty;
		duty2 = base_duty;
	}
	
	// Check if left and right wheels has aligned with path, but only the second time 
	// will constitute a complete turn (will begin aligned)
	if( fabs(Misalignment) < ALIGN_TOLERANCE*2)
	{
		if(!FirstAligned)
		{
			FirstAligned =1;
			waitms(500);
		}
		else
		{
			// Clear all flags and reset directions
			FirstAligned = 0;
			Turn180_Flag = 0;
			Turn180FirstCall = 0;
			DirectionL = DirectionLPrev;
			DirectionR = DirectionRPrev;
		}
	}
}

// Hierarchy to control movement of the vehicle. Checks flags set by the UART receive
// to call specific movement commands
void MovementController ( void )
{	
	if (Stop_Flag)
	{
		duty1=0;
		duty2=0;
		LCDprint("Stopped",2,1);
	}
	// Check Turn Flags to Issue a Turn Command, will not execute if currently in a 180 turn
	else if( (Turn_R_Flag || Turn_L_Flag) && !Turn180_Flag)
	{
		TurnIntersect();
		if(Turn_R_Flag)
			LCDprint("Turn Right CMD",2,1);
		else
			LCDprint("Turn Left CMD",2,1);
	}
	else if( Turn180_Flag)
	{
		Turn180();
		LCDprint("Turning 180 Deg",2,1);
	}
	else
	{
		AlignPath();
		LCDprint("Following Path",2,1);
	}
}

// Takes commands received by the UART and sets flags used by the Movement Controller
void CommandHandler( void )
{
	if( Command == TurnLeft)
		Turn_L_Flag =1;
	else if( Command == TurnRight)
		Turn_R_Flag =1;
	else if( Command == StopCommand)
		Stop_Flag != Stop_Flag;
	else if( Command == ReverseCommand)
	{
		DirectionL != DirectionL;
		DirectionR != DirectionR;
	}
	else
		Command == NullCommand;
}
 
void PinConfigure(void)
{
	TRISBbits.TRISB12 = 0; // Outputs to drive H-bridges
  	TRISBbits.TRISB13 = 0;
  	TRISBbits.TRISB14 = 0;
  	TRISBbits.TRISB15 = 0;
	TRISAbits.TRISA1 = 0;
	LATAbits.LATA1 = 1;
}

// Performs all ISR and non-ISR configurations
void ConfigureAll( void )
{
	CFGCON = 0;
	PinConfigure();
    UART2Configure(115200);  // Configure UART2 for a baud rate of 100
 	
    StartBitTriggerConfig();
	INTCONbits.MVEC = 1;
  	__builtin_enable_interrupts();
	Timer1Configure();
	Timer2Configure();
	LCD_4BIT();
	adcConfigureAutoScan( 0x0038, 3); // Using pins RB1,RB2,RB3 as ADC inputs
	AD1CON1SET = 0x8000;              // start ADC
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
	char LCDstring[17];
	
	ConfigureAll();
	
	while(1)
	{	
		CalculateVolts();
		CommandHandler();
		MovementController();
		
		sprintf(LCDstring, "V1:%.3f V2:%.3f", voltage1, voltage2);
		LCDprint(LCDstring,1,1);
	}
}
