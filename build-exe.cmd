@echo off
setlocal
cd /d "%~dp0"
set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"

if not exist "%CSC%" (
  echo Build failed: the Windows .NET Framework C# compiler was not found.
  exit /b 1
)

if not exist dist mkdir dist
if not exist "dist\.build" mkdir "dist\.build"
if exist "dist\.build\BlackScreenGuard.exe" del /q "dist\.build\BlackScreenGuard.exe"

"%CSC%" /nologo /target:winexe /platform:anycpu /optimize+ /debug- /warn:4 /warnaserror+ /codepage:65001 ^
  /win32icon:BlackScreenGuard.ico ^
  /win32manifest:src\app.manifest ^
  /out:dist\.build\BlackScreenGuard.exe ^
  /reference:System.dll ^
  /reference:System.Drawing.dll ^
  /reference:System.Windows.Forms.dll ^
  src\BlackScreenGuard.cs

if errorlevel 1 (
  if exist "dist\.build\BlackScreenGuard.exe" del /q "dist\.build\BlackScreenGuard.exe"
  rmdir "dist\.build" 2>nul
  echo Build failed.
  exit /b 1
)

start /wait "" "dist\.build\BlackScreenGuard.exe" --self-test
if errorlevel 1 (
  del /q "dist\.build\BlackScreenGuard.exe"
  rmdir "dist\.build" 2>nul
  echo Build failed: executable self-test did not pass.
  exit /b 1
)

move /y "dist\.build\BlackScreenGuard.exe" "dist\BlackScreenGuard.exe" >nul
if errorlevel 1 (
  echo Build failed: could not replace dist\BlackScreenGuard.exe.
  exit /b 1
)
rmdir "dist\.build" 2>nul

echo Build succeeded: dist\BlackScreenGuard.exe
exit /b 0
