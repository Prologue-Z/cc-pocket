@echo off
setlocal

set "DAEMON=daemon\build\install\cc-pocket-daemon\bin\cc-pocket-daemon.bat"
set "CLAUDE=C:\Users\Administrator\AppData\Roaming\npm\claude.cmd"
set "JDK=C:\Program Files\Eclipse Adoptium\jdk-17.0.17.10-hotspot"

echo ============================================
echo  cc-pocket local debug launcher
echo ============================================
echo.
echo  Daemon window will open. Keep it running.
echo  Desktop client: ws://127.0.0.1:8765/v1/ws
echo ============================================

REM Start daemon in a separate window that stays open
start "" cmd /k "cd /d %~dp0 && %DAEMON% run --local --host 127.0.0.1 --claude-bin "%CLAUDE%""

echo Waiting for daemon (8s)...
timeout /t 8 /nobreak >nul

REM Start desktop client
echo.
echo Starting desktop client...
call gradlew.bat :mobile:composeApp:run "-Dorg.gradle.java.home=%JDK%"
