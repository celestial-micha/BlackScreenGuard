@echo off
setlocal
cd /d "%~dp0"
if not exist dist mkdir dist
C:\Windows\System32\iexpress.exe /N package.sed
if exist "dist\BlackScreenGuard.exe" (
  where node >nul 2>nul
  if errorlevel 1 (
    echo Node.js was not found. EXE created without the custom icon.
    exit /b 0
  )
  node set-icon.js
  if errorlevel 1 (
    echo EXE created, but custom icon embedding failed.
    exit /b 1
  )
  echo Build succeeded: dist\BlackScreenGuard.exe
  exit /b 0
)
echo Build failed.
exit /b 1
