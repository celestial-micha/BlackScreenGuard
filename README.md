<p align="center">
  <img src="BlackScreenGuard-logo.png" width="160" alt="BlackScreen Guard 图标">
</p>

<h1 align="center">BlackScreen Guard｜黑屏守护</h1>

<p align="center">
  <a href="README_EN.md">English</a> | 简体中文
</p>

适用于 Windows 11 的多显示器熄屏保护工具。启动后先用纯黑遮罩覆盖所有显示器，再请求 Windows 关闭显示器；电脑和后台程序继续运行，并可维持现有远程连接所需的运行环境。程序是直接编译的 C# WinForms EXE，不包含自解压载荷、PowerShell 启动器或运行时脚本。

## 界面预览

### 控制主页

<p align="center">
  <img src="assets/screenshots/control-page.png" width="760" alt="BlackScreen Guard 控制主页">
</p>

### 黑屏控制面板

点击“开始”后，程序首先以纯黑画面覆盖所有显示器，随后请求 Windows 关闭显示器背光。

<p align="center">
  <img src="assets/screenshots/blackout.png" width="960" alt="BlackScreen Guard 纯黑画面">
</p>

移动鼠标或按键会唤醒显示器。移动鼠标约 30 像素或单击，即可显示“继续黑屏”和“退出程序”控制面板；选择“继续黑屏”后会再次熄屏。

<p align="center">
  <img src="assets/screenshots/blackout-control.png" width="960" alt="BlackScreen Guard 黑屏控制面板">
</p>

## 功能

- 请求 Windows 关闭所有已连接的显示器，使受支持的 LCD 背光真正熄灭
- 使用纯黑窗口保护显示器被输入唤醒后的画面
- 阻止系统因闲置而自动休眠，同时允许显示器保持关闭
- 黑屏期间继续运行后台程序和现有网络会话
- 拦截黑屏窗口内的普通按键与鼠标点击，减少误操作
- 鼠标静止约 2 秒后自动隐藏，移动时立即显示
- 移动约 30 像素或单击后显示控制面板
- 控制面板无操作约 2 秒后自动隐藏
- 支持“继续黑屏”、退出程序和 `Esc` 快速退出
- 保留 Windows `Ctrl + Alt + Delete` 安全序列

## EXE 下载与使用

从 [Releases](https://github.com/celestial-micha/BlackScreenGuard/releases) 下载最新的 `BlackScreenGuard.exe`，双击运行，然后在控制页面点击“开始”。

程序无需安装。首次运行未经代码签名的 EXE 时，Windows SmartScreen 可能显示安全提示。

## 从源码运行

双击 `启动 BlackScreen Guard.cmd`。如果尚未构建，启动脚本会先调用 Windows 自带的 .NET Framework C# 编译器生成 EXE，然后直接运行它。

## 构建 EXE

在 Windows 11 中双击 `build-exe.cmd`，构建结果位于：

```text
dist\BlackScreenGuard.exe
```

构建过程使用 Windows 自带的 .NET Framework C# 编译器。无需安装 Node.js、PowerShell 模块或第三方打包工具。构建脚本先生成临时 EXE、执行内置自检，再以通过验证的文件替换正式输出。

## 安全与分发

- 发布文件是普通 C# WinForms EXE，不会解压或启动其他脚本。
- 应用以当前用户权限运行，清单明确设置为 `asInvoker`，不会请求管理员权限。
- EXE 元数据中的发布者为 `celestial-micha`，不再继承 IExpress 的 Microsoft 元数据。
- 当前公开构建尚未使用商业 Authenticode 证书，因此新下载仍可能出现“未知发布者”的 SmartScreen 信誉提示；这与 Defender 将文件直接识别为木马是两类不同提示。
- 正式发布前应在最终文件生成后进行代码签名；签名后不得再次修改图标、版本或其他资源。

## 工作方式与限制

- 程序直接通过 C# P/Invoke 使用 Windows `SC_MONITORPOWER` 请求关闭显示器，并使用 `SetThreadExecutionState` 只阻止系统闲置休眠；后台程序仍可继续运行。
- 在大多数内置屏幕和支持电源管理的外接显示器上，关屏会使 LCD 背光真正熄灭。是否响应该请求最终取决于显卡驱动、显示器固件和连接方式；不响应时仍会保留纯黑遮罩作为后备。
- 鼠标、键盘、系统通知或某些外设可能唤醒显示器。无操作时程序会再次请求关屏；选择“继续黑屏”也会立即进入下一次关屏。
- OLED 显示器显示纯黑时像素本身通常已不发光，但本程序仍会请求系统关屏以降低耗电。
- 公司域策略、安全软件、断网、关机、重启或断电仍可能影响后台程序和远程连接。
- `Ctrl + Alt + Delete` 属于 Windows 安全序列，普通应用无法也不应拦截。

## 项目文件

```text
src/BlackScreenGuard.cs       C# WinForms 主程序
src/app.manifest              Windows 权限与兼容性清单
启动 BlackScreen Guard.cmd    构建并启动入口
build-exe.cmd                 C# EXE 构建与自检入口
assets/                       图标资源
assets/screenshots/           README 界面截图
BlackScreenGuard-logo.png     高清 Logo
BlackScreenGuard.ico          程序窗口图标
LICENSE                       MIT 开源许可证
```

## 开源许可证

本项目采用 [MIT License](LICENSE) 开源。

你可以自由使用、复制、修改和分发本项目；使用或分发时请保留原始版权与许可证声明，并注明项目来源：

[celestial-micha/BlackScreenGuard](https://github.com/celestial-micha/BlackScreenGuard)
