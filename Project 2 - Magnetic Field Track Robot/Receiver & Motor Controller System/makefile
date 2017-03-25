CC = xc32-gcc
OBJCPY = xc32-bin2hex
ARCH = -mprocessor=32MX130F064B
OBJS = Project2.o PIC32_LCD.o
PORTN=$(shell type COMPORT.inc)
Project2.elf: $(OBJS)
	$(CC) $(ARCH) -o Project2.elf $(OBJS) -mips16 -DXPRJ_default=default -legacy-libc -Wl,-Map=Project2.map
	$(OBJCPY) Project2.elf
	@echo Success!
   
Project2.o: Project2.c global.h
	$(CC) -mips16 -g -x c -c $(ARCH) -MMD -o Project2.o Project2.c -DXPRJ_default=default -legacy-libc

PIC32_LCD.o: PIC32_LCD.c global.h
	$(CC) -mips16 -g -x c -c $(ARCH) -MMD -o PIC32_LCD.o PIC32_LCD.c -DXPRJ_default=default -legacy-libc	
	
clean:
	@del *.o 2>NUL
	@del *.elf *.hex 2>NUL
	
LoadFlash:
	@Taskkill /IM putty.exe /F 2>NUL | wait 500
	pro32.exe -p -v Project2.hex

putty:
	@Taskkill /IM putty.exe /F 2>NUL | wait 500
	c:\putty\putty.exe -serial $(PORTN) -sercfg 115200,8,n,1,N -v

dummy: Project2.hex Project2.map
	$(CC) --version

explorer:
	@explorer .