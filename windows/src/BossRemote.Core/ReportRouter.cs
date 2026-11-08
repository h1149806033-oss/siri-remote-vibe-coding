namespace BossRemote.Core;

public abstract record RemoteEvent;

public sealed record ButtonChanged(RemoteControl Control, bool Down) : RemoteEvent;

public sealed record TouchFrame(IReadOnlyList<Contact> Contacts) : RemoteEvent;

public sealed record BatteryReading(int Level) : RemoteEvent;

/// <summary>
/// 把一份从设备读到的 HID 报告变成按钮、触控或电量事件。
/// 认不出的字节不会产生触控或指针。
/// </summary>
public sealed class ReportRouter
{
    private readonly Dictionary<string, HashSet<RemoteControl>> buttonsBySource = [];
    private int? lastBattery;
    public bool SawButtonReport { get; private set; }
    public bool SawTouchReport { get; private set; }
    public bool SawBatteryReport { get; private set; }

    public IReadOnlyList<RemoteEvent> Push(string source, ReadOnlySpan<byte> report, HidReportLayout? layout)
    {
        var events = new List<RemoteEvent>();
        var usedDescriptor = false;
        if (layout != null && layout.TryDecode(report, out var decoded))
        {
            usedDescriptor = true;
            if (decoded.MentionedButtons.Count > 0)
            {
                SawButtonReport = true;
                events.AddRange(ApplyButtons(source + ":hid", decoded.Pressed));
            }

            if (decoded.HasTouchAxes)
            {
                SawTouchReport = true;
                events.Add(new TouchFrame(decoded.Contacts));
            }

            if (decoded.Battery is { } level)
            {
                AddBattery(level, events);
            }
        }

        if (!usedDescriptor && A2854Reports.TryParseTouch(report, out var contacts))
        {
            SawTouchReport = true;
            events.Add(new TouchFrame(contacts));
            return events;
        }

        if (!usedDescriptor && A2854Reports.TryParseButtons(report, out var bits))
        {
            SawButtonReport = true;
            var down = new HashSet<RemoteControl>();
            A2854Reports.CollectButtons(bits, down);
            events.AddRange(ApplyButtons(source + ":raw", down));
        }

        return events;
    }

    public IReadOnlyList<RemoteEvent> ReleaseSource(string source)
    {
        var events = new List<RemoteEvent>();
        var keys = buttonsBySource.Keys.Where(key => key.StartsWith(source, StringComparison.Ordinal)).ToArray();
        foreach (var key in keys)
        {
            events.AddRange(ApplyButtons(key, []));
            buttonsBySource.Remove(key);
        }

        return events;
    }

    private List<RemoteEvent> ApplyButtons(string key, HashSet<RemoteControl> down)
    {
        buttonsBySource.TryGetValue(key, out var previous);
        previous ??= [];
        var events = new List<RemoteEvent>();
        foreach (var control in down)
        {
            if (previous.Add(control))
            {
                events.Add(new ButtonChanged(control, true));
            }
        }

        foreach (var control in previous.ToArray())
        {
            if (!down.Contains(control))
            {
                previous.Remove(control);
                events.Add(new ButtonChanged(control, false));
            }
        }

        buttonsBySource[key] = previous;
        return events;
    }

    private void AddBattery(int level, List<RemoteEvent> events)
    {
        var clamped = Math.Clamp(level, 0, 100);
        if (lastBattery == clamped)
        {
            return;
        }

        lastBattery = clamped;
        SawBatteryReport = true;
        events.Add(new BatteryReading(clamped));
    }
}
