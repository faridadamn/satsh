@echo off
setlocal
title satsh desktop - install
cd /d "%~dp0"
echo.
echo   ===  satsh desktop  ===
echo.

rem --- cari Python: Win7 = 3.8, Win10/11 = 3.8 s/d 3.14 ---
set PY=
set CHK=import sys; sys.exit(0 if (3,8) ^<= sys.version_info[:2] ^<= (3,14) else 1)
py -3.8 -c "import sys" >nul 2>&1 && set PY=py -3.8
if "%PY%"=="" py -3 -c "%CHK%" >nul 2>&1 && set PY=py -3
if "%PY%"=="" python -c "%CHK%" >nul 2>&1 && set PY=python
if "%PY%"=="" (
  echo   [X] Python ga ketemu.
  echo       Windows 7 : install Python 3.8.10  https://www.python.org/downloads/release/python-3810/
  echo       Windows 10/11: install Python 3.12  https://www.python.org/downloads/
  echo       Centang "Add Python to PATH" pas install, terus jalanin install.bat lagi.
  pause
  exit /b 1
)
echo   [OK] Pakai: %PY%

rem --- bikin virtualenv ---
if not exist ".venv\Scripts\python.exe" (
  echo   ... bikin .venv
  %PY% -m venv .venv || (echo   [X] Gagal bikin venv & pause & exit /b 1)
)

rem --- pilih wheel 32/64-bit ---
for /f %%b in ('.venv\Scripts\python.exe -c "import struct;print(struct.calcsize(chr(80))*8)"') do set BITS=%%b
for /f %%v in ('.venv\Scripts\python.exe -c "import sys;print(*sys.version_info[:2],sep='.')"') do set PYV=%%v
if "%BITS%"=="64" (set WH=wheels\win_amd64) else (set WH=wheels\win32)
echo   [OK] Python %PYV% %BITS%-bit, wheel dari %WH%

echo   ... install library - offline
.venv\Scripts\python.exe -m pip install --no-index --find-links "%WH%" -r requirements.txt || (
  echo   ... offline gagal, coba online
  .venv\Scripts\python.exe -m pip install -r requirements.txt || (echo   [X] Install library gagal & pause & exit /b 1)
)

rem --- shortcut Desktop (+ Startup kalau mau) ---
set VBS=%TEMP%\satsh_lnk.vbs
> "%VBS%" echo Set s = CreateObject("WScript.Shell")
>>"%VBS%" echo Set l = s.CreateShortcut(WScript.Arguments(0))
>>"%VBS%" echo l.TargetPath = "%~dp0.venv\Scripts\pythonw.exe"
>>"%VBS%" echo l.Arguments = "-m satsh"
>>"%VBS%" echo l.WorkingDirectory = "%~dp0"
>>"%VBS%" echo l.IconLocation = "%~dp0satsh.ico"
>>"%VBS%" echo l.Description = "satsh desktop"
>>"%VBS%" echo l.Save
cscript //nologo "%VBS%" "%USERPROFILE%\Desktop\satsh.lnk"
echo   [OK] Shortcut "satsh" di Desktop

echo.
set /p AUTO=  Nyalain satsh otomatis tiap Windows nyala? (y/n): 
if /i "%AUTO%"=="y" (
  cscript //nologo "%VBS%" "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\satsh.lnk"
  echo   [OK] Autostart aktif
)
del "%VBS%" >nul 2>&1

echo.
echo   Beres! Buka satsh lewat shortcut di Desktop.
echo   (UI kebuka di browser: http://127.0.0.1:8771 - paling enak pakai Chrome)
echo.
start "" ".venv\Scripts\pythonw.exe" -m satsh
pause
