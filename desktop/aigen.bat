@echo off
rem Jalanin aigen dengan jendela console (buat lihat log / debug)
cd /d "%~dp0"
".venv\Scripts\python.exe" -m aigen %*
pause
