param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$SelfTest = $args -contains '-SelfTest'
$CaptureScreenshots = $args -contains '-CaptureScreenshots'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class BlackScreenGuardNative {
    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SendMessageTimeout(
        IntPtr hwnd,
        uint message,
        UIntPtr wParam,
        IntPtr lParam,
        uint flags,
        uint timeout,
        out UIntPtr result
    );

    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(
        IntPtr hwnd,
        int attribute,
        ref int value,
        int valueSize
    );

    public const uint ES_CONTINUOUS       = 0x80000000;
    public const uint ES_SYSTEM_REQUIRED  = 0x00000001;

    private static readonly IntPtr HWND_BROADCAST = new IntPtr(0xffff);
    private const uint WM_SYSCOMMAND = 0x0112;
    private const uint SC_MONITORPOWER = 0xF170;
    private const uint SMTO_ABORTIFHUNG = 0x0002;

    public static bool RequestDisplayPower(int state) {
        UIntPtr result;
        return SendMessageTimeout(
            HWND_BROADCAST,
            WM_SYSCOMMAND,
            new UIntPtr(SC_MONITORPOWER),
            new IntPtr(state),
            SMTO_ABORTIFHUNG,
            1000,
            out result
        ) != IntPtr.Zero;
    }
}
'@

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

$script:BlackWindows = [System.Collections.Generic.List[System.Windows.Forms.Form]]::new()
$script:SessionStartedAt = $null
$script:IsBlackoutActive = $false
$script:StartMousePosition = [System.Drawing.Point]::Empty
$script:CursorShown = $false
$script:SuppressCursorRevealUntil = [DateTime]::MinValue
$script:ControlPanelVisible = $false
$script:ControlPanelTimer = [System.Windows.Forms.Timer]::new()
$script:ControlPanelTimer.Interval = 2000
$script:CursorIdleTimer = [System.Windows.Forms.Timer]::new()
$script:CursorIdleTimer.Interval = 2000
$script:DisplayPowerTimer = [System.Windows.Forms.Timer]::new()
$script:DisplayPowerTimer.Interval = 500

function Set-BlackoutCursorVisible {
    param([bool]$Visible)
    if ($Visible -and -not $script:CursorShown) {
        [System.Windows.Forms.Cursor]::Show()
        $script:CursorShown = $true
    }
    elseif (-not $Visible -and $script:CursorShown) {
        [System.Windows.Forms.Cursor]::Hide()
        $script:CursorShown = $false
    }
}

function Restart-CursorIdleTimer {
    $script:CursorIdleTimer.Stop()
    if ($script:IsBlackoutActive) {
        $script:CursorIdleTimer.Start()
    }
}

function Schedule-DisplayPowerOff {
    $script:DisplayPowerTimer.Stop()
    if ($script:IsBlackoutActive -and -not $script:ControlPanelVisible) {
        # 给窗口绘制和按钮点击留出时间，再请求 Windows 关闭显示器。
        $script:DisplayPowerTimer.Start()
    }
}

function Enable-DarkWindowFrame {
    param([System.Windows.Forms.Form]$Form)
    if (-not $Form.IsHandleCreated) {
        [void]$Form.Handle
    }
    $enabled = 1
    # DWMWA_USE_IMMERSIVE_DARK_MODE is 20 on current Windows 11 builds.
    # Attribute 19 covers earlier compatible builds.
    $result = [BlackScreenGuardNative]::DwmSetWindowAttribute(
        $Form.Handle,
        20,
        [ref]$enabled,
        4
    )
    if ($result -ne 0) {
        [void][BlackScreenGuardNative]::DwmSetWindowAttribute(
            $Form.Handle,
            19,
            [ref]$enabled,
            4
        )
    }
}

function New-Label {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [float]$Size = 10,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular,
        [System.Drawing.Color]$Color = [System.Drawing.Color]::FromArgb(226, 232, 240)
    )
    $label = [System.Windows.Forms.Label]::new()
    $label.Text = $Text
    $label.Location = [System.Drawing.Point]::new($X, $Y)
    $label.Size = [System.Drawing.Size]::new($Width, $Height)
    $label.Font = [System.Drawing.Font]::new('Microsoft YaHei UI', $Size, $Style)
    $label.ForeColor = $Color
    $label.BackColor = [System.Drawing.Color]::Transparent
    return $label
}

function New-Button {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height)
    $button = [System.Windows.Forms.Button]::new()
    $button.Text = $Text
    $button.Location = [System.Drawing.Point]::new($X, $Y)
    $button.Size = [System.Drawing.Size]::new($Width, $Height)
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0
    $button.Font = [System.Drawing.Font]::new('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $button
}

function Set-ControlPanelVisibility {
    param([bool]$Visible)
    $script:ControlPanelVisible = $Visible
    $script:ControlPanelTimer.Stop()
    foreach ($window in $script:BlackWindows) {
        $panel = $window.Controls['ActionPanel']
        if ($null -ne $panel) {
            $panel.Visible = $Visible
            if ($Visible) { $panel.BringToFront() }
        }
    }
    if ($Visible) {
        $script:ControlPanelTimer.Start()
    }
    elseif ($script:IsBlackoutActive) {
        # 隐藏面板时进入全新的纯黑状态，避免点击产生的细小位移
        # 继续沿用旧基准而立即再次触发控制面板。
        $script:CursorIdleTimer.Stop()
        $script:StartMousePosition = [System.Windows.Forms.Cursor]::Position
        $script:SuppressCursorRevealUntil = (Get-Date).AddMilliseconds(500)
        Set-BlackoutCursorVisible $false
        Schedule-DisplayPowerOff
    }
}

function Stop-Blackout {
    $script:ControlPanelTimer.Stop()
    $script:CursorIdleTimer.Stop()
    $script:DisplayPowerTimer.Stop()
    $script:IsBlackoutActive = $false
    # 确保通过 Esc 或其他程序化路径退出时显示器恢复。
    [void][BlackScreenGuardNative]::RequestDisplayPower(-1)
    Set-BlackoutCursorVisible $true
    foreach ($window in @($script:BlackWindows)) {
        $window.Close()
        $window.Dispose()
    }
    $script:BlackWindows.Clear()
    [void][BlackScreenGuardNative]::SetThreadExecutionState([BlackScreenGuardNative]::ES_CONTINUOUS)
    $script:MainForm.Show()
    $script:MainForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $script:MainForm.Activate()
    $script:StateValue.Text = '未运行'
    $script:StateValue.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
    $script:StartTimeValue.Text = '—'
    $script:DurationValue.Text = '00:00:00'
    $script:StartButton.Enabled = $true
}

function Test-ActivationGesture {
    param([System.Windows.Forms.MouseEventArgs]$EventArgs)
    if ((Get-Date) -lt $script:SuppressCursorRevealUntil) {
        return
    }
    Restart-CursorIdleTimer
    if (-not $script:CursorShown) {
        Set-BlackoutCursorVisible $true
        $script:StartMousePosition = [System.Windows.Forms.Cursor]::Position
        if ($EventArgs.Button -eq [System.Windows.Forms.MouseButtons]::None) {
            return
        }
    }

    $current = [System.Windows.Forms.Cursor]::Position
    $dx = $current.X - $script:StartMousePosition.X
    $dy = $current.Y - $script:StartMousePosition.Y
    $distanceSquared = ($dx * $dx) + ($dy * $dy)
    if ($EventArgs.Button -ne [System.Windows.Forms.MouseButtons]::None -or $distanceSquared -ge 900) {
        Set-ControlPanelVisibility $true
    }
}

function New-BlackWindow {
    param([System.Windows.Forms.Screen]$Screen, [bool]$Primary)

    $window = [System.Windows.Forms.Form]::new()
    $window.Name = 'BlackScreenGuardBlackout'
    $window.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $window.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $window.Bounds = $Screen.Bounds
    $window.BackColor = [System.Drawing.Color]::Black
    $window.TopMost = $true
    $window.ShowInTaskbar = $false
    $window.KeyPreview = $true

    $panel = [System.Windows.Forms.Panel]::new()
    $panel.Name = 'ActionPanel'
    $panel.Size = [System.Drawing.Size]::new(330, 145)
    $panel.Location = [System.Drawing.Point]::new(
        [Math]::Max(0, [int](($Screen.Bounds.Width - $panel.Width) / 2)),
        [Math]::Max(0, [int](($Screen.Bounds.Height - $panel.Height) / 2))
    )
    $panel.BackColor = [System.Drawing.Color]::FromArgb(32, 36, 44)
    $panel.Visible = $false

    $hint = New-Label -Text '黑屏守护中' -X 20 -Y 18 -Width 290 -Height 28 -Size 13 -Style Bold -Color ([System.Drawing.Color]::White)
    $continueButton = New-Button -Text '继续黑屏' -X 20 -Y 70 -Width 135 -Height 48
    $continueButton.BackColor = [System.Drawing.Color]::FromArgb(55, 65, 81)
    $continueButton.ForeColor = [System.Drawing.Color]::White
    $exitButton = New-Button -Text '退出程序' -X 175 -Y 70 -Width 135 -Height 48
    $exitButton.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
    $exitButton.ForeColor = [System.Drawing.Color]::White
    $continueButton.Add_Click({ Set-ControlPanelVisibility $false })
    $exitButton.Add_Click({ $script:MainForm.Close() })
    $panel.Controls.AddRange(@($hint, $continueButton, $exitButton))
    $window.Controls.Add($panel)

    $window.Add_MouseMove({ param($sender, $eventArgs) Test-ActivationGesture $eventArgs })
    $window.Add_MouseDown({ param($sender, $eventArgs) Test-ActivationGesture $eventArgs })
    $window.Add_KeyDown({
        param($sender, $eventArgs)
        $eventArgs.SuppressKeyPress = $true
        $eventArgs.Handled = $true
        if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            $script:MainForm.Close()
        }
        else {
            Schedule-DisplayPowerOff
        }
    })
    $window.Add_Deactivate({
        param($sender, $eventArgs)
        if ($script:IsBlackoutActive) {
            $sender.TopMost = $true
            $sender.Activate()
        }
    })
    return $window
}

function Start-Blackout {
    if ($script:IsBlackoutActive) { return }
    $script:IsBlackoutActive = $true
    $script:SessionStartedAt = Get-Date
    $script:StartMousePosition = [System.Windows.Forms.Cursor]::Position
    $script:SuppressCursorRevealUntil = [DateTime]::MinValue
    # 会话开始前 Windows 指针处于可见状态，随后统一隐藏一次。
    $script:CursorShown = $true
    $script:ControlPanelVisible = $false
    $script:StartButton.Enabled = $false
    $script:StateValue.Text = '正在保护'
    $script:StateValue.ForeColor = [System.Drawing.Color]::FromArgb(22, 163, 74)
    $script:StartTimeValue.Text = $script:SessionStartedAt.ToString('yyyy-MM-dd HH:mm:ss')

    # 保持系统和后台任务运行，但不再使用 ES_DISPLAY_REQUIRED 保持背光开启。
    $flags = [BlackScreenGuardNative]::ES_CONTINUOUS -bor
             [BlackScreenGuardNative]::ES_SYSTEM_REQUIRED
    [void][BlackScreenGuardNative]::SetThreadExecutionState($flags)

    foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
        $window = New-BlackWindow -Screen $screen -Primary $screen.Primary
        $script:BlackWindows.Add($window)
    }

    $script:MainForm.Hide()
    Set-BlackoutCursorVisible $false
    foreach ($window in $script:BlackWindows) {
        $window.Show()
        $window.BringToFront()
    }
    $primaryWindow = $script:BlackWindows | Where-Object {
        $_.Bounds.Contains([System.Windows.Forms.Cursor]::Position)
    } | Select-Object -First 1
    if ($null -eq $primaryWindow) { $primaryWindow = $script:BlackWindows[0] }
    $primaryWindow.Activate()
    Schedule-DisplayPowerOff
}

$script:ControlPanelTimer.Add_Tick({ Set-ControlPanelVisibility $false })
$script:CursorIdleTimer.Add_Tick({
    $script:CursorIdleTimer.Stop()
    if ($script:IsBlackoutActive) {
        Set-BlackoutCursorVisible $false
        Schedule-DisplayPowerOff
    }
})
$script:DisplayPowerTimer.Add_Tick({
    $script:DisplayPowerTimer.Stop()
    if ($script:IsBlackoutActive -and -not $script:ControlPanelVisible) {
        # state 2 对应 SC_MONITORPOWER 的“关闭显示器”。电脑本身仍保持唤醒。
        [void][BlackScreenGuardNative]::RequestDisplayPower(2)
    }
})

$script:MainForm = [System.Windows.Forms.Form]::new()
$script:MainForm.Text = 'BlackScreen Guard｜黑屏守护'
$appIconCandidates = @(
    (Join-Path $PSScriptRoot 'BlackScreenGuard.ico'),
    (Join-Path $PSScriptRoot 'assets\BlackScreenGuard.ico')
)
$appIconPath = $appIconCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($null -ne $appIconPath) {
    $script:MainForm.Icon = [System.Drawing.Icon]::new($appIconPath)
}
$script:MainForm.ClientSize = [System.Drawing.Size]::new(760, 650)
$script:MainForm.MinimumSize = [System.Drawing.Size]::new(776, 689)
$script:MainForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$script:MainForm.BackColor = [System.Drawing.Color]::FromArgb(9, 13, 21)
$script:MainForm.Font = [System.Drawing.Font]::new('Microsoft YaHei UI', 10)

$title = New-Label -Text 'BlackScreen Guard｜黑屏守护' -X 42 -Y 32 -Width 650 -Height 42 -Size 21 -Style Bold -Color ([System.Drawing.Color]::FromArgb(248, 250, 252))
$subtitle = New-Label -Text '适用于 Windows 11 的显示器熄屏保护工具。请求关闭显示器背光，并用纯黑遮罩保护唤醒画面；电脑和后台程序仍保持运行，也可维持现有远程连接所需的运行环境。' -X 45 -Y 78 -Width 650 -Height 52 -Size 9 -Color ([System.Drawing.Color]::FromArgb(148, 163, 184))

$statusCard = [System.Windows.Forms.Panel]::new()
$statusCard.Location = [System.Drawing.Point]::new(42, 145)
$statusCard.Size = [System.Drawing.Size]::new(676, 200)
$statusCard.BackColor = [System.Drawing.Color]::FromArgb(18, 25, 38)

$statusHeading = New-Label -Text '运行状态' -X 24 -Y 20 -Width 160 -Height 28 -Size 12 -Style Bold
$stateLabel = New-Label -Text '状态' -X 24 -Y 72 -Width 120 -Height 24 -Color ([System.Drawing.Color]::FromArgb(148, 163, 184))
$script:StateValue = New-Label -Text '未运行' -X 165 -Y 72 -Width 180 -Height 24 -Style Bold -Color ([System.Drawing.Color]::FromArgb(148, 163, 184))
$startLabel = New-Label -Text '开始时间' -X 350 -Y 72 -Width 120 -Height 24 -Color ([System.Drawing.Color]::FromArgb(148, 163, 184))
$script:StartTimeValue = New-Label -Text '—' -X 470 -Y 72 -Width 190 -Height 24 -Style Bold
$durationLabel = New-Label -Text '当前黑屏持续时间' -X 24 -Y 125 -Width 140 -Height 24 -Color ([System.Drawing.Color]::FromArgb(148, 163, 184))
$script:DurationValue = New-Label -Text '00:00:00' -X 165 -Y 125 -Width 180 -Height 24 -Size 12 -Style Bold
$displayLabel = New-Label -Text '覆盖显示器' -X 350 -Y 125 -Width 120 -Height 24 -Color ([System.Drawing.Color]::FromArgb(148, 163, 184))
$displayValue = New-Label -Text ("{0} 台" -f [System.Windows.Forms.Screen]::AllScreens.Count) -X 470 -Y 125 -Width 160 -Height 24 -Style Bold
$statusCard.Controls.AddRange(@($statusHeading, $stateLabel, $script:StateValue, $startLabel, $script:StartTimeValue, $durationLabel, $script:DurationValue, $displayLabel, $displayValue))

$settingsCard = [System.Windows.Forms.Panel]::new()
$settingsCard.Location = [System.Drawing.Point]::new(42, 365)
$settingsCard.Size = [System.Drawing.Size]::new(676, 160)
$settingsCard.BackColor = [System.Drawing.Color]::FromArgb(18, 25, 38)
$settingsHeading = New-Label -Text '保护设置' -X 24 -Y 18 -Width 160 -Height 28 -Size 12 -Style Bold
$sleepStatus = New-Label -Text '●  已阻止系统休眠' -X 24 -Y 65 -Width 250 -Height 25 -Color ([System.Drawing.Color]::FromArgb(74, 222, 128))
$displayStatus = New-Label -Text '●  启动后请求关闭显示器背光' -X 335 -Y 65 -Width 280 -Height 25 -Color ([System.Drawing.Color]::FromArgb(74, 222, 128))
$gestureHint = New-Label -Text '轻移显示鼠标；移动约 30 像素或单击显示控制面板；Esc 退出。' -X 24 -Y 112 -Width 620 -Height 25 -Size 9 -Color ([System.Drawing.Color]::FromArgb(148, 163, 184))
$settingsCard.Controls.AddRange(@($settingsHeading, $sleepStatus, $displayStatus, $gestureHint))

$script:StartButton = New-Button -Text '开始' -X 42 -Y 550 -Width 676 -Height 54
$script:StartButton.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$script:StartButton.ForeColor = [System.Drawing.Color]::White
$script:StartButton.Add_Click({ Start-Blackout })

$statusTimer = [System.Windows.Forms.Timer]::new()
$statusTimer.Interval = 1000
$statusTimer.Add_Tick({
    if ($script:IsBlackoutActive -and $null -ne $script:SessionStartedAt) {
        $elapsed = (Get-Date) - $script:SessionStartedAt
        $script:DurationValue.Text = '{0:00}:{1:00}:{2:00}' -f [int]$elapsed.TotalHours, $elapsed.Minutes, $elapsed.Seconds
    }
})
$statusTimer.Start()

$script:MainForm.Controls.AddRange(@($title, $subtitle, $statusCard, $settingsCard, $script:StartButton))
$script:MainForm.Add_Shown({ Enable-DarkWindowFrame $script:MainForm })
$script:MainForm.Add_FormClosing({
    if ($script:IsBlackoutActive) { Stop-Blackout }
    [void][BlackScreenGuardNative]::SetThreadExecutionState([BlackScreenGuardNative]::ES_CONTINUOUS)
})

if ($CaptureScreenshots) {
    $screenshotDirectory = Join-Path $PSScriptRoot 'assets\screenshots'
    [System.IO.Directory]::CreateDirectory($screenshotDirectory) | Out-Null

    $script:MainForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $script:MainForm.Location = [System.Drawing.Point]::new(-20000, -20000)
    $script:MainForm.Show()
    [System.Windows.Forms.Application]::DoEvents()
    Enable-DarkWindowFrame $script:MainForm
    $controlBitmap = [System.Drawing.Bitmap]::new(
        $script:MainForm.ClientSize.Width,
        $script:MainForm.ClientSize.Height
    )
    $controlGraphics = [System.Drawing.Graphics]::FromImage($controlBitmap)
    $controlGraphics.Clear($script:MainForm.BackColor)
    foreach ($control in $script:MainForm.Controls) {
        $control.DrawToBitmap($controlBitmap, $control.Bounds)
    }
    $controlGraphics.Dispose()
    $controlBitmap.Save(
        (Join-Path $screenshotDirectory 'control-page.png'),
        [System.Drawing.Imaging.ImageFormat]::Png
    )
    $controlBitmap.Dispose()
    $script:MainForm.Hide()

    $previewWindow = New-BlackWindow -Screen ([System.Windows.Forms.Screen]::PrimaryScreen) -Primary $true
    $previewWindow.Location = [System.Drawing.Point]::new(-20000, -20000)
    $previewWindow.Size = [System.Drawing.Size]::new(1280, 720)
    $previewPanel = $previewWindow.Controls['ActionPanel']
    $previewPanel.Location = [System.Drawing.Point]::new(
        [int](($previewWindow.ClientSize.Width - $previewPanel.Width) / 2),
        [int](($previewWindow.ClientSize.Height - $previewPanel.Height) / 2)
    )
    $previewPanel.Visible = $true
    $previewWindow.Show()
    [System.Windows.Forms.Application]::DoEvents()
    $blackoutBitmap = [System.Drawing.Bitmap]::new(1280, 720)
    $previewWindow.DrawToBitmap(
        $blackoutBitmap,
        [System.Drawing.Rectangle]::new(0, 0, 1280, 720)
    )
    $blackoutBitmap.Save(
        (Join-Path $screenshotDirectory 'blackout-control.png'),
        [System.Drawing.Imaging.ImageFormat]::Png
    )
    $blackoutBitmap.Dispose()
    $previewWindow.Dispose()

    $statusTimer.Dispose()
    $script:ControlPanelTimer.Dispose()
    $script:CursorIdleTimer.Dispose()
    $script:DisplayPowerTimer.Dispose()
    $script:MainForm.Dispose()
    return
}

if ($SelfTest) {
    Write-Output ('BlackScreen Guard self-test: OK ({0} display(s) detected)' -f [System.Windows.Forms.Screen]::AllScreens.Count)
    $statusTimer.Dispose()
    $script:ControlPanelTimer.Dispose()
    $script:CursorIdleTimer.Dispose()
    $script:DisplayPowerTimer.Dispose()
    $script:MainForm.Dispose()
    return
}

[System.Windows.Forms.Application]::Run($script:MainForm)
