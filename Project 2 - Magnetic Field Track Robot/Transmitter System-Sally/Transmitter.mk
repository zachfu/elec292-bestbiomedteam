CC=c51
COMPORT = $(shell type COMPORT.inc)
OBJS=main.obj startup.obj lcd.obj

main.hex: $(OBJS)
	$(CC) $(OBJS)
	@del *.asm *.lst *.lkr 2> nul
	@echo Done!
	
main.obj: main.c lcd.h global.h
	$(CC) -c main.c

startup.obj: startup.c global.h
	$(CC) -c startup.c

lcd.obj: lcd.c lcd.h global.h
	$(CC) -c lcd.c

clean:
	@del $(OBJS) *.asm *.lkr *.lst *.map *.hex *.map 2> nul

LoadFlash:
	@Taskkill /IM putty.exe /F 2>NUL | wait 500
	F38X_prog main.hex

putty:
	@Taskkill /IM putty.exe /F 2>NUL | wait 500
	putty -serial $(COMPORT) -sercfg 115200,8,n,1,N -v

Dummy: main.hex main.Map
	@echo Nothing to see here!
	
explorer:
	explorer .
		