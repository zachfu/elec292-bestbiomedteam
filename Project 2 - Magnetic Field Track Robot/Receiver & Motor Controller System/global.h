// Defines
#define SYSCLK 40000000L
#define FREQ		100L	// Frequency of timer 2
#define VREF 	3.265		// ADC reference voltage
#define Baud2BRG(desired_baud)( (SYSCLK / (16*desired_baud))-1)

#define Max_Misalignment 1.3

// Pin assignment defines
#define H11_PIN LATBbits.LATB15
#define H12_PIN LATBbits.LATB14
#define H21_PIN LATBbits.LATB13
#define H22_PIN LATBbits.LATB12

// Miscellaneous 'bits'/flags