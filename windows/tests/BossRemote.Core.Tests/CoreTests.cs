using BossRemote.Core;
using Xunit;

namespace BossRemote.Core.Tests;

public sealed class RecordingSink : IPointerSink
{
    public List<string> Events { get; } = [];
    public int MoveX { get; private set; }
    public int MoveY { get; private set; }
    public int ScrollTotal { get; private set; }
    public bool LeftDown { get; private set; }

    public void Move(int dx, int dy)
    {
        MoveX += dx;
        MoveY += dy;
        Events.Add($"move:{dx},{dy}");
    }

    public void Scroll(int pixels)
    {
        ScrollTotal += pixels;
        Events.Add($"scroll:{pixels}");
    }

    public void Click() => Events.Add("click");

    public void SetLeftButton(bool down)
    {
        LeftDown = down;
        Events.Add(down ? "leftdown" : "leftup");
    }

    public void Press(KeyChord chord) => Events.Add($"key:{chord.VirtualKey:X}:{chord.Modifiers}");

    public void SetSustained(KeyChord chord, bool down) =>
        Events.Add($"hold:{chord.VirtualKey:X}:{(down ? "down" : "up")}");

    public void Type(string text) => Events.Add($"text:{text}");
}

public class CatalogTests
{
    [Fact]
    public void Counts_match_the_mac_app()
    {
        Assert.Equal(13, RemoteCatalog.ButtonControls.Length + RemoteCatalog.DirectionalControls.Length);
        Assert.Equal(9, RemoteCatalog.GestureControls.Length);
        Assert.Equal(22, RemoteCatalog.All.Count());
    }

    [Fact]
    public void Usage_map_matches_the_swift_table()
    {
        Assert.Equal(RemoteControl.Back, HidUsageMap.Control(0x0C, 0x224));
        Assert.Equal(RemoteControl.Up, HidUsageMap.Control(0x0C, 0x42));
        Assert.Equal(RemoteControl.Down, HidUsageMap.Control(0x0C, 0x43));
        Assert.Equal(RemoteControl.Left, HidUsageMap.Control(0x0C, 0x44));
        Assert.Equal(RemoteControl.Right, HidUsageMap.Control(0x0C, 0x45));
        Assert.Equal(RemoteControl.Siri, HidUsageMap.Control(0x0C, 0x04));
        Assert.Equal(RemoteControl.Select, HidUsageMap.Control(0x0C, 0x80));
        Assert.Equal(RemoteControl.PlayPause, HidUsageMap.Control(0x0C, 0xCD));
        Assert.Equal(RemoteControl.VolumeUp, HidUsageMap.Control(0x0C, 0xE9));
        Assert.Equal(RemoteControl.VolumeDown, HidUsageMap.Control(0x0C, 0xEA));
        Assert.Equal(RemoteControl.Mute, HidUsageMap.Control(0x0C, 0xE2));
        Assert.Equal(RemoteControl.Power, HidUsageMap.Control(0x0C, 0x30));
        Assert.Equal(RemoteControl.Tv, HidUsageMap.Control(0x0C, 0x60));
        Assert.Null(HidUsageMap.Control(0x01, 0x30));
        Assert.Equal(25, HidUsageMap.Entries.Count);
    }

    [Fact]
    public void Mac_only_actions_do_not_invent_a_chord()
    {
        Assert.False(KeyCatalog.TryGetChord(KeyBinding.BrightnessUp, out _));
        Assert.False(KeyCatalog.TryGetChord(KeyBinding.BrightnessDown, out _));
        Assert.False(KeyCatalog.TryGetChord(KeyBinding.HideApp, out _));
        Assert.False(KeyCatalog.TryGetChord(KeyBinding.AppExpose, out _));
        Assert.True(KeyCatalog.TryGetChord(KeyBinding.AppSwitcher, out var altTab));
        Assert.Equal(Vk.Tab, altTab.VirtualKey);
        Assert.Equal(KeyModifiers.Alt, altTab.Modifiers);
        Assert.True(KeyCatalog.TryGetChord(KeyBinding.VolumeUp, out var volume));
        Assert.Equal(Vk.VolumeUp, volume.VirtualKey);
    }

    [Fact]
    public void Identifiers_match_the_swift_raw_values()
    {
        Assert.Equal("play_pause", RemoteCatalog.Id(RemoteControl.PlayPause));
        Assert.Equal("volume_up", RemoteCatalog.Id(RemoteControl.VolumeUp));
        Assert.Equal("tapTwo", RemoteCatalog.Id(RemoteControl.TapTwo));
        Assert.Equal("ringUp", RemoteCatalog.Id(RemoteControl.RingUp));
        Assert.True(RemoteCatalog.TryParseId("swipeLeft", out var swipe));
        Assert.Equal(RemoteControl.SwipeLeft, swipe);
    }

    [Fact]
    public void Multitouch_calibration_constants_match_the_mac_app()
    {
        Assert.Equal(0.068, TouchGeometry.XAtLeft);
        Assert.Equal(0.902, TouchGeometry.XAtRight);
        Assert.Equal(0.025, TouchGeometry.YAtBottom);
        Assert.Equal(0.892, TouchGeometry.YAtTop);
        Assert.Equal(0.40, TouchGeometry.RingRadius);
        Assert.Equal(0.28, TouchGeometry.RingExitRadius);
        var (x, y) = TouchGeometry.NormalizeMultitouch(0.068, 0.892);
        Assert.Equal(0, x, 3);
        Assert.Equal(0, y, 3);
    }
}

public class ReportTests
{
    [Fact]
    public void Raw_button_bits_follow_the_published_a2854_map()
    {
        Assert.True(A2854Reports.TryParseButtons([0x40, 0x00], out var back));
        var down = new HashSet<RemoteControl>();
        A2854Reports.CollectButtons(back, down);
        Assert.Equal([RemoteControl.Back], down);

        Assert.True(A2854Reports.TryParseButtons([0x00, 0x01], out var play));
        down.Clear();
        A2854Reports.CollectButtons(play, down);
        Assert.Equal([RemoteControl.PlayPause], down);

        Assert.True(A2854Reports.TryParseButtons([0x00, 0x10], out var left));
        down.Clear();
        A2854Reports.CollectButtons(left, down);
        Assert.Equal([RemoteControl.Left], down);

        Assert.False(A2854Reports.TryParseButtons([0x00, 0xE0], out _));
    }

    [Fact]
    public void Raw_touch_report_normalizes_center_and_skips_hover()
    {
        byte[] center = [0x32, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x40, 0x10, 0x0A, 0x08];
        Assert.True(A2854Reports.TryParseTouch(center, out var contacts));
        Assert.Single(contacts);
        Assert.Equal(0.5, contacts[0].X, 3);
        Assert.Equal(0.5, contacts[0].Y, 3);

        byte[] hover = [0x32, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x40, 0x10, 0x0A, 0x02];
        Assert.True(A2854Reports.TryParseTouch(hover, out var hovering));
        Assert.Empty(hovering);
    }

    [Fact]
    public void Descriptor_buttons_and_digitizer_decode_without_guessing_vendor_bytes()
    {
        byte[] buttons =
        [
            0x05, 0x0C, 0x09, 0x01, 0xA1, 0x01,
            0x09, 0xCD, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x01, 0x81, 0x02,
            0x75, 0x07, 0x95, 0x01, 0x81, 0x03,
            0xC0,
        ];
        var layout = HidReportLayout.Parse(buttons);
        Assert.True(layout.TryDecode([0x01], out var pressed));
        Assert.Contains(RemoteControl.PlayPause, pressed.Pressed);
        Assert.True(layout.TryDecode([0x00], out var released));
        Assert.DoesNotContain(RemoteControl.PlayPause, released.Pressed);

        byte[] touch =
        [
            0x05, 0x0D, 0x09, 0x05, 0xA1, 0x01,
            0x05, 0x01, 0x09, 0x30, 0x15, 0x00, 0x26, 0xE8, 0x03,
            0x75, 0x10, 0x95, 0x01, 0x81, 0x02,
            0x09, 0x31, 0x81, 0x02,
            0xC0,
        ];
        var touchLayout = HidReportLayout.Parse(touch);
        Assert.True(touchLayout.TryDecode([0xF4, 0x01, 0xE8, 0x03], out var contact));
        Assert.True(contact.HasTouchAxes);
        Assert.Single(contact.Contacts);
        Assert.Equal(0.5, contact.Contacts[0].X, 2);
        Assert.Equal(1, contact.Contacts[0].Y, 2);
    }

    [Fact]
    public void Unknown_bytes_do_not_become_touch_or_buttons()
    {
        var router = new ReportRouter();
        var events = router.Push("hid", [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88], null);
        Assert.Empty(events);
        Assert.False(router.SawTouchReport);
        Assert.False(router.SawButtonReport);
    }

    [Fact]
    public void Router_emits_edges_once()
    {
        var router = new ReportRouter();
        var down = router.Push("hid", [0x40, 0x00], null);
        var again = router.Push("hid", [0x40, 0x00], null);
        var up = router.Push("hid", [0x00, 0x00], null);
        Assert.Equal(new ButtonChanged(RemoteControl.Back, true), Assert.Single(down));
        Assert.Empty(again);
        Assert.Equal(new ButtonChanged(RemoteControl.Back, false), Assert.Single(up));
    }

    [Fact]
    public void Voice_frame_extracts_opus_and_rejects_noise()
    {
        var packet = new byte[100];
        packet[4] = 4;
        packet[5] = 0xB8;
        packet[6] = 1;
        packet[7] = 2;
        packet[8] = 3;
        var opus = SiriVoiceFrame.TryExtractOpus(packet);
        Assert.Equal(new byte[] { 0xB8, 1, 2, 3 }, opus);
        Assert.Null(SiriVoiceFrame.TryExtractOpus(new byte[100]));
    }
}

public class GestureTests
{
    [Fact]
    public void Finger_moving_right_moves_the_pointer_right_and_up_moves_it_up()
    {
        var engine = Engine();
        var x = 0;
        var y = 0;
        engine.OnPointer = (dx, dy) => { x += dx; y += dy; };
        engine.Handle([At(0.40, 0.50)], 0);
        for (var i = 1; i <= 8; i++)
        {
            engine.Handle([At(0.40 + i * 0.01, 0.50)], i * 0.016);
        }

        Assert.True(x > 0, $"dx={x}");

        x = 0;
        y = 0;
        engine.Handle([], 0.2);
        engine.Handle([At(0.50, 0.40)], 0.3);
        for (var i = 1; i <= 8; i++)
        {
            engine.Handle([At(0.50, 0.40 + i * 0.01)], 0.3 + i * 0.016);
        }

        Assert.True(y < 0, $"dy={y}");
    }

    [Fact]
    public void Short_tap_clicks_and_a_fast_swipe_does_not()
    {
        var clicks = 0;
        var swipes = new List<SwipeDirection>();
        var engine = Engine();
        engine.OnClick = () => clicks++;
        engine.OnSwipe = (direction, _) => swipes.Add(direction);
        engine.Handle([At(0.50, 0.50)], 1);
        engine.Handle([At(0.50, 0.50)], 1.05);
        engine.Handle([], 1.10);
        Assert.Equal(1, clicks);

        engine.Handle([At(0.30, 0.50)], 2);
        engine.Handle([At(0.58, 0.50)], 2.08);
        engine.Handle([], 2.08);
        Assert.Equal(SwipeDirection.Right, Assert.Single(swipes));
        Assert.Equal(1, clicks);
    }

    [Fact]
    public void Outer_ring_scrolls_only_after_the_start_threshold_and_reverses()
    {
        var forward = Rotate(0.04, 30);
        var backward = Rotate(-0.04, 30);
        Assert.True(Math.Abs(forward) > 10, $"forward={forward}");
        Assert.True(Math.Sign(forward) == -Math.Sign(backward));
    }

    [Fact]
    public void Pressure_rise_drags_or_freezes_instead_of_inventing_a_click()
    {
        var drag = Engine();
        drag.PressToDrag = true;
        var events = new List<string>();
        drag.OnDrag = down => events.Add(down ? "down" : "up");
        drag.OnPointer = (dx, _) => events.Add($"move:{dx}");
        FeedPress(drag, 0);
        drag.Handle([At(0.62, 0.50, 0.5)], 0.14);
        drag.Handle([], 0.20);
        Assert.Contains("down", events);
        Assert.Contains("up", events);
        Assert.Contains(events, item => item.StartsWith("move:", StringComparison.Ordinal));

        var frozen = Engine();
        frozen.PressToDrag = false;
        frozen.PressFreezeEnabled = true;
        var moved = 0;
        frozen.OnPointer = (_, _) => moved++;
        FeedPress(frozen, 1);
        frozen.Handle([At(0.51, 0.50, 0.5)], 1.14);
        Assert.Equal(0, moved);
    }

    [Fact]
    public void Double_tap_and_edge_jump_are_distinct()
    {
        var engine = Engine();
        var clicks = 0;
        var doubles = 0;
        var scroll = 0;
        engine.DoubleTapAvailable = () => true;
        engine.OnClick = () => clicks++;
        engine.OnDoubleTap = () => doubles++;
        engine.Handle([At(0.50, 0.50)], 0);
        engine.Handle([], 0.05);
        engine.Handle([At(0.50, 0.50)], 0.12);
        engine.Handle([], 0.16);
        Assert.Equal(1, doubles);
        Assert.Equal(0, clicks);

        engine.DoubleTapAvailable = () => false;
        engine.OnScroll = pixels => scroll += pixels;
        engine.Handle([At(0.50, 0.95)], 1);
        engine.Handle([], 1.05);
        engine.Handle([At(0.50, 0.95)], 1.12);
        engine.Handle([], 1.16);
        Assert.True(scroll < -1000);
    }

    private static GestureEngine Engine() => new()
    {
        PressToDrag = false,
        PressFreezeEnabled = false,
        TapEnabled = true,
        PointerEnabled = true,
        ScrollEnabled = true,
    };

    private static Contact At(double x, double y, double size = 0.2) => new(1, x, y, size);

    private static void FeedPress(GestureEngine engine, double start)
    {
        engine.Handle([At(0.50, 0.50, 0.20)], start);
        engine.Handle([At(0.50, 0.50, 0.20)], start + 0.03);
        engine.Handle([At(0.50, 0.50, 0.20)], start + 0.06);
        engine.Handle([At(0.50, 0.50, 0.50)], start + 0.09);
    }

    private static int Rotate(double step, int count)
    {
        var engine = Engine();
        var total = 0;
        engine.OnScroll = pixels => total += pixels;
        for (var i = 0; i < count; i++)
        {
            var angle = i * step;
            engine.Handle([new Contact(1, 0.5 + Math.Cos(angle) * 0.45, 0.5 + Math.Sin(angle) * 0.45, 0.2)], i * 0.016);
        }

        engine.Handle([], count * 0.016);
        return total;
    }
}

public class PipelineTests
{
    [Fact]
    public void Mapped_button_presses_a_real_chord_and_hold_waits_half_a_second()
    {
        var sink = new RecordingSink();
        var mappings = new MappingStore();
        var pipeline = new InputPipeline(sink, mappings, new AppSettings(), () => null);
        pipeline.Apply(new ButtonChanged(RemoteControl.Back, true), 0);
        pipeline.Apply(new ButtonChanged(RemoteControl.Back, false), 0.05);
        Assert.Contains(sink.Events, item => item.StartsWith("key:", StringComparison.Ordinal));

        sink.Events.Clear();
        mappings.SetHoldAction(RemoteControl.Back, ButtonAction.FromKey(KeyBinding.Escape));
        pipeline.Apply(new ButtonChanged(RemoteControl.Back, true), 1);
        pipeline.Advance(1.49);
        Assert.Empty(sink.Events);
        pipeline.Advance(1.50);
        Assert.Contains(sink.Events, item => item.Contains($":{KeyModifiers.None}", StringComparison.Ordinal) && item.Contains($"{Vk.Escape:X}", StringComparison.Ordinal));

        sink.Events.Clear();
        pipeline.Apply(new ButtonChanged(RemoteControl.Back, true), 2);
        pipeline.Apply(new ButtonChanged(RemoteControl.Back, false), 2.2);
        Assert.Contains(sink.Events, item => item.Contains($"{Vk.Back:X}", StringComparison.Ordinal));
    }

    [Fact]
    public void App_profile_overrides_global_and_siri_holds_a_key_without_audio()
    {
        var sink = new RecordingSink();
        var mappings = new MappingStore();
        mappings.Ensure("notepad.exe", "记事本");
        mappings.SetAction(RemoteControl.PlayPause, ButtonAction.FromKey(KeyBinding.Save), "notepad.exe");
        var pipeline = new InputPipeline(sink, mappings, new AppSettings(), () => "notepad.exe");
        pipeline.Apply(new ButtonChanged(RemoteControl.PlayPause, true), 0);
        pipeline.Apply(new ButtonChanged(RemoteControl.PlayPause, false), 0.01);
        Assert.Contains(sink.Events, item => item.Contains($"{Vk.S:X}", StringComparison.Ordinal));

        sink.Events.Clear();
        pipeline.Apply(new ButtonChanged(RemoteControl.Siri, true), 1);
        pipeline.Apply(new ButtonChanged(RemoteControl.Siri, false), 1.4);
        Assert.Equal(["hold:A3:down", "hold:A3:up"], sink.Events);
    }

    [Fact]
    public void Touch_bytes_move_the_pointer_and_noise_does_not()
    {
        var sink = new RecordingSink();
        var pipeline = new InputPipeline(sink, new MappingStore(), new AppSettings { PressToDrag = false }, () => null);
        var router = new ReportRouter();
        foreach (var report in new byte[][]
                 {
                     Touch(0x00, 0x00, 0x00),
                     Touch(0x40, 0x00, 0x00),
                     Touch(0x80, 0x00, 0x00),
                 })
        {
            foreach (var remoteEvent in router.Push("hid", report, null))
            {
                pipeline.Apply(remoteEvent, 0.05);
            }
        }

        Assert.True(sink.MoveX != 0 || sink.Events.Exists(item => item.StartsWith("move:", StringComparison.Ordinal)));

        var before = sink.Events.Count;
        foreach (var remoteEvent in router.Push("hid", [9, 8, 7, 6, 5, 4, 3, 2], null))
        {
            pipeline.Apply(remoteEvent, 1);
        }

        Assert.Equal(before, sink.Events.Count);
    }

    [Fact]
    public void Down_double_press_types_the_ideographic_comma()
    {
        var sink = new RecordingSink();
        var pipeline = new InputPipeline(sink, new MappingStore(), new AppSettings(), () => null);
        pipeline.Apply(new ButtonChanged(RemoteControl.Down, true), 0);
        pipeline.Apply(new ButtonChanged(RemoteControl.Down, false), 0.05);
        pipeline.Apply(new ButtonChanged(RemoteControl.Down, true), 0.20);
        pipeline.Apply(new ButtonChanged(RemoteControl.Down, false), 0.25);
        Assert.Contains("text:，", sink.Events);
    }

    [Fact]
    public void Config_round_trip_migrates_old_defaults_and_keeps_profiles()
    {
        var directory = Path.Combine(Path.GetTempPath(), "boss-remote-tests-" + Guid.NewGuid().ToString("N"));
        var path = Path.Combine(directory, "config.json");
        var settings = new AppSettings { PointerSpeed = 1.4, Appearance = "light", PressToDrag = false };
        var mappings = new MappingStore();
        mappings.SetAction(RemoteControl.Tv, ButtonAction.MouseClick);
        mappings.Ensure("code.exe", "Code");
        mappings.SetHoldAction(RemoteControl.Select, ButtonAction.HoldLeftButton, "code.exe");
        var history = new HistoryStore();
        history.Record(new ActivityEvent(DateTime.UnixEpoch, ActivityKind.Button, RemoteControl.Back, "退格", null, null));
        ConfigFile.Save(path, settings, mappings, history, [new BatterySample(DateTime.UnixEpoch, 40, BatteryChargeState.OnBattery)]);

        var loaded = ConfigFile.Load(path);
        Assert.Equal(1.4, loaded.Settings.PointerSpeed);
        Assert.Equal("light", loaded.Settings.Appearance);
        Assert.Equal(ActionKind.MouseClick, loaded.Mappings.Action(RemoteControl.Tv).Kind);
        Assert.Equal(ActionKind.HoldLeftButton, loaded.Mappings.HoldAction(RemoteControl.Select, "code.exe").Kind);
        Assert.Single(loaded.History.Events);
        Assert.Equal(40, loaded.Battery[0].Level);

        loaded.Mappings.DefaultsVersion = 2;
        loaded.Mappings.Actions[RemoteControl.Back] = ButtonAction.FromKey(KeyBinding.Escape);
        loaded.Mappings.MigrateDefaults();
        Assert.Equal(KeyBinding.Delete, loaded.Mappings.Action(RemoteControl.Back).Key);
        Directory.Delete(directory, true);
    }

    [Fact]
    public void Battery_rate_uses_a_real_rise_and_history_merges_repeats()
    {
        var battery = new BatteryInsights();
        var start = new DateTime(2026, 11, 8, 0, 0, 0, DateTimeKind.Utc);
        battery.SetConnected(true, 40, start);
        battery.Update(50, BatteryChargeState.Charging, start.AddMinutes(10));
        var rate = battery.ChargeRatePerHour(start.AddMinutes(10));
        Assert.NotNull(rate);
        Assert.InRange(rate!.Value, 50, 70);
        Assert.True(battery.IsCharging);

        var history = new HistoryStore();
        var first = new DateTime(2026, 11, 8, 1, 0, 0, DateTimeKind.Utc);
        history.Record(new ActivityEvent(first, ActivityKind.Button, RemoteControl.Up, "↑", "a", null));
        history.Record(new ActivityEvent(first.AddMilliseconds(200), ActivityKind.Button, RemoteControl.Up, "↑", "a", null));
        Assert.Single(history.Events);
        Assert.Equal(2, history.Events[0].Count);
    }

    private static byte[] Touch(byte x0, byte x1, byte y)
    {
        return [0x32, 0x00, 0x00, 0x01, x0, x1, y, 0x20, 0x10, 0x01, 0x08];
    }
}
