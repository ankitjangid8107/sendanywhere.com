@echo off
:: Run as Administrator automatically
net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath \"%~f0\"" & exit /b)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
pause
