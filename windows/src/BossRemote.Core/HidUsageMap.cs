namespace BossRemote.Core;

/// <summary>
/// 与 macOS <c>HIDUsageMap</c> 相同的用法页/用法对照。
/// 只在报告描述符里真实出现这些用法时才会命中。
/// </summary>
public static class HidUsageMap
{
    public const int VendorId = 0x004C;
    public const int ProductId = 0x0315;

    public static readonly int[] AcceptedPrimaryUsagePages = [0x01, 0x06, 0x0C, 0x0D, 0xFF00];

    private static readonly (ushort Page, ushort Usage, RemoteControl Control)[] Map =
    [
        (0x01, 0x86, RemoteControl.Back),
        (0x01, 0x40, RemoteControl.Back),
        (0x0C, 0x40, RemoteControl.Back),
        (0x0C, 0x224, RemoteControl.Back),
        (0x0C, 0x42, RemoteControl.Up),
        (0x0C, 0x43, RemoteControl.Down),
        (0x0C, 0x44, RemoteControl.Left),
        (0x0C, 0x45, RemoteControl.Right),
        (0x0C, 0x04, RemoteControl.Siri),
        (0xFF00, 0x01, RemoteControl.Siri),
        (0xFF00, 0x02, RemoteControl.Siri),
        (0xFF00, 0x03, RemoteControl.Siri),
        (0x0B, 0x21, RemoteControl.Siri),
        (0x0B, 0x2F, RemoteControl.Siri),
        (0x0C, 0x60, RemoteControl.Tv),
        (0x0C, 0x223, RemoteControl.Tv),
        (0x0C, 0x80, RemoteControl.Select),
        (0x0C, 0x41, RemoteControl.Select),
        (0x09, 0x01, RemoteControl.Select),
        (0x0C, 0xCD, RemoteControl.PlayPause),
        (0x0C, 0xE9, RemoteControl.VolumeUp),
        (0x0C, 0xEA, RemoteControl.VolumeDown),
        (0x0C, 0xE2, RemoteControl.Mute),
        (0x0C, 0x20, RemoteControl.Mute),
        (0x0C, 0x30, RemoteControl.Power),
    ];

    public static IReadOnlyList<(ushort Page, ushort Usage, RemoteControl Control)> Entries => Map;

    public static RemoteControl? Control(ushort usagePage, ushort usage)
    {
        foreach (var entry in Map)
        {
            if (entry.Page == usagePage && entry.Usage == usage)
            {
                return entry.Control;
            }
        }

        return null;
    }

    public static int NormalizeBattery(int raw)
    {
        var level = raw > 100 ? (int)Math.Round(raw / 255.0 * 100.0) : raw;
        return Math.Clamp(level, 0, 100);
    }
}
