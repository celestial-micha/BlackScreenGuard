@echo off
setlocal
cd /d "%~dp0"
if not exist "dist\BlackScreenGuard.exe" call build-exe.cmd
if errorlevel 1 exit /b 1
start "" "dist\BlackScreenGuard.exe"
