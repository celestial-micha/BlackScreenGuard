<p align="center">
  <img src="BlackScreenGuard-logo.png" width="160" alt="BlackScreen Guard icon">
</p>

<h1 align="center">BlackScreen Guard</h1>

<p align="center">
  English | <a href="README.md">简体中文</a>
</p>

A multi-monitor blackout utility for Windows 11. It covers every connected display with a pure-black overlay, prevents idle sleep and automatic display power-off, keeps the computer awake, allows background applications to continue running, and maintains the operating environment required by existing remote connections.

## Interface preview

### Control page

<p align="center">
  <img src="assets/screenshots/control-page.png" width="760" alt="BlackScreen Guard control page">
</p>

### Blackout control panel

After selecting **Start**, the application first covers every display with a pure-black image.

<p align="center">
  <img src="assets/screenshots/blackout.png" width="960" alt="BlackScreen Guard pure-black screen">
</p>

Move the pointer by about 30 pixels or click during blackout to reveal the **Continue Blackout** and **Exit** controls.

<p align="center">
  <img src="assets/screenshots/blackout-control.png" width="960" alt="BlackScreen Guard blackout control panel">
</p>

## Features

- Covers every connected monitor with a pure-black window
- Prevents idle system sleep and automatic display power-off
- Keeps background applications and existing network sessions running
- Captures ordinary keyboard and mouse input inside the blackout windows
- Hides the pointer after about 1.2 seconds of inactivity and reveals it on movement
- Shows a compact control panel after a click or about 30 pixels of movement
- Automatically hides the control panel after 4 seconds of inactivity
- Provides Continue Blackout, Exit, and `Esc` quick-exit controls
- Leaves the Windows `Ctrl + Alt + Delete` secure attention sequence intact

## Download and use

Download the latest `BlackScreenGuard.exe` from [Releases](https://github.com/celestial-micha/BlackScreenGuard/releases), run it, and select **Start** on the control page.

No installation is required. Because the executable is not code-signed, Windows SmartScreen may display a warning on first launch.

## Run from source

Double-click `启动 BlackScreen Guard.cmd`. Windows 11 already includes the required Windows PowerShell and WinForms components.

## Build the EXE

On Windows 11, double-click `build-exe.cmd`. The output is written to:

```text
dist\BlackScreenGuard.exe
```

Packaging uses the IExpress component included with Windows. Embedding the custom icon requires Node.js; before the first build, run:

```powershell
pnpm install
```

## How it works and limitations

- The blackout is a topmost pure-black window; it does not physically turn off the monitor. An LCD backlight normally remains on.
- The application uses Windows `SetThreadExecutionState` to request prevention of idle sleep and automatic display power-off.
- Domain policies, security software, network loss, shutdowns, restarts, and power loss can still affect background applications and remote connectivity.
- `Ctrl + Alt + Delete` is a Windows secure attention sequence and cannot—and should not—be intercepted by a regular application.

## Project layout

```text
BlackScreenGuard.ps1          Main application
启动 BlackScreen Guard.cmd    Source launcher
build-exe.cmd                 EXE build entry point
package.sed                   IExpress package definition
assets/                       Icon assets
assets/screenshots/           README interface screenshots
BlackScreenGuard-logo.png     High-resolution logo
BlackScreenGuard.ico          Application window icon
```
