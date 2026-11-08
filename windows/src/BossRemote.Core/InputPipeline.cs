namespace BossRemote.Core;

public interface IPointerSink
{
    void Move(int dx, int dy);
    void Scroll(int pixels);
    void Click();
    void SetLeftButton(bool down);
    void Press(KeyChord chord);
    void SetSustained(KeyChord chord, bool down);
    void Type(string text);
}

public sealed record FiredAction(RemoteControl Control, ButtonAction Action, bool Hold, string? AppId);

public sealed class HoldDispatcher
{
    public const double ThresholdSeconds = 0.5;
    private Pending? pending;

    public IReadOnlyList<FiredAction> OnButton(
        RemoteControl control,
        bool down,
        double now,
        string? appId,
        MappingStore mappings)
    {
        if (down)
        {
            var tap = mappings.Action(control, appId);
            var hold = mappings.HoldAction(control, appId);
            pending = null;
            if (hold.IsNone)
            {
                return [new FiredAction(control, tap, false, appId)];
            }

            pending = new Pending(control, tap, hold, appId, now + ThresholdSeconds);
            return [];
        }

        if (pending is not { } current || current.Control != control)
        {
            return [];
        }

        pending = null;
        return [new FiredAction(control, current.Tap, false, current.AppId)];
    }

    public IReadOnlyList<FiredAction> Advance(double now)
    {
        if (pending is not { } current || now < current.Due)
        {
            return [];
        }

        pending = null;
        return [new FiredAction(current.Control, current.Hold, true, current.AppId)];
    }

    private sealed record Pending(
        RemoteControl Control,
        ButtonAction Tap,
        ButtonAction Hold,
        string? AppId,
        double Due);
}

/// <summary>
/// 把真实报告事件接到映射、手势和输出。没有报告就不会移动指针。
/// </summary>
public sealed class InputPipeline
{
    private readonly IPointerSink sink;
    private readonly MappingStore mappings;
    private readonly AppSettings settings;
    private readonly HistoryStore? history;
    private readonly Func<string?> foregroundAppId;
    private readonly HoldDispatcher holds = new();
    private readonly GestureEngine gestures = new();
    private readonly Dictionary<RemoteControl, double> lastDown = [];
    private RemoteControl? leftHeldBy;

    public InputPipeline(
        IPointerSink sink,
        MappingStore mappings,
        AppSettings settings,
        Func<string?> foregroundAppId,
        HistoryStore? history = null)
    {
        this.sink = sink;
        this.mappings = mappings;
        this.settings = settings;
        this.foregroundAppId = foregroundAppId;
        this.history = history;
        gestures.OnPointer = (dx, dy) =>
        {
            if (settings.PointerEnabled)
            {
                sink.Move(dx, dy);
            }
        };
        gestures.OnScroll = pixels =>
        {
            if (settings.ScrollEnabled && pixels != 0)
            {
                sink.Scroll(pixels);
            }
        };
        gestures.OnClick = () => sink.Click();
        gestures.OnDrag = down => sink.SetLeftButton(down);
        gestures.OnSwipe = (direction, fromRing) => RunGesture(GestureControl(direction, fromRing));
        gestures.OnDoubleTap = () => RunGesture(RemoteControl.TapTwo);
        gestures.OnJump = _ => { };
        gestures.DoubleTapAvailable = () =>
            !mappings.Action(RemoteControl.TapTwo, CurrentApp()).IsNone;
    }

    public GestureEngine Gestures => gestures;

    public void Apply(RemoteEvent remoteEvent, double now)
    {
        CopyGestureSettings();
        switch (remoteEvent)
        {
            case ButtonChanged(var control, var down):
                OnButton(control, down, now);
                break;
            case TouchFrame(var contacts):
                gestures.Handle(contacts, now);
                break;
        }
    }

    public void Advance(double now)
    {
        CopyGestureSettings();
        gestures.Advance(now);
        foreach (var fired in holds.Advance(now))
        {
            Execute(fired, now);
        }
    }

    private void OnButton(RemoteControl control, bool down, double now)
    {
        var appId = CurrentApp();
        var doublePress = false;
        if (down)
        {
            doublePress = lastDown.TryGetValue(control, out var previous) && now - previous <= 0.35;
            lastDown[control] = now;
        }

        if (control == RemoteControl.Siri)
        {
            if (settings.SiriSustainedKey)
            {
                sink.SetSustained(
                    new KeyChord(settings.SiriVirtualKey, KeyModifiers.None, settings.SiriVirtualKey == Vk.RControl),
                    down);
            }

            return;
        }

        var tap = mappings.Action(control, appId);
        if (tap.Kind == ActionKind.HoldLeftButton && mappings.HoldAction(control, appId).IsNone)
        {
            sink.SetLeftButton(down);
            leftHeldBy = down ? control : null;
            if (down)
            {
                Remember(new FiredAction(control, tap, false, appId));
            }

            return;
        }

        foreach (var fired in holds.OnButton(control, down, now, appId, mappings))
        {
            Execute(fired, now, doublePress);
        }

        if (!down && leftHeldBy == control)
        {
            sink.SetLeftButton(false);
            leftHeldBy = null;
        }
    }

    private void Execute(FiredAction fired, double now, bool doublePress = false)
    {
        if (fired.Action.Kind == ActionKind.HoldLeftButton)
        {
            sink.SetLeftButton(true);
            leftHeldBy = fired.Control;
            Remember(fired);
            return;
        }

        if (!fired.Action.IsNone)
        {
            Dispatch(fired.Action);
            Remember(fired);
        }

        if (doublePress && fired.Control == RemoteControl.Down && !fired.Hold)
        {
            sink.Type("，");
        }
    }

    private void Dispatch(ButtonAction action)
    {
        switch (action.Kind)
        {
            case ActionKind.MouseClick:
                sink.Click();
                break;
            case ActionKind.Key when action.Key is { } key && KeyCatalog.TryGetChord(key, out var chord):
                sink.Press(chord);
                break;
        }
    }

    private void RunGesture(RemoteControl control)
    {
        var appId = CurrentApp();
        var action = mappings.Action(control, appId);
        if (action.IsNone)
        {
            return;
        }

        Dispatch(action);
        Remember(new FiredAction(control, action, false, appId));
    }

    private void Remember(FiredAction fired)
    {
        if (!settings.HistoryEnabled || history == null)
        {
            return;
        }

        history.Record(new ActivityEvent(
            DateTime.UtcNow,
            ActivityKind.Button,
            fired.Control,
            fired.Action.Label,
            fired.AppId,
            fired.Hold ? "长按" : null));
    }

    private void CopyGestureSettings()
    {
        gestures.PointerEnabled = settings.PointerEnabled;
        gestures.ScrollEnabled = settings.ScrollEnabled;
        gestures.TapEnabled = settings.TapToClick;
        gestures.PressFreezeEnabled = settings.PressFreeze;
        gestures.PressToDrag = settings.PressToDrag;
        gestures.InvertPointerY = settings.InvertPointerY;
        gestures.InvertScroll = settings.InvertScroll;
        gestures.PointerSpeed = settings.PointerSpeed;
        gestures.ScrollSpeed = settings.ScrollSpeed;
    }

    private string? CurrentApp()
    {
        var id = foregroundAppId();
        return string.IsNullOrWhiteSpace(id) ? null : id;
    }

    private static RemoteControl GestureControl(SwipeDirection direction, bool fromRing) => direction switch
    {
        SwipeDirection.Up => fromRing ? RemoteControl.RingUp : RemoteControl.SwipeUp,
        SwipeDirection.Down => fromRing ? RemoteControl.RingDown : RemoteControl.SwipeDown,
        SwipeDirection.Left => fromRing ? RemoteControl.RingLeft : RemoteControl.SwipeLeft,
        SwipeDirection.Right => fromRing ? RemoteControl.RingRight : RemoteControl.SwipeRight,
        _ => RemoteControl.SwipeUp,
    };
}
