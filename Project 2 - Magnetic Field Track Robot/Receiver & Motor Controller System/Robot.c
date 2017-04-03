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

volatile char 			Command=NullCommand;
volatile int 			an1;
volatile int 			an2;
volatile int 			an3;

volatile int			StartTurn = 0;
volatile int			TurnFirstPassFlag = 0;
volatile int			StoppedFlag = 0;
volatile int			ReverseFlag = 0;

volatile int			TurnCmdFlag = 0;
volatile int			Turn180CmdFlag = 0;		

volatile float 			voltage1;
volatile float  		voltage2;
volatile float			voltage3;
volatile float 			Misalignment;
volatile float  		speed_adjust;
volatile float			intersect_adjust;

/* UART2Configure() sets up the UART2 for the most standard and minimal operation
 *  Enable TX and RX lines, 8 data bits, no parity, 1 stop bit, idle when HIGH
 *
 * Input: Desired Baud Rate
 * Output: Actual Baud Rate from baud control register U2BRG after assignment*/
void UART2Configure( int desired_baud)
{
	
	
	//U2RXRbits.U2RXR = 4;    //SET RX to RB8
    //RPB9Rbits.RPB9R = 2;    //SET RB9 to TX

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


void __ISR(_UART_2_VECTOR, IPL2AUTO) IntUart2Handler(void)
  {
  unsigned char t;
  	
  	if (IFS1bits.U2RXIF)
  	{
  		t = 0;
		while(!U2STAbits.URXDA)
		{
			waitms(1);
			t++;
			if(t > 110)
			{
				IFS1CLR=_IFS1_U2RXIF_MASK;
				return;
			}
		}
		
		Command = U2RXREG;
		IFS1CLR=_IFS1_U2RXIF_MASK;
	}
    if ( IFS1bits.U2TXIF)
      {
        IFS1bits.U2TXIF = 0;
      }
  }

// Interrupt Service Routine for Timer2 which has Interrupt Vector 8 and initalized with priority level 3
void __ISR(_TIMER_2_VECTOR, IPL7AUTO) Timer2_ISR(void)
{	
	if( Misalignment > 0)
		U2RXRbits.U2RXR = 0;    //SET RX to RPA1 
	else if( Misalignment < 0)
		U2RXRbits.U2RXR = 4;    //Set RX to RPB8
	
	pwm_count++;
	
	if(pwm_count==100)
		pwm_count = 0;
	
	if(pwm_count < duty1) {
		if(!ReverseFlag) // change later to char corresponding to a direction change command
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
		if(!ReverseFlag)
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
	IPC2bits.T2IP = 7;	// Top priority
	IPC2bits.T2IS = 0; 
	IFS0bits.T2IF = 0;
	IEC0bits.T2IE = 1;
}
	
void __ISR(_ADC_VECTOR, IPL6AUTO) ADC_ISR(void)
{
	LATBbits.LATB0 = !LATBbits.LATB0;
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
	IPC5bits.AD1IP = 6; // Set Priority 6
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
	// Linear scaling of speed when approaching an intersection down to a min of 50% duty
	if( Command != TurnLeft || Command != TurnRight)
		intersect_adjust = (1-(voltage3/(IntersectDetectVoltageMax*2)));
	// If turn command has been issued apply a exponential scaling down to a min of 20% duty
	else
		intersect_adjust = (1-pow((voltage3/(IntersectDetectVoltageMax*1.75)),0.5));
 
 	// If there's an intersect approaching, drive straight 
 	if( voltage3 > IntersectDetectVoltageLow)
 		speed_adjust = 1;
}

// If there is no signal in the path, then stop the motors
void NoSignalPath( void )
{ 
	if( voltage1<0.001 && voltage2< 0.001)
	{
		duty1 = 0;
		duty2 = 0;
	}
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
void AlignPathDynamic(void)
{
  // Scale speed adjust depending on the difference in amplitude. An absolute difference of 1.6V indicates maximum turn
  // In that case the car pivots (one wheel completely turned off). 1.6V difference, speed adjust = 0%
  // 0V difference, speed adjust = 100% (nothing happens) 
  // Turn_Scaling_Factor adjusts the degree of curve which controls the steering, with a higher
  // scaling factor increasing the initial slope
  speed_adjust = (1-((pow((fabs(Misalignment)/Max_Misalignment), Turn_Scaling_Factor))));
  NoSignalPath();
  IntersectHandler();
  
  // Prevent speed_adjust from being greater than 1 or less than 0
  if( speed_adjust > 1 )
  	speed_adjust = 1;
  if( speed_adjust < 0)
  	speed_adjust = 0;
  
  if( Misalignment-AlignTolerance > 0) 		// Voltage1 is higher, line is closer to left side of car, turn left by slowing down the left wheel
  {
    duty1 = base_duty*intersect_adjust*speed_adjust;
    duty2 = base_duty*intersect_adjust;
  }
  else if (Misalignment+AlignTolerance < 0)	// Voltage2 is higher, line is closer to right side of car, turn right by slowing down the right wheel
  {
    duty2 = base_duty*intersect_adjust*speed_adjust;
    duty1 = base_duty*intersect_adjust;
  }
  else {									// Else aligned, drive straight
    duty1 = base_duty;
  	duty2 = base_duty;
  }
}
		
// Checks for intersections in the track and depending on any commands from the transmitter system
// either ignores the intersection, turns left or turns right. Priority is higher than generic
// realignment function. Checks voltage of inductor 3 to see if there is some form of intersection.
// Check if voltage3>threshold (threshold determined through testing to see what constitutes an arbitrarily
// large intersection. Then pivots on the wheel corresponding to the turn direction until
// the wheels align with the new path 
void DetectIntersection( void )
{
  	// Check if vehicle has arrived near 'center' of the intersection
  	if( !StartTurn)
    {
  		if( voltage3 > (IntersectCrossVoltage*0.8)) // Slightly prior to intersect cross (with some error margin)
    		StartTurn = 1;
    	AlignPathDynamic();		// Continue to follow the path until we've reached the intersection cross
    }
  	// Once vehicle has reached centre of intersection, begin turning
  	else
    {
      if( Command == TurnLeft )	
      	duty1 = 0;
      else
      	duty2 = 0;
      	
      // Check if vehicle has aligned with new path,
      // once it has clear all turn commands and proceed forward
      if( (0 <= (Misalignment+AlignTolerance)) && ((Misalignment+AlignTolerance) <= (AlignTolerance*2)))	
  	  {
  	  	if( TurnFirstPassFlag)	
  	  	{
  	  		TurnFirstPassFlag = 1;
  	  		waitms(500);
  	  	}
  	  	else
  	  	{
    		duty1 = base_duty;				// Set wheel speeds back to default values
  			duty2 = base_duty;			
  			StartTurn = 0;					// Turn off the StartTurn 'flag' for future function calls
     		Command = NullCommand;			// Clear command, resume default function
     		TurnFirstPassFlag = 0;			// Clear flag
     		TurnCmdFlag = 0;				// Clear flag
     	}
      }
    }
}

// If the stop command has been transmitted, sets the duty cycle of both wheels to 0, then pauses until stop has been issued again
void StopMovement (void)
{
	if( !StoppedFlag)
	{
  		duty1 = 0;
  		duty2 = 0;
  		StoppedFlag = 1;
  	}
  	else
  	{
  		StoppedFlag = 0;
  		duty1 = base_duty;
  		duty2 = base_duty;
  	}
}

// Pivots 180 degrees (until it realigns itself with the path in the other direction)
void Turn180 (void)
{
  	if( !StartTurn)
 	{
	  	duty1 = 0;
    	StartTurn = 1;
    	Turn180CmdFlag = 1; // Hold the command until it has been completed
 	}
  	else
  	{
  		if( (0 <= (Misalignment+AlignTolerance)) && ((Misalignment+AlignTolerance)<= (AlignTolerance*2)))	
  		{
  	  		if( !TurnFirstPassFlag)
  	  		{
  	  			TurnFirstPassFlag = 1;
  	  			waitms(750); //????????????????
  	  		}
  	  		else
  	  		{
  	  			TurnFirstPassFlag = 0;
    			duty1 = base_duty;			// Set wheel speeds back to default values			
    			Command = NullCommand;		// Clear command, resume default function
   				StartTurn = 0; 				// Clear 'flag'
   				Turn180CmdFlag = 0;			
   			}
  		}
  	}
}

// Hierarchy to control movement of the vehicle. The received movement command from the UART
// determines what is executed
void MovementController(void)
{
	char LCDString[17];
	
  	if( Command == NullCommand && !StoppedFlag)
  	{
  		AlignPathDynamic();
  		LCDprint("Steering...",2,1);
  	}
  	else
	{
  		if( Command == StopCommand)
  		{
    		StopMovement();
    		if( StoppedFlag)
    			LCDprint("Stopped",2,1);
    	}
  		else if( Command == TurnLeft || Command == TurnRight || TurnCmdFlag)
  		{
  			if(!TurnCmdFlag)
  				TurnCmdFlag = 1;
     	 	DetectIntersection();
     	 	LCDprint("Turn Intersect",2,1);
     	}
   		else if( Command == Turn180Command || Turn180CmdFlag)
   		{
      		Turn180();
      		LCDprint("Spinning...",2,1);
      	}
      	else if( (0 <= Command) && (Command <= 100))
      	{
      		base_duty = Command;
     		sprintf(LCDString,"Speed Set To %d", Command);
      		LCDprint(LCDString,2,1);
      	}
      	else if( Command == Reverse )
      	{
      		ReverseFlag != ReverseFlag;
      		LCDprint("Reverse CMD",2,1);
      	}
    	else 
    		Command = NullCommand;
    }
}  
void PinConfigure(void)
{
	TRISBbits.TRISB12 = 0; // Outputs to drive H-bridges
  	TRISBbits.TRISB13 = 0;
  	TRISBbits.TRISB14 = 0;
  	TRISBbits.TRISB15 = 0;
	
}

// Performs all ISR and non-ISR configurations
void ConfigureAll( void )
{
	CFGCON = 0;
	PinConfigure();
    UART2Configure(100);  // Configure UART2 for a baud rate of 100
 	
    
	INTCONbits.MVEC = 1;
  	__builtin_enable_interrupts();
	Timer2Configure();
	LCD_4BIT();
	adcConfigureAutoScan( 0x000D, 3); // Select A0, A2, A3 as analog inputs
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
		MovementController();
		
		sprintf(LCDstring, "V1:%.3f V2:%.3f", voltage1, voltage2);
		LCDprint(LCDstring,1,1);
	}
}
