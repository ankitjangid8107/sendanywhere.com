@echo off
setlocal
title SendAnywhere LAN - Emergency password reset
cd /d "%~dp0"
fltmc >nul 2>&1
if errorlevel 1 (
  echo Administrator rights required. Right-click reset-password.bat and choose "Run as administrator".
  pause
  exit /b
)
if not exist "%~dp0iis-app\App_Data\accounts" (
  echo No accounts found yet. Open the website and create the admin account first.
  pause
  exit /b
)
echo %date% %time% > "%~dp0iis-app\App_Data\accounts\reset.allow"
echo.
echo Emergency reset is now allowed for 15 minutes.
echo.
echo  1. On THIS server PC open the website (http://localhost:PORT)
echo  2. Click Login - Forgot? - choose "Server PC"
echo  3. Type the username (admin or user) and a new password
echo.
echo This works only on this PC and only for the next 15 minutes.
pause
