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

#define H11_PIN LATBbits.LATB15
#define H12_PIN LATBbits.LATB14
#define H21_PIN LATBbits.LATB13
#define H22_PIN LATBbits.LATB12


volatile unsigned char pwm_count;
volatile unsigned char direction=0;
volatile unsigned char base_duty = 50, duty1 = 50, duty2 = 50;
volatile int 	an1;
volatile int 	an2;
volatile int 	an3;
volatile float  voltage1;
volatile float  voltage2;
volatile float	voltage3;

void UART2Configure(int baud_rate)
{
    // Peripheral Pin Select
    U2RXRbits.U2RXR = 4;    //SET RX to RB8
    RPB9Rbits.RPB9R = 2;    //SET RB9 to TX

    U2MODE = 0;         // disable autobaud, TX and RX enabled only, 8N1, idle=HIGH
    U2STA = 0x1400;     // enable TX and RX
    U2BRG = Baud2BRG(baud_rate); // U2BRG = (FPb / (16*baud)) - 1
    
    U2MODESET = 0x8000;     // enable UART2
}

// Good information about ADC in PIC32 found here:
// http://umassamherstm5.org/tech-tutorials/pic32-tutorials/pic32mx220-tutorials/adc
void ADCConf(void)
{
    AD1CON1CLR = 0x8000;    // disable ADC before configuration
    AD1CON1 = 0x00E0;       // internal counter ends sampling and starts conversion (auto-convert), manual sample
    AD1CON2 = 0;            // AD1CON2<15:13> set voltage reference to pins AVSS/AVDD
    AD1CON3 = 0x0f01;       // TAD = 4*TPB, acquisition time = 15*TAD 
    AD1CON1SET=0x8000;      // Enable ADC
}

// Interrupt Service Routine for Timer2 which has Interrupt Vector 8 and initalized with priority level 3
void __ISR(_TIMER_2_VECTOR, IPL7AUTO) Timer2_ISR(void)
{
	LATBbits.LATB0 = !LATBbits.LATB0;
	
	pwm_count++;
	
	if(pwm_count==100)
		pwm_count = 0;
	
	if(pwm_count < duty1) {
		if(direction==0)
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
		if(direction==0)
		{
		H21_PIN = 0;
		H22_PIN = 1;
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
 			
	if( AD1CON2bits.BUFS == 1)	 // check which buffers are being written to and read from the other set
	{    
		an1 = ADC1BUF0;								// AD1CON2bits.BUFS==1 corresponds to ADC1BUF0-7
		an2 = ADC1BUF1;
		an3 = ADC1BUF2;
	}
	else
	{														// AD1CON2bits.BUFS==0 corresponds to ADC1BUF8-F
   		an1 = ADC1BUF8;	
		an2 = ADC1BUF9;
		an3 = ADC1BUFA;
	}
	AD1CON1bits.ASAM = 1;           // restart automatic sampling
	IFS0CLR = 0x10000000;           // clear ADC interrupt flag	
      
}

// Configuration for ADC in Auto-Scan Mode
// Code from http://umassamherstm5.org/tech-tutorials/pic32-tutorials/pic32mx220-tutorials/adc
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
	IPC5bits.AD1IP = 6; // Priority 6
	IPC5bits.AD1IS = 0;
	IFS0bits.AD1IF = 0; // Clear interrupt flag
	IEC0bits.AD1IE = 1; // Enable ADC interrupt
}


// Function to adjust duty cycles in order to realign the cart to drive 'straight'
// The voltages from the inductors are read from main and determines the misalignmnet of the wheels (the degree of turn in the track)
// The speed of the wheels are adjusted dynamically to correct the misalignment, speed adjustment is currently a linear function
// of the misalignment.
// Duty1 controls the pwm of the wheels on the left side of the car, duty2 controls right side
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
  float difference = voltage1 - voltage2; // Max difference in amplitude is +/- 2V
  float speed_adjust;
  
  // Scale speed adjust depending on the difference in amplitude. An absolute difference of 2V indicates maximum turn
  // In that case the car should simply rotate (one wheel completely turned off). 2V difference, speed adjust = 0%
  // 0V difference, speed adjust = 100% (nothing happens) 
  speed_adjust = (1-(0.5*fabs(difference)));
    
  if( difference-0.01 > 0) // Voltage1 is higher, line is closer to left side of car, turn left by slowing down the left wheel
  {
    duty1 = base_duty*speed_adjust;
    duty2 = base_duty;
  }
  else if (difference+0.01 < 0) // Voltage2 is higher, line is closer to right side of car, turn right by slowing down the right wheel
  {
    duty2 = base_duty*speed_adjust;
    duty1 = base_duty;
  }
  else {										// More or less alignment, keep duty cycles the same
    duty1 = base_duty;
  	duty2 = base_duty;
  }
}

void main(void)
{
	volatile unsigned long t=0;
    int adcval;
    float voltage;
	char LCDstring[17];

	TRISBbits.TRISB12 = 0;
  	TRISBbits.TRISB13 = 0;
  	TRISBbits.TRISB14 = 0;
  	TRISBbits.TRISB15 = 0;
	
	TRISBbits.TRISB0 = 0;		// DEBUG PIN
	LATBbits.LATB0 = 0;

	CFGCON = 0;
    UART2Configure(115200);  // Configure UART2 for a baud rate of 115200

    
	INTCONbits.MVEC = 1;
  	__builtin_enable_interrupts();
	Timer2Configure();
	LCD_4BIT();
	adcConfigureAutoScan( 0x000E, 3); // Bitwise select of which pins to use as analog input (choice of AN0-AN15, though I can't locate AN6-8 or 13-15 :/) 
	AD1CON1SET = 0x8000;              // start ADC
	
	while(1)
	{	
		voltage1=an1*VREF/1023.0; 		// conversions from adc inputs to voltage
		voltage2=an2*VREF/1023.0;
		voltage3=an3*VREF/1023.0;
		AlignPathDynamic();
		printf("Voltages: %.3f, %.3f, %.3f\r\n", voltage1, voltage2, (voltage1-voltage2));
	}
}
