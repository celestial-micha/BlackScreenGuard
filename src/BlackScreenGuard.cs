using System;
using System.Collections.Generic;
using System.Drawing;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;

[assembly: AssemblyTitle("BlackScreen Guard")]
[assembly: AssemblyDescription("BlackScreen Guard for Windows 11")]
[assembly: AssemblyCompany("celestial-micha")]
[assembly: AssemblyProduct("BlackScreen Guard")]
[assembly: AssemblyCopyright("Copyright © celestial-micha 2026")]
[assembly: AssemblyVersion("1.0.4.0")]
[assembly: AssemblyFileVersion("1.0.4.0")]
[assembly: AssemblyInformationalVersion("1.0.4")]

namespace BlackScreenGuardApp
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            if (HasArgument(args, "--self-test") || HasArgument(args, "-SelfTest"))
            {
                using (MainForm form = new MainForm())
                {
                    return form.RunSelfTest() ? 0 : 1;
                }
            }

            Application.ThreadException += delegate(object sender, System.Threading.ThreadExceptionEventArgs e)
            {
                ShowFatalError(e.Exception);
            };

            AppDomain.CurrentDomain.UnhandledException += delegate(object sender, UnhandledExceptionEventArgs e)
            {
                Exception exception = e.ExceptionObject as Exception;
                ShowFatalError(exception ?? new InvalidOperationException("Unknown fatal error."));
            };

            Application.Run(new MainForm());
            return 0;
        }

        private static bool HasArgument(string[] args, string expected)
        {
            foreach (string argument in args)
            {
                if (string.Equals(argument, expected, StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }
            return false;
        }

        private static void ShowFatalError(Exception exception)
        {
            try
            {
                NativeMethods.RequestDisplayPower(-1);
                NativeMethods.SetThreadExecutionState(ExecutionState.Continuous);
                MessageBox.Show(
                    "BlackScreen Guard 遇到错误并已尝试恢复显示器：\r\n\r\n" + exception.Message,
                    "BlackScreen Guard",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error
                );
            }
            catch
            {
                // Avoid recursively failing while handling a fatal exception.
            }
        }
    }

    [Flags]
    internal enum ExecutionState : uint
    {
        SystemRequired = 0x00000001,
        DisplayRequired = 0x00000002,
        Continuous = 0x80000000
    }

    internal static class NativeMethods
    {
        private static readonly IntPtr HwndBroadcast = new IntPtr(0xffff);

        private const uint WmSysCommand = 0x0112;
        private const uint ScMonitorPower = 0xF170;
        private const uint SmtoAbortIfHung = 0x0002;

        [DllImport("kernel32.dll")]
        internal static extern ExecutionState SetThreadExecutionState(ExecutionState flags);

        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(
            IntPtr window,
            int attribute,
            ref int value,
            int valueSize
        );

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SendMessageTimeout(
            IntPtr window,
            uint message,
            UIntPtr wParam,
            IntPtr lParam,
            uint flags,
            uint timeout,
            out UIntPtr result
        );

        internal static bool RequestDisplayPower(int state)
        {
            UIntPtr result;
            return SendMessageTimeout(
                HwndBroadcast,
                WmSysCommand,
                new UIntPtr(ScMonitorPower),
                new IntPtr(state),
                SmtoAbortIfHung,
                1000,
                out result
            ) != IntPtr.Zero;
        }

        internal static void EnableDarkWindowFrame(Form form)
        {
            if (!form.IsHandleCreated)
            {
                IntPtr ignored = form.Handle;
            }

            int enabled = 1;
            int result = DwmSetWindowAttribute(form.Handle, 20, ref enabled, sizeof(int));
            if (result != 0)
            {
                DwmSetWindowAttribute(form.Handle, 19, ref enabled, sizeof(int));
            }
        }
    }

    internal sealed class MainForm : Form
    {
        private static readonly Color WindowBackground = Color.FromArgb(9, 13, 21);
        private static readonly Color CardBackground = Color.FromArgb(18, 25, 38);
        private static readonly Color PrimaryText = Color.FromArgb(226, 232, 240);
        private static readonly Color MutedText = Color.FromArgb(148, 163, 184);
        private static readonly Color SuccessText = Color.FromArgb(74, 222, 128);

        private readonly List<BlackoutForm> blackoutWindows = new List<BlackoutForm>();
        private readonly Timer statusTimer = new Timer();
        private readonly Timer controlPanelTimer = new Timer();
        private readonly Timer cursorIdleTimer = new Timer();
        private readonly Timer displayPowerTimer = new Timer();

        private Label stateValue;
        private Label startTimeValue;
        private Label durationValue;
        private Button startButton;

        private bool blackoutActive;
        private bool cursorShown;
        private bool controlPanelVisible;
        private DateTime sessionStartedAt;
        private DateTime suppressCursorRevealUntil = DateTime.MinValue;
        private Point startMousePosition = Point.Empty;

        internal MainForm()
        {
            Text = "BlackScreen Guard｜黑屏守护";
            ClientSize = new Size(760, 650);
            MinimumSize = new Size(776, 689);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = WindowBackground;
            Font = new Font("Microsoft YaHei UI", 10.0f, FontStyle.Regular);

            try
            {
                Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            }
            catch
            {
                // The executable still runs if Windows cannot load its icon.
            }

            BuildInterface();
            ConfigureTimers();

            Shown += delegate { NativeMethods.EnableDarkWindowFrame(this); };
            FormClosing += delegate
            {
                StopBlackout();
                NativeMethods.SetThreadExecutionState(ExecutionState.Continuous);
            };
        }

        internal bool RunSelfTest()
        {
            return Screen.AllScreens.Length > 0 &&
                   stateValue != null &&
                   startButton != null &&
                   !blackoutActive;
        }

        internal bool IsBlackoutActive
        {
            get { return blackoutActive; }
        }

        internal void ContinueBlackout()
        {
            SetControlPanelVisible(false);
        }

        internal void ExitApplication()
        {
            Close();
        }

        internal void HandleActivationGesture(MouseEventArgs eventArgs)
        {
            if (DateTime.UtcNow < suppressCursorRevealUntil)
            {
                return;
            }

            RestartCursorIdleTimer();

            if (!cursorShown)
            {
                SetBlackoutCursorVisible(true);
                startMousePosition = Cursor.Position;
                if (eventArgs.Button == MouseButtons.None)
                {
                    return;
                }
            }

            Point current = Cursor.Position;
            long deltaX = current.X - startMousePosition.X;
            long deltaY = current.Y - startMousePosition.Y;
            long distanceSquared = (deltaX * deltaX) + (deltaY * deltaY);

            if (eventArgs.Button != MouseButtons.None || distanceSquared >= 900)
            {
                SetControlPanelVisible(true);
            }
        }

        internal void HandleBlackoutKey(KeyEventArgs eventArgs)
        {
            eventArgs.SuppressKeyPress = true;
            eventArgs.Handled = true;

            if (eventArgs.KeyCode == Keys.Escape)
            {
                Close();
            }
            else
            {
                ScheduleDisplayPowerOff();
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                statusTimer.Dispose();
                controlPanelTimer.Dispose();
                cursorIdleTimer.Dispose();
                displayPowerTimer.Dispose();
            }
            base.Dispose(disposing);
        }

        private void BuildInterface()
        {
            Label title = CreateLabel(
                "BlackScreen Guard｜黑屏守护",
                42,
                32,
                650,
                42,
                21.0f,
                FontStyle.Bold,
                Color.FromArgb(248, 250, 252)
            );

            Label subtitle = CreateLabel(
                "适用于 Windows 11 的显示器熄屏保护工具。请求关闭显示器背光，并用纯黑遮罩保护唤醒画面；电脑和后台程序仍保持运行，也可维持现有远程连接所需的运行环境。",
                45,
                78,
                650,
                52,
                9.0f,
                FontStyle.Regular,
                MutedText
            );

            Panel statusCard = CreateCard(42, 145, 676, 200);
            Label statusHeading = CreateLabel("运行状态", 24, 20, 160, 28, 12.0f, FontStyle.Bold, PrimaryText);
            Label stateLabel = CreateLabel("状态", 24, 72, 120, 24, 10.0f, FontStyle.Regular, MutedText);
            stateValue = CreateLabel("未运行", 165, 72, 180, 24, 10.0f, FontStyle.Bold, MutedText);
            Label startLabel = CreateLabel("开始时间", 350, 72, 120, 24, 10.0f, FontStyle.Regular, MutedText);
            startTimeValue = CreateLabel("—", 470, 72, 190, 24, 10.0f, FontStyle.Bold, PrimaryText);
            Label durationLabel = CreateLabel("当前黑屏持续时间", 24, 125, 140, 24, 10.0f, FontStyle.Regular, MutedText);
            durationValue = CreateLabel("00:00:00", 165, 125, 180, 24, 12.0f, FontStyle.Bold, PrimaryText);
            Label displayLabel = CreateLabel("覆盖显示器", 350, 125, 120, 24, 10.0f, FontStyle.Regular, MutedText);
            Label displayValue = CreateLabel(
                string.Format("{0} 台", Screen.AllScreens.Length),
                470,
                125,
                160,
                24,
                10.0f,
                FontStyle.Bold,
                PrimaryText
            );

            statusCard.Controls.AddRange(new Control[]
            {
                statusHeading,
                stateLabel,
                stateValue,
                startLabel,
                startTimeValue,
                durationLabel,
                durationValue,
                displayLabel,
                displayValue
            });

            Panel settingsCard = CreateCard(42, 365, 676, 160);
            Label settingsHeading = CreateLabel("保护设置", 24, 18, 160, 28, 12.0f, FontStyle.Bold, PrimaryText);
            Label sleepStatus = CreateLabel("●  已阻止系统休眠", 24, 65, 250, 25, 10.0f, FontStyle.Regular, SuccessText);
            Label displayStatus = CreateLabel("●  启动后请求关闭显示器背光", 335, 65, 280, 25, 10.0f, FontStyle.Regular, SuccessText);
            Label gestureHint = CreateLabel(
                "轻移显示鼠标；移动约 30 像素或单击显示控制面板；Esc 退出。",
                24,
                112,
                620,
                25,
                9.0f,
                FontStyle.Regular,
                MutedText
            );
            settingsCard.Controls.AddRange(new Control[] { settingsHeading, sleepStatus, displayStatus, gestureHint });

            startButton = CreateButton("开始", 42, 550, 676, 54);
            startButton.BackColor = Color.FromArgb(37, 99, 235);
            startButton.ForeColor = Color.White;
            startButton.Click += delegate { StartBlackout(); };

            Controls.AddRange(new Control[] { title, subtitle, statusCard, settingsCard, startButton });
        }

        private void ConfigureTimers()
        {
            statusTimer.Interval = 1000;
            statusTimer.Tick += delegate
            {
                if (!blackoutActive)
                {
                    return;
                }

                TimeSpan elapsed = DateTime.Now - sessionStartedAt;
                durationValue.Text = string.Format(
                    "{0:00}:{1:00}:{2:00}",
                    (int)elapsed.TotalHours,
                    elapsed.Minutes,
                    elapsed.Seconds
                );
            };
            statusTimer.Start();

            controlPanelTimer.Interval = 2000;
            controlPanelTimer.Tick += delegate { SetControlPanelVisible(false); };

            cursorIdleTimer.Interval = 2000;
            cursorIdleTimer.Tick += delegate
            {
                cursorIdleTimer.Stop();
                if (blackoutActive)
                {
                    SetBlackoutCursorVisible(false);
                    ScheduleDisplayPowerOff();
                }
            };

            displayPowerTimer.Interval = 500;
            displayPowerTimer.Tick += delegate
            {
                displayPowerTimer.Stop();
                if (blackoutActive && !controlPanelVisible)
                {
                    NativeMethods.RequestDisplayPower(2);
                }
            };
        }

        private void StartBlackout()
        {
            if (blackoutActive)
            {
                return;
            }

            blackoutActive = true;
            sessionStartedAt = DateTime.Now;
            startMousePosition = Cursor.Position;
            suppressCursorRevealUntil = DateTime.MinValue;
            cursorShown = true;
            controlPanelVisible = false;
            startButton.Enabled = false;
            stateValue.Text = "正在保护";
            stateValue.ForeColor = Color.FromArgb(22, 163, 74);
            startTimeValue.Text = sessionStartedAt.ToString("yyyy-MM-dd HH:mm:ss");

            NativeMethods.SetThreadExecutionState(
                ExecutionState.Continuous | ExecutionState.SystemRequired
            );

            foreach (Screen screen in Screen.AllScreens)
            {
                blackoutWindows.Add(new BlackoutForm(this, screen));
            }

            Hide();
            SetBlackoutCursorVisible(false);

            foreach (BlackoutForm window in blackoutWindows)
            {
                window.Show();
                window.BringToFront();
            }

            BlackoutForm primaryWindow = null;
            foreach (BlackoutForm window in blackoutWindows)
            {
                if (window.Bounds.Contains(Cursor.Position))
                {
                    primaryWindow = window;
                    break;
                }
            }

            if (primaryWindow == null && blackoutWindows.Count > 0)
            {
                primaryWindow = blackoutWindows[0];
            }

            if (primaryWindow != null)
            {
                primaryWindow.Activate();
            }

            ScheduleDisplayPowerOff();
        }

        private void StopBlackout()
        {
            controlPanelTimer.Stop();
            cursorIdleTimer.Stop();
            displayPowerTimer.Stop();

            if (!blackoutActive && blackoutWindows.Count == 0)
            {
                return;
            }

            blackoutActive = false;
            NativeMethods.RequestDisplayPower(-1);
            SetBlackoutCursorVisible(true);

            BlackoutForm[] windows = blackoutWindows.ToArray();
            blackoutWindows.Clear();
            foreach (BlackoutForm window in windows)
            {
                window.Close();
                window.Dispose();
            }

            NativeMethods.SetThreadExecutionState(ExecutionState.Continuous);
        }

        private void SetControlPanelVisible(bool visible)
        {
            controlPanelVisible = visible;
            controlPanelTimer.Stop();

            foreach (BlackoutForm window in blackoutWindows)
            {
                window.SetActionPanelVisible(visible);
            }

            if (visible)
            {
                controlPanelTimer.Start();
            }
            else if (blackoutActive)
            {
                cursorIdleTimer.Stop();
                startMousePosition = Cursor.Position;
                suppressCursorRevealUntil = DateTime.UtcNow.AddMilliseconds(500);
                SetBlackoutCursorVisible(false);
                ScheduleDisplayPowerOff();
            }
        }

        private void ScheduleDisplayPowerOff()
        {
            displayPowerTimer.Stop();
            if (blackoutActive && !controlPanelVisible)
            {
                displayPowerTimer.Start();
            }
        }

        private void RestartCursorIdleTimer()
        {
            cursorIdleTimer.Stop();
            if (blackoutActive)
            {
                cursorIdleTimer.Start();
            }
        }

        private void SetBlackoutCursorVisible(bool visible)
        {
            if (visible && !cursorShown)
            {
                Cursor.Show();
                cursorShown = true;
            }
            else if (!visible && cursorShown)
            {
                Cursor.Hide();
                cursorShown = false;
            }
        }

        internal static Label CreateLabel(
            string text,
            int x,
            int y,
            int width,
            int height,
            float size,
            FontStyle style,
            Color color
        )
        {
            Label label = new Label();
            label.Text = text;
            label.Location = new Point(x, y);
            label.Size = new Size(width, height);
            label.Font = new Font("Microsoft YaHei UI", size, style);
            label.ForeColor = color;
            label.BackColor = Color.Transparent;
            return label;
        }

        internal static Button CreateButton(string text, int x, int y, int width, int height)
        {
            Button button = new Button();
            button.Text = text;
            button.Location = new Point(x, y);
            button.Size = new Size(width, height);
            button.FlatStyle = FlatStyle.Flat;
            button.FlatAppearance.BorderSize = 0;
            button.Font = new Font("Microsoft YaHei UI", 10.0f, FontStyle.Bold);
            button.Cursor = Cursors.Hand;
            button.UseVisualStyleBackColor = false;
            return button;
        }

        private static Panel CreateCard(int x, int y, int width, int height)
        {
            Panel panel = new Panel();
            panel.Location = new Point(x, y);
            panel.Size = new Size(width, height);
            panel.BackColor = CardBackground;
            return panel;
        }
    }

    internal sealed class BlackoutForm : Form
    {
        private readonly MainForm owner;
        private readonly Panel actionPanel;

        internal BlackoutForm(MainForm owner, Screen screen)
        {
            this.owner = owner;

            Name = "BlackScreenGuardBlackout";
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            Bounds = screen.Bounds;
            BackColor = Color.Black;
            TopMost = true;
            ShowInTaskbar = false;
            KeyPreview = true;

            actionPanel = new Panel();
            actionPanel.Name = "ActionPanel";
            actionPanel.Size = new Size(330, 145);
            actionPanel.Location = new Point(
                Math.Max(0, (screen.Bounds.Width - actionPanel.Width) / 2),
                Math.Max(0, (screen.Bounds.Height - actionPanel.Height) / 2)
            );
            actionPanel.BackColor = Color.FromArgb(32, 36, 44);
            actionPanel.Visible = false;

            Label hint = MainForm.CreateLabel(
                "黑屏守护中",
                20,
                18,
                290,
                28,
                13.0f,
                FontStyle.Bold,
                Color.White
            );

            Button continueButton = MainForm.CreateButton("继续黑屏", 20, 70, 135, 48);
            continueButton.BackColor = Color.FromArgb(55, 65, 81);
            continueButton.ForeColor = Color.White;
            continueButton.Click += delegate { owner.ContinueBlackout(); };

            Button exitButton = MainForm.CreateButton("退出程序", 175, 70, 135, 48);
            exitButton.BackColor = Color.FromArgb(37, 99, 235);
            exitButton.ForeColor = Color.White;
            exitButton.Click += delegate { owner.ExitApplication(); };

            actionPanel.Controls.AddRange(new Control[] { hint, continueButton, exitButton });
            Controls.Add(actionPanel);

            MouseMove += delegate(object sender, MouseEventArgs e) { owner.HandleActivationGesture(e); };
            MouseDown += delegate(object sender, MouseEventArgs e) { owner.HandleActivationGesture(e); };
            KeyDown += delegate(object sender, KeyEventArgs e) { owner.HandleBlackoutKey(e); };
            Deactivate += delegate
            {
                if (owner.IsBlackoutActive)
                {
                    TopMost = true;
                    Activate();
                }
            };
        }

        internal void SetActionPanelVisible(bool visible)
        {
            actionPanel.Visible = visible;
            if (visible)
            {
                actionPanel.BringToFront();
            }
        }
    }
}
