<p align="center">
  <img src="BlackScreenGuard-logo.png" width="160" alt="BlackScreen Guard icon">
</p>

<h1 align="center">BlackScreen Guard</h1>

<p align="center">
  English | <a href="README.md">简体中文</a>
</p>

A multi-monitor display-off utility for Windows 11. It first covers every display with a pure-black overlay and then asks Windows to turn the displays off, while keeping the computer, background applications, and existing remote sessions running. The application is a directly compiled C# WinForms executable with no self-extracting payload, PowerShell launcher, or runtime script.

## Interface preview

### Control page

<p align="center">
  <img src="assets/screenshots/control-page.png" width="760" alt="BlackScreen Guard control page">
</p>

### Blackout control panel

After selecting **Start**, the application covers every display with a pure-black image and then asks Windows to turn off the display backlights.

<p align="center">
  <img src="assets/screenshots/blackout.png" width="960" alt="BlackScreen Guard pure-black screen">
</p>

Mouse or keyboard input wakes the displays. Move the pointer by about 30 pixels or click to reveal the **Continue Blackout** and **Exit** controls. Selecting **Continue Blackout** turns the displays off again.

<p align="center">
  <img src="assets/screenshots/blackout-control.png" width="960" alt="BlackScreen Guard blackout control panel">
</p>

## Features

- Asks Windows to turn off every connected display so supported LCD backlights actually switch off
- Keeps a pure-black window ready to protect the picture when input wakes a display
- Prevents idle system sleep while allowing the displays to remain off
- Keeps background applications and existing network sessions running
- Captures ordinary keyboard and mouse input inside the blackout windows
- Hides the pointer after about 2 seconds of inactivity and reveals it on movement
- Shows a compact control panel after a click or about 30 pixels of movement
- Automatically hides the control panel after about 2 seconds of inactivity
- Provides Continue Blackout, Exit, and `Esc` quick-exit controls
- Leaves the Windows `Ctrl + Alt + Delete` secure attention sequence intact

## Download and use the EXE

Download the latest `BlackScreenGuard.exe` from [Releases](https://github.com/celestial-micha/BlackScreenGuard/releases), run it, and select **Start** on the control page.

No installation is required. Because the executable is not code-signed, Windows SmartScreen may display a warning on first launch.

## Run from source

Double-click `启动 BlackScreen Guard.cmd`. If the executable has not been built, the launcher first invokes the .NET Framework C# compiler included with Windows and then runs the resulting EXE directly.

## Build the EXE

On Windows 11, double-click `build-exe.cmd`. The output is written to:

```text
dist\BlackScreenGuard.exe
```

The build uses the .NET Framework C# compiler included with Windows. It requires no Node.js installation, PowerShell modules, or third-party packaging tools. The build script creates a temporary EXE, runs its built-in self-test, and only then replaces the final output.

## Security and distribution

- The release file is a regular C# WinForms executable and does not extract or launch another script.
- The application runs with the current user's permissions; its manifest explicitly requests `asInvoker` and never requests elevation.
- Publisher metadata is `celestial-micha` and no longer inherits Microsoft metadata from an IExpress stub.
- Public builds are not yet signed with a commercial Authenticode certificate, so a newly downloaded file can still receive an “unknown publisher” SmartScreen reputation prompt. That prompt is distinct from Defender classifying the file as a Trojan.
- Production files should be code-signed only after all icons, versions, and resources are final; never modify a file after signing.

## How it works and limitations

- The C# application directly invokes Windows `SC_MONITORPOWER` to request display power-off and uses `SetThreadExecutionState` only to prevent idle system sleep, so background applications can keep running.
- On most built-in panels and power-management-capable external monitors, display-off actually switches off the LCD backlight. The graphics driver, monitor firmware, and connection ultimately determine whether the request is honored; the pure-black overlay remains as a fallback.
- Mouse or keyboard input, system notifications, and some peripherals can wake a display. After input becomes idle, or when **Continue Blackout** is selected, the application requests display-off again.
- On OLED displays, pure-black pixels normally emit no light, but the application still requests display-off to reduce power use.
- Domain policies, security software, network loss, shutdowns, restarts, and power loss can still affect background applications and remote connectivity.
- `Ctrl + Alt + Delete` is a Windows secure attention sequence and cannot—and should not—be intercepted by a regular application.

## Project layout

```text
src/BlackScreenGuard.cs       C# WinForms application
src/app.manifest              Windows permissions and compatibility manifest
启动 BlackScreen Guard.cmd    Build-and-run entry point
build-exe.cmd                 C# build and self-test entry point
assets/                       Icon assets
assets/screenshots/           README interface screenshots
BlackScreenGuard-logo.png     High-resolution logo
BlackScreenGuard.ico          Application window icon
LICENSE                       MIT open-source license
```

## License

This project is open source under the [MIT License](LICENSE).

You may use, copy, modify, and distribute this project. When using or redistributing it, retain the original copyright and license notice and acknowledge the project source:

[celestial-micha/BlackScreenGuard](https://github.com/celestial-micha/BlackScreenGuard)
