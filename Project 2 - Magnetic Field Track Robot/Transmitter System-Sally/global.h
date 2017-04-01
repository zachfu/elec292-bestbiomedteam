#define SYSCLK    48000000L // SYSCLK frequency in Hz
#define BAUDRATE    115200L // Baud rate of UART in bps

#define TIMER_0_FREQ 1000L 	// for Command signal (1KHz for 100 Baud rate)
#define TIMER_2_FREQ 16000L	// for Guid Signal (16KHz)



/********** pin configuration *********/

#define GUID_SIG 		P2_0// output pin for guid signal
#define COMMAND_SIG 	P2_1// output pin for command signal
							/* P2_2 to 7 is for LCD */

#define SEND  			P1_0
#define NEXT   			P1_1
#define STOP	 		P1_2	//Complete stop
#define CONTINUE		P1_3	//Continue with Previous speed
#define TURN_180	 	P1_4	//180 degrees turn
#define SPEED_UP		P1_5
#define SPEED_DOWN		P1_6
#define TEST_PIN		P1_7



#define PUSH_SFRPAGE _asm push _SFRPAGE _endasm
#define POP_SFRPAGE _asm pop _SFRPAGE _endasm