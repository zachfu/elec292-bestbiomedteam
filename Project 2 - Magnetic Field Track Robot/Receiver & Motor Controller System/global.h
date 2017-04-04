// Defines
#define SYSCLK 40000000L
#define FREQ		100L	// Frequency of timer 2
#define VREF 	3.265		// ADC reference voltage
#define Baud2BRG(desired_baud)( (SYSCLK / (16*desired_baud))-1)
#define BUZZER_FREQ		4000L	// Frequency of timer 2

// Constants  
#define MAX_MISALIGNMENT 1.7
#define SPEED_SCALING (1.0/3.0)
#define INTERSECT_VOLTAGE 1.4
#define ALIGN_TOLERANCE 0.045
#define INTERSECT_MINVOLTAGE 0.25
#define ALIGN_MINVOLTAGE 0.225
#define INTERSECT_SCALING 2.75

// Pin assignment defines
#define H11_PIN LATBbits.LATB15
#define H12_PIN LATBbits.LATB14
#define H21_PIN LATBbits.LATB13
#define H22_PIN LATBbits.LATB12
#define SOUND_OUT   LATBbits.LATB0
#define AMBER_R	    LATAbits.LATA0
#define AMBER_L 	LATAbits.LATA1

// Receive Commands
#define StopCommand 's'
#define	TurnLeft 'l'	
#define TurnRight 'r'
#define Turn180Command 'o'
#define ReverseCommand 'v'
#define NullCommand 'n'
#define Speed_Up		 'u'
#define Speed_Down		 'd'
