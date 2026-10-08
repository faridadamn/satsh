@echo off
rem Jalanin satsh dengan jendela console (buat lihat log / debug)
cd /d "%~dp0"
".venv\Scripts\python.exe" -m satsh %*
pause
