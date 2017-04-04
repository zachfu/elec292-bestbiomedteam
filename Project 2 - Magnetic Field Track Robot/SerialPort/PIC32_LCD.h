#define LCD_RS LATBbits.LATB6
//#define LCD_RW GND // Not used in this code.  Connect to GND
#define LCD_E  LATBbits.LATB5
#define LCD_D4 LATAbits.LATA4
#define LCD_D5 LATBbits.LATB4
#define LCD_D6 LATAbits.LATA3
#define LCD_D7 LATAbits.LATA2

#define LCD_RS_ENABLE TRISBbits.TRISB6
#define LCD_E_ENABLE  TRISBbits.TRISB5
#define LCD_D4_ENABLE TRISAbits.TRISA4
#define LCD_D5_ENABLE TRISBbits.TRISB4
#define LCD_D6_ENABLE TRISAbits.TRISA3
#define LCD_D7_ENABLE TRISAbits.TRISA2


#define CHARS_PER_LINE 16

union BYTE {
    unsigned char byte;
    struct {
        unsigned char bit0    :1;
        unsigned char bit1    :1;
        unsigned char bit2    :1;
        unsigned char bit3    :1;
        unsigned char bit4    :1;
        unsigned char bit5    :1;
        unsigned char bit6    :1;
        unsigned char bit7    :1;
    };
};

void Timer4us(unsigned char us);
void waitms (unsigned int ms);
void LCD_pulse (void);
void LCD_byte (unsigned char x);
void WriteData (unsigned char x);
void WriteCommand (unsigned char x);
void LCD_4BIT (void);
void LCDprint(char * string, unsigned char line, unsigned char clear);
