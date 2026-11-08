namespace BossRemote.Core;

/// <summary>
/// 与 macOS <c>RemoteControl</c> 相同的 22 个目标：13 个实体键 + 9 个手势。
/// 字符串值保持一致，方便对照，不表示配置文件可以跨系统直接拷贝。
/// </summary>
public enum RemoteControl
{
    Power,
    Up,
    Down,
    Left,
    Right,
    Select,
    Back,
    Tv,
    PlayPause,
    VolumeUp,
    VolumeDown,
    Mute,
    Siri,
    RingUp,
    RingDown,
    RingLeft,
    RingRight,
    SwipeUp,
    SwipeDown,
    SwipeLeft,
    SwipeRight,
    TapTwo,
}

public enum KeyBinding
{
    ReturnKey,
    Escape,
    Space,
    Tab,
    Delete,
    ForwardDelete,
    UpArrow,
    DownArrow,
    LeftArrow,
    RightArrow,
    PageUp,
    PageDown,
    Home,
    End,
    Undo,
    Redo,
    Cut,
    Copy,
    Paste,
    SelectAll,
    Find,
    Save,
    NewItem,
    OpenItem,
    CloseWindow,
    QuitApp,
    HideApp,
    Minimize,
    FullScreen,
    Reload,
    GoBack,
    GoForward,
    NewTab,
    ReopenTab,
    NextTab,
    PreviousTab,
    AddressBar,
    AppSwitcher,
    LockScreen,
    Spotlight,
    MissionControl,
    AppExpose,
    ShowDesktop,
    Launchpad,
    Screenshot,
    MediaPlayPause,
    MediaNext,
    MediaPrevious,
    VolumeUp,
    VolumeDown,
    Mute,
    BrightnessUp,
    BrightnessDown,
}

public enum ActionKind
{
    None,
    Key,
    MouseClick,
    HoldLeftButton,
}

public readonly record struct ButtonAction(ActionKind Kind, KeyBinding? Key)
{
    public static ButtonAction None { get; } = new(ActionKind.None, null);

    public static ButtonAction FromKey(KeyBinding key) => new(ActionKind.Key, key);

    public static ButtonAction MouseClick { get; } = new(ActionKind.MouseClick, null);

    public static ButtonAction HoldLeftButton { get; } = new(ActionKind.HoldLeftButton, null);

    public bool IsNone => Kind == ActionKind.None;

    public string Label => Kind switch
    {
        ActionKind.None => "不执行操作",
        ActionKind.MouseClick => "鼠标左键单击",
        ActionKind.HoldLeftButton => "按住鼠标左键（拖拽）",
        ActionKind.Key => Key is { } key ? KeyCatalog.Title(key) : "按键",
        _ => "不执行操作",
    };
}

[Flags]
public enum KeyModifiers
{
    None = 0,
    Control = 1,
    Shift = 2,
    Alt = 4,
    Windows = 8,
}

public readonly record struct KeyChord(ushort VirtualKey, KeyModifiers Modifiers, bool Extended = false);

public static class RemoteCatalog
{
    public static readonly RemoteControl[] ButtonControls =
    [
        RemoteControl.Power, RemoteControl.Back, RemoteControl.Tv, RemoteControl.PlayPause,
        RemoteControl.VolumeUp, RemoteControl.VolumeDown, RemoteControl.Mute, RemoteControl.Siri,
    ];

    public static readonly RemoteControl[] DirectionalControls =
    [
        RemoteControl.Up, RemoteControl.Down, RemoteControl.Left, RemoteControl.Right, RemoteControl.Select,
    ];

    public static readonly RemoteControl[] GestureControls =
    [
        RemoteControl.RingUp, RemoteControl.RingDown, RemoteControl.RingLeft, RemoteControl.RingRight,
        RemoteControl.SwipeUp, RemoteControl.SwipeDown, RemoteControl.SwipeLeft, RemoteControl.SwipeRight,
        RemoteControl.TapTwo,
    ];

    public static IEnumerable<RemoteControl> All { get; } =
        Enum.GetValues<RemoteControl>();

    public static bool IsGesture(RemoteControl control) =>
        GestureControls.Contains(control);

    public static string Title(RemoteControl control) => control switch
    {
        RemoteControl.Power => "电源",
        RemoteControl.Up => "上",
        RemoteControl.Down => "下",
        RemoteControl.Left => "左",
        RemoteControl.Right => "右",
        RemoteControl.Select => "确定键",
        RemoteControl.Back => "返回",
        RemoteControl.Tv => "TV",
        RemoteControl.PlayPause => "播放 / 暂停",
        RemoteControl.VolumeUp => "音量 +",
        RemoteControl.VolumeDown => "音量 −",
        RemoteControl.Mute => "静音",
        RemoteControl.Siri => "Siri 语音键",
        RemoteControl.RingUp => "外环上滑",
        RemoteControl.RingDown => "外环下滑",
        RemoteControl.RingLeft => "外环左滑",
        RemoteControl.RingRight => "外环右滑",
        RemoteControl.SwipeUp => "上滑",
        RemoteControl.SwipeDown => "下滑",
        RemoteControl.SwipeLeft => "左滑",
        RemoteControl.SwipeRight => "右滑",
        RemoteControl.TapTwo => "双击触控板",
        _ => control.ToString(),
    };

    public static string Id(RemoteControl control) => control switch
    {
        RemoteControl.PlayPause => "play_pause",
        RemoteControl.VolumeUp => "volume_up",
        RemoteControl.VolumeDown => "volume_down",
        RemoteControl.RingUp => "ringUp",
        RemoteControl.RingDown => "ringDown",
        RemoteControl.RingLeft => "ringLeft",
        RemoteControl.RingRight => "ringRight",
        RemoteControl.SwipeUp => "swipeUp",
        RemoteControl.SwipeDown => "swipeDown",
        RemoteControl.SwipeLeft => "swipeLeft",
        RemoteControl.SwipeRight => "swipeRight",
        RemoteControl.TapTwo => "tapTwo",
        _ => control.ToString().ToLowerInvariant(),
    };

    public static bool TryParseId(string id, out RemoteControl control)
    {
        foreach (var candidate in All)
        {
            if (string.Equals(Id(candidate), id, StringComparison.Ordinal))
            {
                control = candidate;
                return true;
            }
        }

        control = default;
        return false;
    }

    public static ButtonAction DefaultAction(RemoteControl control) => control switch
    {
        RemoteControl.Select => ButtonAction.FromKey(KeyBinding.ReturnKey),
        RemoteControl.Back => ButtonAction.FromKey(KeyBinding.Delete),
        RemoteControl.Tv => ButtonAction.FromKey(KeyBinding.AppSwitcher),
        RemoteControl.PlayPause => ButtonAction.FromKey(KeyBinding.MediaPlayPause),
        RemoteControl.Up => ButtonAction.FromKey(KeyBinding.UpArrow),
        RemoteControl.Down => ButtonAction.FromKey(KeyBinding.DownArrow),
        RemoteControl.Left => ButtonAction.FromKey(KeyBinding.LeftArrow),
        RemoteControl.Right => ButtonAction.FromKey(KeyBinding.RightArrow),
        RemoteControl.VolumeUp => ButtonAction.FromKey(KeyBinding.VolumeUp),
        RemoteControl.VolumeDown => ButtonAction.FromKey(KeyBinding.VolumeDown),
        RemoteControl.Mute => ButtonAction.FromKey(KeyBinding.Mute),
        RemoteControl.Power => ButtonAction.FromKey(KeyBinding.LockScreen),
        _ => ButtonAction.None,
    };

    public static Dictionary<RemoteControl, ButtonAction> DefaultActions()
    {
        var map = new Dictionary<RemoteControl, ButtonAction>();
        foreach (var control in All)
        {
            map[control] = DefaultAction(control);
        }

        return map;
    }
}

public static class KeyCatalog
{
    public static string Title(KeyBinding key) => key switch
    {
        KeyBinding.ReturnKey => "Enter",
        KeyBinding.Escape => "Esc",
        KeyBinding.Space => "空格",
        KeyBinding.Tab => "Tab",
        KeyBinding.Delete => "退格",
        KeyBinding.ForwardDelete => "Delete",
        KeyBinding.UpArrow => "↑",
        KeyBinding.DownArrow => "↓",
        KeyBinding.LeftArrow => "←",
        KeyBinding.RightArrow => "→",
        KeyBinding.PageUp => "Page Up",
        KeyBinding.PageDown => "Page Down",
        KeyBinding.Home => "Home",
        KeyBinding.End => "End",
        KeyBinding.Undo => "撤销",
        KeyBinding.Redo => "重做",
        KeyBinding.Cut => "剪切",
        KeyBinding.Copy => "复制",
        KeyBinding.Paste => "粘贴",
        KeyBinding.SelectAll => "全选",
        KeyBinding.Find => "查找",
        KeyBinding.Save => "保存",
        KeyBinding.NewItem => "新建",
        KeyBinding.OpenItem => "打开",
        KeyBinding.CloseWindow => "关闭窗口或标签页",
        KeyBinding.QuitApp => "关闭程序（Alt+F4）",
        KeyBinding.HideApp => "隐藏 App（Windows 无对应按键）",
        KeyBinding.Minimize => "最小化",
        KeyBinding.FullScreen => "全屏（F11）",
        KeyBinding.Reload => "刷新",
        KeyBinding.GoBack => "后退",
        KeyBinding.GoForward => "前进",
        KeyBinding.NewTab => "新建标签页",
        KeyBinding.ReopenTab => "恢复标签页",
        KeyBinding.NextTab => "下一个标签页",
        KeyBinding.PreviousTab => "上一个标签页",
        KeyBinding.AddressBar => "地址栏",
        KeyBinding.AppSwitcher => "切换窗口（Alt+Tab）",
        KeyBinding.LockScreen => "锁定（Win+L）",
        KeyBinding.Spotlight => "搜索（Win+S）",
        KeyBinding.MissionControl => "任务视图（Win+Tab）",
        KeyBinding.AppExpose => "窗口预览（Windows 无对应按键）",
        KeyBinding.ShowDesktop => "显示桌面",
        KeyBinding.Launchpad => "开始菜单",
        KeyBinding.Screenshot => "截图（Win+Shift+S）",
        KeyBinding.MediaPlayPause => "媒体播放 / 暂停",
        KeyBinding.MediaNext => "下一首",
        KeyBinding.MediaPrevious => "上一首",
        KeyBinding.VolumeUp => "系统音量 +",
        KeyBinding.VolumeDown => "系统音量 −",
        KeyBinding.Mute => "系统静音",
        KeyBinding.BrightnessUp => "亮度 +（Windows 无对应按键）",
        KeyBinding.BrightnessDown => "亮度 −（Windows 无对应按键）",
        _ => key.ToString(),
    };

    public static string? UnavailableReason(KeyBinding key) => key switch
    {
        KeyBinding.HideApp => "macOS 的隐藏 App 没有等价系统按键，本程序不发送替代键。",
        KeyBinding.AppExpose => "macOS 的当前 App 窗口预览没有等价系统按键，本程序不发送替代键。",
        KeyBinding.BrightnessUp or KeyBinding.BrightnessDown =>
            "Windows 没有与 macOS 亮度键对应的虚拟键，本程序不发送替代键。",
        _ => null,
    };

    public static bool TryGetChord(KeyBinding key, out KeyChord chord)
    {
        chord = default;
        if (UnavailableReason(key) != null)
        {
            return false;
        }

        chord = key switch
        {
            KeyBinding.ReturnKey => Key(Vk.Return),
            KeyBinding.Escape => Key(Vk.Escape),
            KeyBinding.Space => Key(Vk.Space),
            KeyBinding.Tab => Key(Vk.Tab),
            KeyBinding.Delete => Key(Vk.Back),
            KeyBinding.ForwardDelete => Ext(Vk.Delete),
            KeyBinding.UpArrow => Ext(Vk.Up),
            KeyBinding.DownArrow => Ext(Vk.Down),
            KeyBinding.LeftArrow => Ext(Vk.Left),
            KeyBinding.RightArrow => Ext(Vk.Right),
            KeyBinding.PageUp => Ext(Vk.PageUp),
            KeyBinding.PageDown => Ext(Vk.PageDown),
            KeyBinding.Home => Ext(Vk.Home),
            KeyBinding.End => Ext(Vk.End),
            KeyBinding.Undo => Ctrl(Vk.Z),
            KeyBinding.Redo => Ctrl(Vk.Y),
            KeyBinding.Cut => Ctrl(Vk.X),
            KeyBinding.Copy => Ctrl(Vk.C),
            KeyBinding.Paste => Ctrl(Vk.V),
            KeyBinding.SelectAll => Ctrl(Vk.A),
            KeyBinding.Find => Ctrl(Vk.F),
            KeyBinding.Save => Ctrl(Vk.S),
            KeyBinding.NewItem => Ctrl(Vk.N),
            KeyBinding.OpenItem => Ctrl(Vk.O),
            KeyBinding.CloseWindow => Ctrl(Vk.W),
            KeyBinding.QuitApp => Alt(Vk.F4),
            KeyBinding.Minimize => Win(Vk.Down, extended: true),
            KeyBinding.FullScreen => Key(Vk.F11),
            KeyBinding.Reload => Ctrl(Vk.R),
            KeyBinding.GoBack => Alt(Vk.Left, extended: true),
            KeyBinding.GoForward => Alt(Vk.Right, extended: true),
            KeyBinding.NewTab => Ctrl(Vk.T),
            KeyBinding.ReopenTab => CtrlShift(Vk.T),
            KeyBinding.NextTab => Ctrl(Vk.Tab),
            KeyBinding.PreviousTab => CtrlShift(Vk.Tab),
            KeyBinding.AddressBar => Ctrl(Vk.L),
            KeyBinding.AppSwitcher => Alt(Vk.Tab),
            KeyBinding.LockScreen => Win(Vk.L),
            KeyBinding.Spotlight => Win(Vk.S),
            KeyBinding.MissionControl => Win(Vk.Tab),
            KeyBinding.ShowDesktop => Win(Vk.D),
            KeyBinding.Launchpad => new KeyChord(Vk.LWin, KeyModifiers.None, true),
            KeyBinding.Screenshot => new KeyChord(Vk.S, KeyModifiers.Windows | KeyModifiers.Shift, true),
            KeyBinding.MediaPlayPause => Ext(Vk.MediaPlayPause),
            KeyBinding.MediaNext => Ext(Vk.MediaNext),
            KeyBinding.MediaPrevious => Ext(Vk.MediaPrevious),
            KeyBinding.VolumeUp => Ext(Vk.VolumeUp),
            KeyBinding.VolumeDown => Ext(Vk.VolumeDown),
            KeyBinding.Mute => Ext(Vk.VolumeMute),
            _ => default,
        };
        return chord.VirtualKey != 0;
    }

    private static KeyChord Key(ushort vk) => new(vk, KeyModifiers.None);

    private static KeyChord Ext(ushort vk) => new(vk, KeyModifiers.None, true);

    private static KeyChord Ctrl(ushort vk) => new(vk, KeyModifiers.Control, vk is Vk.Left or Vk.Right or Vk.Up or Vk.Down or Vk.Tab);

    private static KeyChord CtrlShift(ushort vk) =>
        new(vk, KeyModifiers.Control | KeyModifiers.Shift, vk is Vk.Left or Vk.Right or Vk.Tab);

    private static KeyChord Alt(ushort vk, bool extended = false) => new(vk, KeyModifiers.Alt, extended);

    private static KeyChord Win(ushort vk, bool extended = true) => new(vk, KeyModifiers.Windows, extended);
}

public static class Vk
{
    public const ushort Return = 0x0D;
    public const ushort Escape = 0x1B;
    public const ushort Space = 0x20;
    public const ushort Tab = 0x09;
    public const ushort Back = 0x08;
    public const ushort Delete = 0x2E;
    public const ushort Up = 0x26;
    public const ushort Down = 0x28;
    public const ushort Left = 0x25;
    public const ushort Right = 0x27;
    public const ushort PageUp = 0x21;
    public const ushort PageDown = 0x22;
    public const ushort Home = 0x24;
    public const ushort End = 0x23;
    public const ushort F4 = 0x73;
    public const ushort F11 = 0x7A;
    public const ushort LWin = 0x5B;
    public const ushort RControl = 0xA3;
    public const ushort A = 0x41;
    public const ushort C = 0x43;
    public const ushort D = 0x44;
    public const ushort F = 0x46;
    public const ushort L = 0x4C;
    public const ushort N = 0x4E;
    public const ushort O = 0x4F;
    public const ushort R = 0x52;
    public const ushort S = 0x53;
    public const ushort T = 0x54;
    public const ushort V = 0x56;
    public const ushort W = 0x57;
    public const ushort X = 0x58;
    public const ushort Y = 0x59;
    public const ushort Z = 0x5A;
    public const ushort VolumeMute = 0xAD;
    public const ushort VolumeDown = 0xAE;
    public const ushort VolumeUp = 0xAF;
    public const ushort MediaNext = 0xB0;
    public const ushort MediaPrevious = 0xB1;
    public const ushort MediaPlayPause = 0xB3;
}
