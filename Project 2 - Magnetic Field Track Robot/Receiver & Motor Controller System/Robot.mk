CC = xc32-gcc
OBJCPY = xc32-bin2hex
ARCH = -mprocessor=32MX130F064B
OBJS = Robot.o PIC32_LCD.o
PORTN=$(shell type COMPORT.inc)
Robot.elf: $(OBJS)
	$(CC) $(ARCH) -o Robot.elf $(OBJS) -mips16 -DXPRJ_default=default -legacy-libc -Wl,-Map=Robot.map
	$(OBJCPY) Robot.elf
	@echo Success!
   
Robot.o: Robot.c global.h
	$(CC) -mips16 -g -x c -c $(ARCH) -MMD -o Robot.o Robot.c -DXPRJ_default=default -legacy-libc

PIC32_LCD.o: PIC32_LCD.c global.h
	$(CC) -mips16 -g -x c -c $(ARCH) -MMD -o PIC32_LCD.o PIC32_LCD.c -DXPRJ_default=default -legacy-libc	
	
clean:
	@del *.o 2>NUL
	@del *.elf *.hex *.d *.map 2>NUL
	
LoadFlash:
	@Taskkill /IM putty.exe /F 2>NUL | wait 500
	pro32.exe -p -v Robot.hex

putty:
	@Taskkill /IM putty.exe /F 2>NUL | wait 500
	c:\putty\putty.exe -serial $(PORTN) -sercfg 115200,8,n,1,N -v

dummy: Robot.hex Robot.map
	$(CC) --version

explorer:
	@explorer .