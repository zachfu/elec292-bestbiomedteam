@echo off
::This file was created automatically by CrossIDE to compile with C51.
C:
cd "\Users\Sally\Downloads\elec292-bestbiomedteam-master\elec292-bestbiomedteam-master\Project 2 - Magnetic Field Track Robot\Transmitter System\"
"C:\CrossIDE\Call51\Bin\c51.exe" --use-stdout  "C:\Users\Sally\Downloads\elec292-bestbiomedteam-master\elec292-bestbiomedteam-master\Project 2 - Magnetic Field Track Robot\Transmitter System\main.c"
if not exist hex2mif.exe goto done
if exist main.ihx hex2mif main.ihx
if exist main.hex hex2mif main.hex
:done
echo done
echo Crosside_Action Set_Hex_File C:\Users\Sally\Downloads\elec292-bestbiomedteam-master\elec292-bestbiomedteam-master\Project 2 - Magnetic Field Track Robot\Transmitter System\main.hex
