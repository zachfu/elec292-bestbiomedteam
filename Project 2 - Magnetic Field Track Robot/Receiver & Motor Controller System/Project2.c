#include <XC.h>
#include <sys/attribs.h>
#include <stdio.h>
#include <stdlib.h> 
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

int ADCRead(char analogPIN)
{
    AD1CHS = analogPIN << 16;    // AD1CHS<16:19> controls which analog pin goes to the ADC
 
    AD1CON1bits.SAMP = 1;        // Begin sampling
    while(AD1CON1bits.SAMP);     // wait until acquisition is done
    while(!AD1CON1bits.DONE);    // wait until conversion done
 
    return ADC1BUF0;             // result stored in ADC1BUF0
}

// Interrupt Service Routine for Timer2 which has Interrupt Vector 8 and initalized with priority level 3
void __ISR(8, IPL3SOFT) Timer2_Counter(void)
{
  LATBbits.LATB0 = !LATBbits.LATB0;
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
	IPC2bits.T2IP = 3;
	IPC2bits.T2IS = 0;
	IFS0bits.T2IF = 0;
	IEC0bits.T2IE = 1;
}

void main(void)
{
	volatile unsigned long t=0;
    int adcval;
    float voltage;
	char LCDstring[17];
	TRISBbits.TRISB0 = 0;
	TRISBbits.TRISB4 = 0;
	TRISAbits.TRISA4 = 0;
	LATBbits.LATB4 = 1;
	LATAbits.LATA4 = 1;
	LATBbits.LATB0 = 0;

	CFGCON = 0;
    UART2Configure(115200);  // Configure UART2 for a baud rate of 115200

    // Configure pins as analog inputs
    ANSELBbits.ANSB3 = 1;   // set RB3 (AN5, pin 7 of DIP28) as analog pin
    TRISBbits.TRISB3 = 1;   // set RB3 as an input
    
	INTCONbits.MVEC = 1;
  	__builtin_enable_interrupts();
    ADCConf(); // Configure ADC
	Timer2Configure();
	LCD_4BIT();

    printf("*** PIC32 ADC test ***\r\n");
	while(1)
	{	
		t++;
		if(t==500000)
		{
        	adcval = ADCRead(5); // note that we call pin AN5 (RB3) by it's analog number
        	voltage=adcval*3.265/1023.0;
        	printf("AN5=0x%04x, %.3fV\r", adcval, voltage);
			fflush(stdout);
			sprintf(LCDstring, "AN5=0x%04x, %.3fV\r", adcval, voltage);
			waitms(20);
			LCDprint(LCDstring, 1, 1);
			LCDprint(LCDstring, 2, 1);
			t = 0;
		}
	}
}
