using BossRemote.Core;

namespace BossRemote.Windows;

internal sealed class MainForm : Form
{
    private readonly string configPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "BossRemote",
        "config.json");

    private readonly AppSettings settings;
    private readonly MappingStore mappings;
    private readonly HistoryStore history;
    private readonly BatteryInsights battery = new();
    private readonly ReportRouter router = new();
    private readonly InputPipeline pipeline;
    private readonly HidSession hid = new();
    private readonly GattBridge gatt = new();
    private readonly RemoteRelay relay = new();
    private readonly Dictionary<string, HidReportLayout?> layouts = [];
    private readonly Dictionary<string, int> loggedReports = [];
    private readonly SendInputSink sink = new();
    private readonly PadView pad = new() { Width = 180, Height = 180, Dock = DockStyle.Left };
    private readonly Label banner = new() { Dock = DockStyle.Top, Height = 48, Padding = new Padding(12, 8, 12, 4) };
    private readonly Label connection = new() { AutoSize = true };
    private readonly Label batteryLabel = new() { AutoSize = true };
    private readonly Label foregroundLabel = new() { AutoSize = true };
    private readonly TextBox logBox = new() { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, Font = new Font(FontFamily.GenericMonospace, 9) };
    private readonly ListBox controls = new() { Dock = DockStyle.Fill };
    private readonly ComboBox scope = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 280 };
    private readonly ComboBox pressAction = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 360 };
    private readonly ComboBox holdAction = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 360 };
    private readonly ListBox historyList = new() { Dock = DockStyle.Fill };
    private readonly NotifyIcon tray;
    private readonly System.Windows.Forms.Timer clock;
    private bool loadingUi;
    private bool exitRequested;
    private int voiceFrames;
    private int interfaceCount;
    private string? foregroundPath;

    public MainForm()
    {
        var loaded = ConfigFile.Load(configPath);
        settings = loaded.Settings;
        mappings = loaded.Mappings;
        history = loaded.History;
        pipeline = new InputPipeline(sink, mappings, settings, ForegroundId, history);
        Text = "老板遥控 Windows";
        Width = 980;
        Height = 700;
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(860, 620);

        tray = new NotifyIcon
        {
            Visible = true,
            Text = "老板遥控：等待遥控器",
            Icon = CreateIcon(),
        };
        tray.DoubleClick += (_, _) => ShowFromTray();
        var menu = new ContextMenuStrip();
        menu.Items.Add("显示", null, (_, _) => ShowFromTray());
        menu.Items.Add("退出", null, (_, _) =>
        {
            exitRequested = true;
            Close();
        });
        tray.ContextMenuStrip = menu;
        Icon = tray.Icon;

        banner.Text = "Windows 端口。指针和按键只来自读到的 HID/GATT 报告；本机构建环境没有遥控器，真机行为都算未验证。语音不会进入系统麦克风。";
        Controls.Add(BuildTabs());
        Controls.Add(BuildHeader());
        Controls.Add(banner);

        hid.Log += message => BeginInvoke(() => AppendLog(message));
        hid.Report += (source, data, descriptor) => BeginInvoke(() => OnHid(source, data, descriptor));
        hid.InterfacesChanged += count => BeginInvoke(() =>
        {
            interfaceCount = count;
            RefreshConnection();
        });

        clock = new System.Windows.Forms.Timer { Interval = 16 };
        clock.Tick += (_, _) =>
        {
            pipeline.Advance(Now());
            var ticks = clock.Tag is int current ? current + 1 : 1;
            clock.Tag = ticks;
            if (ticks % 60 == 0)
            {
                RefreshForeground();
            }

            if (ticks % 300 == 0)
            {
                hid.Rescan();
            }
        };
        clock.Start();
        ApplyTheme();
        RefreshConnection();
        RefreshHistory();
        FormClosing += OnClosing;
        Shown += (_, _) =>
        {
            if (settings.LaunchAtLogin)
            {
                try
                {
                    StartupRegistration.Set(true);
                }
                catch (Exception ex)
                {
                    AppendLog("开机启动写入失败：" + ex.Message);
                }
            }

            hid.Start();
            _ = ProbeGattAsync();
            if (settings.RelayEnabled)
            {
                _ = relay.StartAsync(AppendLog);
            }
        };
    }

    private Control BuildHeader()
    {
        var header = new Panel { Dock = DockStyle.Top, Height = 190 };
        header.Controls.Add(pad);
        var stack = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, Padding = new Padding(12) };
        connection.Font = new Font(Font.FontFamily, 14, FontStyle.Bold);
        stack.Controls.Add(connection);
        stack.Controls.Add(batteryLabel);
        stack.Controls.Add(foregroundLabel);
        var refresh = new Button { Text = "重新检查连接", AutoSize = true };
        refresh.Click += async (_, _) =>
        {
            hid.Rescan();
            await ProbeGattAsync();
        };
        stack.Controls.Add(refresh);
        header.Controls.Add(stack);
        return header;
    }

    private Control BuildTabs()
    {
        var tabs = new TabControl { Dock = DockStyle.Fill };
        tabs.TabPages.Add(Page("连接", logBox));
        tabs.TabPages.Add(Page("映射", BuildMapping()));
        tabs.TabPages.Add(Page("设置", BuildSettings()));
        tabs.TabPages.Add(Page("记录", historyList));
        return tabs;
    }

    private Control BuildMapping()
    {
        var root = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, Padding = new Padding(8) };
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 38));
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 62));
        root.RowCount = 1;
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        foreach (var control in RemoteCatalog.All)
        {
            controls.Items.Add(new ControlChoice(control));
        }

        controls.SelectedIndexChanged += (_, _) => ShowSelectedMapping();
        controls.SelectedIndex = 0;
        root.Controls.Add(controls, 0, 0);

        var side = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true };
        side.Controls.Add(new Label { Text = "作用范围", AutoSize = true });
        scope.SelectedIndexChanged += (_, _) => ShowSelectedMapping();
        side.Controls.Add(scope);
        var add = new Button { Text = "为当前前台程序单独映射", AutoSize = true };
        add.Click += (_, _) => AddForegroundProfile();
        side.Controls.Add(add);
        var remove = new Button { Text = "删除这个程序的映射", AutoSize = true };
        remove.Click += (_, _) => RemoveProfile();
        side.Controls.Add(remove);
        side.Controls.Add(new Label { Text = "按下", AutoSize = true, Margin = new Padding(0, 12, 0, 0) });
        FillActions(pressAction);
        pressAction.SelectedIndexChanged += (_, _) => SaveSelected(hold: false);
        side.Controls.Add(pressAction);
        side.Controls.Add(new Label { Text = "长按 0.5 秒", AutoSize = true, Margin = new Padding(0, 12, 0, 0) });
        FillActions(holdAction);
        holdAction.SelectedIndexChanged += (_, _) => SaveSelected(hold: true);
        side.Controls.Add(holdAction);
        var reset = new Button { Text = "恢复默认映射", AutoSize = true, Margin = new Padding(0, 16, 0, 0) };
        reset.Click += (_, _) =>
        {
            mappings.ResetActions();
            SaveConfig();
            ShowSelectedMapping();
        };
        side.Controls.Add(reset);
        root.Controls.Add(side, 1, 0);
        ReloadScopes();
        return root;
    }

    private Control BuildSettings()
    {
        var panel = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, AutoScroll = true, Padding = new Padding(12), WrapContents = false };
        panel.Controls.Add(Check("启用指针", settings.PointerEnabled, value => settings.PointerEnabled = value));
        panel.Controls.Add(Check("启用滚动", settings.ScrollEnabled, value => settings.ScrollEnabled = value));
        panel.Controls.Add(Check("轻点点击", settings.TapToClick, value => settings.TapToClick = value));
        panel.Controls.Add(Check("按下后拖拽（接触面积上升时按住左键）", settings.PressToDrag, value => settings.PressToDrag = value));
        panel.Controls.Add(Check("按下后锁定指针", settings.PressFreeze, value => settings.PressFreeze = value));
        panel.Controls.Add(Check("反转指针上下", settings.InvertPointerY, value => settings.InvertPointerY = value));
        panel.Controls.Add(Check("反转滚动方向", settings.InvertScroll, value => settings.InvertScroll = value));
        panel.Controls.Add(Speed("指针速度", settings.PointerSpeed, value => settings.PointerSpeed = value));
        panel.Controls.Add(Speed("滚动速度", settings.ScrollSpeed, value => settings.ScrollSpeed = value));
        panel.Controls.Add(Check("按住 Siri 时按住右 Ctrl（给本机输入法，不是麦克风）", settings.SiriSustainedKey, value => settings.SiriSustainedKey = value));
        panel.Controls.Add(Check("GATT 补充通道（订阅通知；不写未公开控制字节）", settings.GattSupplement, value =>
        {
            settings.GattSupplement = value;
            _ = ProbeGattAsync();
        }));
        panel.Controls.Add(Check("记录按键", settings.HistoryEnabled, value => settings.HistoryEnabled = value));
        panel.Controls.Add(Check("转发遥控器事件到 127.0.0.1（需 token 文件和你自己的 SSH 隧道）", settings.RelayEnabled, value =>
        {
            settings.RelayEnabled = value;
            if (value)
            {
                _ = relay.StartAsync(AppendLog);
            }
            else
            {
                _ = relay.StopAsync();
            }
        }));
        panel.Controls.Add(Check("开机启动", settings.LaunchAtLogin, value =>
        {
            settings.LaunchAtLogin = value;
            try
            {
                StartupRegistration.Set(value);
            }
            catch (Exception ex)
            {
                AppendLog("开机启动写入失败：" + ex.Message);
            }
        }));
        var appearance = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 160 };
        appearance.Items.AddRange(["夜间", "日间"]);
        appearance.SelectedIndex = settings.Appearance == "light" ? 1 : 0;
        appearance.SelectedIndexChanged += (_, _) =>
        {
            if (loadingUi)
            {
                return;
            }

            settings.Appearance = appearance.SelectedIndex == 1 ? "light" : "dark";
            ApplyTheme();
            SaveConfig();
        };
        panel.Controls.Add(appearance);
        var reset = new Button { Text = "恢复输入手感默认值", AutoSize = true };
        reset.Click += (_, _) =>
        {
            settings.ResetInput();
            SaveConfig();
            AppendLog("已恢复输入默认值。重新打开设置页即可看到勾选状态。");
        };
        panel.Controls.Add(reset);
        panel.Controls.Add(new Label
        {
            AutoSize = true,
            MaximumSize = new Size(640, 0),
            Text = "亮度加减、隐藏 App、当前 App 窗口预览没有 Windows 等价按键，选中后不会发送。语音虚拟设备未实现。",
        });
        return panel;
    }

    private void OnHid(string source, byte[] data, byte[]? descriptor)
    {
        if (descriptor is { Length: > 0 })
        {
            layouts[source] = HidReportLayout.Parse(descriptor);
        }

        if (data.Length == 0)
        {
            RefreshConnection();
            return;
        }

        NoteReport(source, data);
        layouts.TryGetValue(source, out var layout);
        foreach (var remoteEvent in router.Push(source, data, layout))
        {
            ApplyRemote(remoteEvent);
        }

        RefreshConnection();
    }

    private void ApplyRemote(RemoteEvent remoteEvent)
    {
        switch (remoteEvent)
        {
            case TouchFrame frame:
                pad.ShowContact(frame.Contacts.Count == 0 ? default(Contact?) : frame.Contacts[0]);
                break;
            case BatteryReading reading:
                battery.SetConnected(true, reading.Level, DateTime.UtcNow);
                break;
        }

        pipeline.Apply(remoteEvent, Now());
        relay.Forward(remoteEvent);
        if (remoteEvent is ButtonChanged { Down: true })
        {
            RefreshHistory();
            SaveConfig();
        }
    }

    private async Task ProbeGattAsync()
    {
        AppendLog(settings.GattSupplement ? "开始 GATT 探测，补充通道开。" : "开始 GATT 探测，补充通道关。");
        await gatt.ProbeAsync(
            settings.GattSupplement,
            message => BeginInvoke(() => AppendLog(message)),
            bytes => BeginInvoke(() => OnGatt(bytes)),
            level => BeginInvoke(() =>
            {
                battery.Update(level, null, DateTime.UtcNow);
                RefreshConnection();
            }),
            state => BeginInvoke(() =>
            {
                if (battery.Level is { } level)
                {
                    battery.Update(level, state, DateTime.UtcNow);
                }

                RefreshConnection();
            }));
    }

    private void OnGatt(byte[] bytes)
    {
        if (SiriVoiceFrame.TryExtractOpus(bytes) != null)
        {
            voiceFrames++;
            AppendLog($"收到可解析的 Opus 通知 {voiceFrames} 帧。没有虚拟麦克风，这些帧被丢弃。");
            RefreshConnection();
            return;
        }

        foreach (var remoteEvent in router.Push("gatt", bytes, null))
        {
            ApplyRemote(remoteEvent);
        }
    }

    private void RefreshConnection()
    {
        var open = interfaceCount > 0;
        connection.Text = open ? "HID 已打开 A2854" : "没有打开的 A2854 HID 接口";
        var level = battery.Level?.ToString() ?? "没有读数";
        var charge = battery.IsCharging ? "充电中" : battery.ChargeState.ToString();
        var rate = battery.ChargeRatePerHour(DateTime.UtcNow);
        batteryLabel.Text = $"电量 {level} / {charge}" + (rate is { } value ? $" / 约 {value:0} %/小时" : "") +
                            "    触控报告 " + (router.SawTouchReport ? "有" : "还没有") +
                            "    按键报告 " + (router.SawButtonReport ? "有" : "还没有") +
                            $"    语音帧 {voiceFrames}（不播放）";
        tray.Text = open ? "老板遥控：HID 已打开" : "老板遥控：等待遥控器";
        if (tray.Text.Length > 63)
        {
            tray.Text = tray.Text[..63];
        }
    }

    private void RefreshForeground()
    {
        foregroundPath = ForegroundProcess.ExecutablePath();
        var self = Environment.ProcessPath;
        var name = string.IsNullOrWhiteSpace(foregroundPath) ||
                   string.Equals(foregroundPath, self, StringComparison.OrdinalIgnoreCase)
            ? "全局（前台是本程序或未知）"
            : Path.GetFileName(foregroundPath);
        foregroundLabel.Text = "当前前台：" + name;
    }

    private string? ForegroundId()
    {
        var path = foregroundPath ?? ForegroundProcess.ExecutablePath();
        var self = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(path) || string.Equals(path, self, StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        return path;
    }

    private void AddForegroundProfile()
    {
        var path = ForegroundProcess.ExecutablePath();
        var self = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(path) || string.Equals(path, self, StringComparison.OrdinalIgnoreCase))
        {
            AppendLog("先切到要单独映射的程序，再点这个按钮。");
            return;
        }

        mappings.Ensure(path, Path.GetFileName(path));
        SaveConfig();
        ReloadScopes();
        scope.SelectedItem = path;
    }

    private void RemoveProfile()
    {
        if (scope.SelectedItem is not string id || id == "全局")
        {
            return;
        }

        mappings.RemoveProfile(id);
        SaveConfig();
        ReloadScopes();
    }

    private void ReloadScopes()
    {
        loadingUi = true;
        var selected = scope.SelectedItem as string ?? "全局";
        scope.Items.Clear();
        scope.Items.Add("全局");
        foreach (var profile in mappings.Profiles.Values.OrderBy(profile => profile.DisplayName))
        {
            scope.Items.Add(profile.AppId);
        }

        scope.SelectedItem = scope.Items.Contains(selected) ? selected : "全局";
        loadingUi = false;
        ShowSelectedMapping();
    }

    private void ShowSelectedMapping()
    {
        if (loadingUi || controls.SelectedItem is not ControlChoice selected)
        {
            return;
        }

        var control = selected.Control;
        loadingUi = true;
        var appId = SelectedApp();
        SelectAction(pressAction, mappings.Action(control, appId));
        SelectAction(holdAction, mappings.HoldAction(control, appId));
        loadingUi = false;
    }

    private void SaveSelected(bool hold)
    {
        if (loadingUi || controls.SelectedItem is not ControlChoice selected)
        {
            return;
        }

        var control = selected.Control;
        var combo = hold ? holdAction : pressAction;
        if (combo.SelectedItem is not ActionChoice choice)
        {
            return;
        }

        if (hold)
        {
            mappings.SetHoldAction(control, choice.Action, SelectedApp());
        }
        else
        {
            mappings.SetAction(control, choice.Action, SelectedApp());
        }

        SaveConfig();
    }

    private string? SelectedApp() => scope.SelectedItem as string == "全局" ? null : scope.SelectedItem as string;

    private void RefreshHistory()
    {
        historyList.Items.Clear();
        foreach (var item in history.Events.Take(200))
        {
            var control = item.Control is { } value ? RemoteCatalog.Title(value) : "";
            historyList.Items.Add($"{item.Date.ToLocalTime():HH:mm:ss}  {control}  {item.ActionLabel}  {item.Detail}  ×{item.Count}");
        }
    }

    private void NoteReport(string source, byte[] data)
    {
        loggedReports.TryGetValue(source, out var count);
        if (count >= 12)
        {
            return;
        }

        loggedReports[source] = count + 1;
        var hex = Convert.ToHexString(data.AsSpan(0, Math.Min(data.Length, 24)));
        AppendLog($"{source} 报告 {data.Length} 字节 {hex}");
    }

    private void AppendLog(string message)
    {
        logBox.AppendText($"{DateTime.Now:HH:mm:ss} {message}{Environment.NewLine}");
    }

    private void SaveConfig() =>
        ConfigFile.Save(configPath, settings, mappings, history, battery.Samples);

    private void ApplyTheme()
    {
        var dark = settings.Appearance != "light";
        var back = dark ? Color.FromArgb(28, 28, 32) : Color.FromArgb(246, 244, 240);
        var fore = dark ? Color.FromArgb(236, 232, 226) : Color.FromArgb(28, 28, 32);
        ApplyColors(this, back, fore);
        pad.Dark = dark;
        pad.Invalidate();
    }

    private static void ApplyColors(Control root, Color back, Color fore)
    {
        root.BackColor = back;
        root.ForeColor = fore;
        foreach (Control child in root.Controls)
        {
            if (child is Button or TextBox or ComboBox or ListBox)
            {
                child.BackColor = back;
                child.ForeColor = fore;
            }

            ApplyColors(child, back, fore);
        }
    }

    private CheckBox Check(string text, bool value, Action<bool> set)
    {
        var box = new CheckBox { Text = text, AutoSize = true, Checked = value, Margin = new Padding(0, 6, 0, 0) };
        box.CheckedChanged += (_, _) =>
        {
            if (loadingUi)
            {
                return;
            }

            set(box.Checked);
            SaveConfig();
        };
        return box;
    }

    private Control Speed(string text, double value, Action<double> set)
    {
        var row = new FlowLayoutPanel { AutoSize = true, WrapContents = false };
        row.Controls.Add(new Label { Text = text, AutoSize = true, Padding = new Padding(0, 6, 8, 0) });
        var input = new NumericUpDown { Minimum = 0.2m, Maximum = 3m, DecimalPlaces = 2, Increment = 0.05m, Value = (decimal)value, Width = 80 };
        input.ValueChanged += (_, _) =>
        {
            if (loadingUi)
            {
                return;
            }

            set((double)input.Value);
            SaveConfig();
        };
        row.Controls.Add(input);
        return row;
    }

    private static void FillActions(ComboBox combo)
    {
        combo.Items.Add(new ActionChoice("不执行操作", ButtonAction.None));
        combo.Items.Add(new ActionChoice("鼠标左键单击", ButtonAction.MouseClick));
        combo.Items.Add(new ActionChoice("按住鼠标左键（拖拽）", ButtonAction.HoldLeftButton));
        foreach (var key in Enum.GetValues<KeyBinding>())
        {
            combo.Items.Add(new ActionChoice(KeyCatalog.Title(key), ButtonAction.FromKey(key)));
        }
    }

    private static void SelectAction(ComboBox combo, ButtonAction action)
    {
        foreach (ActionChoice choice in combo.Items)
        {
            if (choice.Action == action)
            {
                combo.SelectedItem = choice;
                return;
            }
        }

        combo.SelectedIndex = 0;
    }

    private void ShowFromTray()
    {
        Show();
        WindowState = FormWindowState.Normal;
        Activate();
    }

    private void OnClosing(object? sender, FormClosingEventArgs e)
    {
        if (!exitRequested && e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            Hide();
            return;
        }

        SaveConfig();
        clock.Stop();
        _ = relay.StopAsync();
        hid.Dispose();
        _ = gatt.DisposeAsync();
        tray.Visible = false;
        tray.Dispose();
    }

    private static double Now() => Environment.TickCount64 / 1000.0;

    private static TabPage Page(string title, Control content)
    {
        var page = new TabPage(title);
        content.Dock = DockStyle.Fill;
        page.Controls.Add(content);
        return page;
    }

    private static Icon CreateIcon()
    {
        var bitmap = new Bitmap(32, 32);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.Clear(Color.FromArgb(32, 32, 36));
        using var brush = new SolidBrush(Color.FromArgb(232, 122, 54));
        graphics.FillEllipse(brush, 5, 5, 22, 22);
        return Icon.FromHandle(bitmap.GetHicon());
    }

    private sealed class ControlChoice(RemoteControl control)
    {
        public RemoteControl Control { get; } = control;
        public override string ToString() => RemoteCatalog.Title(Control) + (RemoteCatalog.IsGesture(Control) ? "（手势）" : "");
    }

    private sealed class ActionChoice(string label, ButtonAction action)
    {
        public string Label { get; } = label;
        public ButtonAction Action { get; } = action;
        public override string ToString() => Label;
    }
}

internal sealed class PadView : Panel
{
    public bool Dark { get; set; } = true;
    private Contact? contact;

    public PadView()
    {
        DoubleBuffered = true;
    }

    public void ShowContact(Contact? next)
    {
        contact = next;
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var graphics = e.Graphics;
        graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        var body = Dark ? Color.FromArgb(48, 48, 54) : Color.FromArgb(226, 223, 216);
        var rim = Dark ? Color.FromArgb(90, 90, 98) : Color.FromArgb(180, 176, 168);
        using var bodyBrush = new SolidBrush(body);
        using var rimPen = new Pen(rim, 2);
        var rect = new Rectangle(18, 8, Width - 36, Height - 16);
        graphics.FillRoundedRectangle(bodyBrush, rect, 28);
        var padRect = new Rectangle(Width / 2 - 58, Height / 2 - 58, 116, 116);
        graphics.DrawEllipse(rimPen, padRect);
        if (contact == null)
        {
            return;
        }

        var onRing = TouchGeometry.IsOnRing(contact.Value.X, contact.Value.Y, false);
        if (onRing)
        {
            using var glow = new Pen(Color.FromArgb(120, 232, 122, 54), 8);
            graphics.DrawEllipse(glow, padRect);
        }

        var x = padRect.Left + (float)(contact.Value.X * padRect.Width);
        var y = padRect.Top + (float)((1 - contact.Value.Y) * padRect.Height);
        using var dot = new SolidBrush(Color.FromArgb(232, 122, 54));
        graphics.FillEllipse(dot, x - 6, y - 6, 12, 12);
    }
}

internal static class GraphicsExtensions
{
    public static void FillRoundedRectangle(this Graphics graphics, Brush brush, Rectangle bounds, int radius)
    {
        using var path = new System.Drawing.Drawing2D.GraphicsPath();
        var diameter = radius * 2;
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        graphics.FillPath(brush, path);
    }
}
