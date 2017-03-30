#include <XC.h>
#include <string.h>
#include <sys/attribs.h>
 
// Configuration Bits (somehow XC32 takes care of this)
#pragma config FNOSC = FRCPLL       // Internal Fast RC oscillator (8 MHz) w/ PLL
#pragma config FPLLIDIV = DIV_2     // Divide FRC before PLL (now 4 MHz)
#pragma config FPLLMUL = MUL_20     // PLL Multiply (now 80 MHz)
#pragma config FPLLODIV = DIV_2     // Divide After PLL (now 40 MHz)
 
                                   // see figure 8.1 in datasheet for more info
#pragma config FWDTEN = OFF         // Watchdog Timer Disabled
#pragma config FPBDIV = DIV_1       // PBCLK = SYCLK

// Defines
#define SYSCLK 40000000L
#define Baud2BRG(desired_baud)      ( (SYSCLK / (16*desired_baud))-1)


volatile char c;
volatile char flag=0;
 
// Function Prototypes
unsigned int SerialReceive(char *buffer, unsigned int max_size);
int UART2Configure( int baud);

void __ISR(_UART_2_VECTOR, IPL2AUTO) IntUart2Handler(void)
  {
  	flag=1;
  	if (IFS1bits.U2RXIF)
  		c = U2RXREG;
  	IFS1CLR=_IFS1_U2RXIF_MASK;
    if ( IFS1bits.U2TXIF)
      {
        IFS1bits.U2TXIF = 0;
      }
  }

void main(void)
{

	CFGCON = 0;
 
    // Peripheral Pin Select
    U2RXRbits.U2RXR = 4;    //SET RX to RB8
    RPB9Rbits.RPB9R = 2;    //SET RB9 to TX
 
    UART2Configure(115200);  // Configure UART2 for a baud rate of 115200
 	
    while(1)
    {
    	if ( flag==1)
    	{
    		printf("this char is :%c\r\n", c);
    		flag=0;
    	}   
    }
}
 
/* UART2Configure() sets up the UART2 for the most standard and minimal operation
 *  Enable TX and RX lines, 8 data bits, no parity, 1 stop bit, idle when HIGH
 *
 * Input: Desired Baud Rate
 * Output: Actual Baud Rate from baud control register U2BRG after assignment*/
int UART2Configure( int desired_baud)
{
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
    // Calculate actual baud rate
    int actual_baud = SYSCLK / (16 * (U2BRG+1));
    return actual_baud;
}
