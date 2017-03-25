// Defines
#define SYSCLK 40000000L
#define FREQ		100L	// Frequency of timer 2
#define VREF 	3.233		// ADC reference voltage
#define Baud2BRG(desired_baud)( (SYSCLK / (16*desired_baud))-1)