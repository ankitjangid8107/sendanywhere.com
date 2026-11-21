@echo off
setlocal EnableExtensions
title SendAnywhere LAN - Safe Setup
cd /d "%~dp0"
set "NAME=SendAnywhereLAN"
set "PORT=8080"
set "APPDIR=%~dp0iis-app"
set "DATADIR=%~dp0iis-app\App_Data"
set "LOG=%~dp0setup-log.txt"
set "APPCMD=%windir%\system32\inetsrv\appcmd.exe"

echo ============================================================
echo   SendAnywhere LAN - Safe IIS Setup  (by AJ System Soft)
echo   Other IIS sites are NOT restarted, changed or deleted.
echo ============================================================
echo.

rem ---- Administrator check ----
fltmc >nul 2>&1
if errorlevel 1 (
  echo [!] Administrator rights required.
  echo     Trying to restart as Administrator...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul 2>&1
  if errorlevel 1 (
    echo.
    echo     Could not elevate automatically.
    echo     Right-click setup-safe.bat and choose "Run as administrator".
    pause
  )
  exit /b
)

if not exist "%APPDIR%\index.html" (
  echo [X] Folder "%APPDIR%" not found. Keep setup-safe.bat next to the iis-app folder.
  goto :end
)

echo Log file: %LOG%
echo Setup started %date% %time% > "%LOG%"

echo.
echo [1/6] Enabling IIS + ASP.NET 4.x features (first time can take a few minutes)...
for %%F in (IIS-WebServerRole IIS-WebServer IIS-CommonHttpFeatures IIS-StaticContent IIS-DefaultDocument IIS-HttpErrors IIS-RequestFiltering IIS-ManagementConsole IIS-ApplicationDevelopment NetFx4Extended-ASPNET45 IIS-NetFxExtensibility45 IIS-ISAPIExtensions IIS-ISAPIFilter IIS-ASPNET45) do (
  dism /online /enable-feature /featurename:%%F /all /norestart /quiet >>"%LOG%" 2>&1
  if errorlevel 1 (echo       skip %%F) else (echo       ok   %%F)
)

if not exist "%APPCMD%" (
  echo [X] IIS is not installed - appcmd.exe missing. Restart the PC and run this setup again.
  goto :end
)

echo.
echo [2/6] Finding a free port (other software is never touched)...
"%APPCMD%" stop site "%NAME%" >nul 2>&1
for %%P in (8080 8090 8181 8282 8383 8484 8585 9090 9191 9292 9393 9494 9595 7070 7171) do (
  call :portfree %%P && (set "PORT=%%P" & goto :portok)
)
echo [X] No free port found. Close some programs and run again.
goto :end
:portok
echo       Using port %PORT%

echo.
echo [3/6] App pool "%NAME%" (.NET v4.0, Integrated)...
"%APPCMD%" list apppool "%NAME%" >nul 2>&1
if errorlevel 1 "%APPCMD%" add apppool /name:"%NAME%" >>"%LOG%" 2>&1
"%APPCMD%" set apppool "%NAME%" /managedRuntimeVersion:v4.0 /managedPipelineMode:Integrated >>"%LOG%" 2>&1

echo.
echo [4/6] Website "%NAME%" ^-^> %APPDIR%
"%APPCMD%" list site "%NAME%" >nul 2>&1
if errorlevel 1 (
  "%APPCMD%" add site /name:"%NAME%" /bindings:http/*:%PORT%: /physicalPath:"%APPDIR%" >>"%LOG%" 2>&1
) else (
  "%APPCMD%" set site "%NAME%" /bindings:http/*:%PORT%: >>"%LOG%" 2>&1
  "%APPCMD%" set vdir "%NAME%/" /physicalPath:"%APPDIR%" >>"%LOG%" 2>&1
)
"%APPCMD%" set app "%NAME%/" /applicationPool:"%NAME%" >>"%LOG%" 2>&1

echo.
echo [5/6] Permissions + firewall...
if not exist "%DATADIR%" mkdir "%DATADIR%"
icacls "%DATADIR%" /grant "IIS_IUSRS:(OI)(CI)M" /T /Q >>"%LOG%" 2>&1
icacls "%DATADIR%" /grant "IIS AppPool\%NAME%:(OI)(CI)M" /T /Q >>"%LOG%" 2>&1
netsh advfirewall firewall delete rule name="%NAME%" >nul 2>&1
netsh advfirewall firewall add rule name="%NAME%" dir=in action=allow protocol=TCP localport=%PORT% >>"%LOG%" 2>&1

echo.
echo [6/6] Restarting ONLY the %NAME% site...
"%APPCMD%" recycle apppool "%NAME%" >nul 2>&1
"%APPCMD%" stop site "%NAME%" >nul 2>&1
"%APPCMD%" start site "%NAME%" >>"%LOG%" 2>&1
if errorlevel 1 (
  echo [X] Site could not start on port %PORT%. See setup-log.txt
  goto :end
)

echo.
where curl >nul 2>&1 && (
  curl -s -m 20 "http://localhost:%PORT%/api/transfer.ashx?action=ping" | findstr /c:"\"ok\":true" >nul && (
    echo [OK] API test passed - uploads will work.
  ) || (
    echo [!] API test failed. Restart the PC once ^(new IIS features^) and run this setup again.
    echo     If it still fails send setup-log.txt.
  )
)

echo.
echo ============================================================
echo  Done. Open on this PC:   http://localhost:%PORT%
echo  Other devices on LAN:
for /f "tokens=2 delims=:" %%I in ('ipconfig ^| findstr /c:"IPv4"') do for /f "tokens=*" %%J in ("%%I") do echo     http://%%J:%PORT%
echo ============================================================
start "" "http://localhost:%PORT%"

:end
echo.
pause
exit /b

:portfree
rem returns errorlevel 0 when nothing is listening on port %1
netstat -ano | findstr /r /c:":%1 .*LISTENING" >nul 2>&1 && exit /b 1
"%APPCMD%" list site 2>nul | findstr /c:":%1:" | findstr /v /c:"\"%NAME%\"" >nul 2>&1 && exit /b 1
exit /b 0
