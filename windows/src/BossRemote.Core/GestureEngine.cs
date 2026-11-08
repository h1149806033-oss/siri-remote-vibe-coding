namespace BossRemote.Core;

public enum SwipeDirection
{
    Up,
    Down,
    Left,
    Right,
}

/// <summary>
/// 触控手势。时间由调用方传入，便于测试。
/// 指针的 Y 按 Windows 屏幕坐标（向下为正）：手指朝遥控器上方移动时 dy 为负，光标向上。
/// 这是给 Windows 的方向，不是把 macOS Y 轴公式原样贴过来。
/// </summary>
public sealed class GestureEngine
{
    private const double PointerScale = 320;
    private const double MotionThreshold = 0.0007;
    private const double TapMaximumDuration = 0.24;
    private const double TapMaximumDistance = 0.03;
    private const double ScrollStartThreshold = 0.22;
    private const double ScrollGainSlow = 110;
    private const double ScrollGainFast = 460;
    private const double ScrollSpeedLow = 0.8;
    private const double ScrollSpeedHigh = 9;
    private const double ScrollEase = 0.55;
    private const double ClickRiseRatio = 0.60;
    private const double PressMaxTravel = 0.02;
    private const double PressWindow = 0.12;
    private const double PressMoveMax = 0.025;
    private const double SwipeMinimumDistance = 0.12;
    private const double SwipeMinimumSpeed = 1.2;
    private const double DoubleTapWindow = 0.28;
    private const double JumpBand = 0.26;
    private const int JumpPixels = 24_000;

    public bool PointerEnabled { get; set; } = true;
    public bool ScrollEnabled { get; set; } = true;
    public bool TapEnabled { get; set; } = true;
    public bool PressFreezeEnabled { get; set; }
    public bool PressToDrag { get; set; } = true;
    public bool InvertPointerY { get; set; }
    public bool InvertScroll { get; set; }
    public double PointerSpeed { get; set; } = 1;
    public double ScrollSpeed { get; set; } = 1;
    public Func<bool>? DoubleTapAvailable { get; set; }

    public Action<int, int>? OnPointer { get; set; }
    public Action<int>? OnScroll { get; set; }
    public Action? OnClick { get; set; }
    public Action<bool>? OnDrag { get; set; }
    public Action<SwipeDirection, bool>? OnSwipe { get; set; }
    public Action? OnDoubleTap { get; set; }
    public Action<bool>? OnJump { get; set; }

    private bool touching;
    private double startedAt;
    private double lastFrameAt;
    private (double X, double Y)? lastPoint;
    private (double X, double Y)? startPoint;
    private double? lastAngle;
    private bool tapCandidate;
    private double tapTravel;
    private bool didMoveOrScroll;
    private bool circular;
    private bool startedOnRing;
    private readonly List<(double Time, double Distance)> velocitySamples = [];
    private double smoothedX;
    private double smoothedY;
    private bool hasMotion;
    private double residualX;
    private double residualY;
    private bool scrollStarted;
    private double scrollArmed;
    private double scrollTarget;
    private double scrollSmoothed;
    private double scrollVelocity;
    private double angularSpeed;
    private double inertiaVelocity;
    private bool inertiaRunning;
    private double lastPump;
    private bool hasPump;
    private readonly List<PressSample> pressSamples = [];
    private bool pressFrozen;
    private (double X, double Y)? freezeOrigin;
    private bool dragging;
    private PendingTap? pendingTap;

    public void Handle(IReadOnlyList<Contact> contacts, double now)
    {
        Pump(now);
        if (contacts.Count == 0)
        {
            Finish(now);
            return;
        }

        var point = Average(contacts);
        var size = contacts.Average(contact => contact.Size);
        if (!touching)
        {
            Begin(point, size, contacts.Count, now);
            return;
        }

        Update(point, size, now);
    }

    public void Advance(double now) => Pump(now);

    private void Begin((double X, double Y) point, double size, int count, double now)
    {
        touching = true;
        startedAt = now;
        lastFrameAt = now;
        lastPoint = point;
        startPoint = point;
        lastAngle = Math.Atan2(point.Y - 0.5, point.X - 0.5);
        tapCandidate = count == 1;
        tapTravel = 0;
        didMoveOrScroll = false;
        circular = false;
        startedOnRing = TouchGeometry.IsOnRing(point.X, point.Y, false);
        velocitySamples.Clear();
        smoothedX = smoothedY = 0;
        hasMotion = false;
        residualX = residualY = 0;
        scrollStarted = false;
        scrollArmed = scrollTarget = scrollSmoothed = scrollVelocity = angularSpeed = 0;
        pressSamples.Clear();
        pressFrozen = false;
        freezeOrigin = null;
        StopDrag();
        StopInertia();
        if (pendingTap != null)
        {
            pendingTap.Cancelled = true;
        }
    }

    private void Update((double X, double Y) point, double size, double now)
    {
        if (lastPoint is not { } previous)
        {
            return;
        }

        var dx = point.X - previous.X;
        var dy = point.Y - previous.Y;
        var dt = lastFrameAt > 0 ? Math.Clamp(now - lastFrameAt, 1.0 / 240, 1.0 / 30) : 1.0 / 60;
        lastPoint = point;
        lastFrameAt = now;
        UpdatePress(size, point, now);

        var onRing = TouchGeometry.IsOnRing(point.X, point.Y, circular);
        if (onRing != circular)
        {
            circular = onRing;
            lastAngle = Math.Atan2(point.Y - 0.5, point.X - 0.5);
            scrollStarted = false;
            scrollArmed = scrollVelocity = angularSpeed = scrollTarget = scrollSmoothed = 0;
            return;
        }

        if (circular)
        {
            UpdateCircular(point, dt);
            return;
        }

        var elapsed = now - startedAt;
        var distance = startPoint is { } start
            ? Hypot(point.X - start.X, point.Y - start.Y)
            : double.PositiveInfinity;
        if (tapCandidate && (elapsed > TapMaximumDuration || distance > TapMaximumDistance))
        {
            tapCandidate = false;
        }

        var moved = Hypot(dx, dy);
        if (moved < MotionThreshold)
        {
            return;
        }

        tapTravel += moved;
        if (tapCandidate)
        {
            if (tapTravel > TapMaximumDistance)
            {
                tapCandidate = false;
                didMoveOrScroll = true;
            }
        }
        else
        {
            didMoveOrScroll = true;
        }

        if (!PointerEnabled || pressFrozen)
        {
            return;
        }

        var velocity = UpdateVelocity(moved, now);
        var gain = PointerGain(velocity);
        var outX = dx * PointerScale * gain * PointerSpeed;
        var outY = -dy * PointerScale * gain * PointerSpeed;
        if (InvertPointerY)
        {
            outY = -outY;
        }

        var speedT = Math.Clamp((velocity - 0.15) / 1.35, 0, 1);
        var referenceAlpha = 0.60 + 0.40 * speedT;
        var alpha = 1 - Math.Pow(1 - referenceAlpha, dt * 60);
        if (hasMotion)
        {
            smoothedX = alpha * outX + (1 - alpha) * smoothedX;
            smoothedY = alpha * outY + (1 - alpha) * smoothedY;
        }
        else
        {
            smoothedX = outX;
            smoothedY = outY;
            hasMotion = true;
        }

        EmitPointer(smoothedX, smoothedY);
    }

    private void UpdateCircular((double X, double Y) point, double dt)
    {
        var angle = Math.Atan2(point.Y - 0.5, point.X - 0.5);
        if (lastAngle is not { } previousAngle)
        {
            lastAngle = angle;
            return;
        }

        lastAngle = angle;
        var delta = angle - previousAngle;
        if (delta > Math.PI) delta -= 2 * Math.PI;
        if (delta < -Math.PI) delta += 2 * Math.PI;
        if (Math.Abs(delta) >= Math.PI)
        {
            return;
        }

        tapCandidate = false;
        didMoveOrScroll = true;
        if (!ScrollEnabled)
        {
            return;
        }

        var step = Math.Max(dt, 1.0 / 120);
        var frameSpeed = Math.Abs(delta) / step;
        angularSpeed = angularSpeed == 0 ? frameSpeed : angularSpeed * 0.72 + frameSpeed * 0.28;
        var gain = ScrollGain(angularSpeed);
        var frameDelta = delta;
        if (!scrollStarted)
        {
            scrollArmed += frameDelta;
            if (Math.Abs(scrollArmed) < ScrollStartThreshold)
            {
                scrollVelocity *= 0.8;
                return;
            }

            delta = scrollArmed;
            scrollArmed = 0;
            scrollStarted = true;
        }

        var sign = InvertScroll ? -1 : 1;
        var pixels = sign * -delta * gain * ScrollSpeed;
        scrollTarget += pixels;
        scrollVelocity = scrollVelocity * 0.7 + (sign * -frameDelta * gain * ScrollSpeed / step) * 0.3;
        EmitScroll(dt);
    }

    private void Finish(double now)
    {
        if (!touching)
        {
            return;
        }

        var elapsed = now - startedAt;
        if (scrollStarted)
        {
            StartInertia();
        }

        if (Swipe(elapsed) is { } direction)
        {
            OnSwipe?.Invoke(direction, startedOnRing);
            Reset();
            return;
        }

        if (TapEnabled && tapCandidate && !didMoveOrScroll && !dragging && elapsed <= TapMaximumDuration)
        {
            if (pendingTap != null)
            {
                var pending = pendingTap;
                pendingTap = null;
                if (now - pending.At <= DoubleTapWindow)
                {
                    if (pending.Action == TapAction.Double)
                    {
                        OnDoubleTap?.Invoke();
                    }
                    else
                    {
                        Jump(pending.ToTop);
                    }

                    Reset();
                    return;
                }
            }

            var zone = Zone(startPoint);
            TapAction? action = null;
            if (DoubleTapAvailable?.Invoke() == true)
            {
                action = TapAction.Double;
            }
            else if (zone is { } band && ScrollEnabled)
            {
                action = new TapAction(false, band);
            }

            if (action != null)
            {
                pendingTap = new PendingTap(now, action.Value);
            }
            else
            {
                OnClick?.Invoke();
            }
        }

        Reset();
    }

    private void Pump(double now)
    {
        if (!hasPump)
        {
            lastPump = now;
            hasPump = true;
        }

        if (touching && now - lastFrameAt > 0.30)
        {
            Finish(lastFrameAt);
        }

        if (pendingTap is { Cancelled: false } pending && now >= pending.At + DoubleTapWindow)
        {
            pendingTap = null;
            OnClick?.Invoke();
        }
        else if (pendingTap is { Cancelled: true } cancelled && now - cancelled.At > DoubleTapWindow)
        {
            pendingTap = null;
        }

        var elapsed = Math.Max(0, now - lastPump);
        lastPump = now;
        if (!inertiaRunning)
        {
            return;
        }

        var steps = (int)Math.Floor(elapsed / (1.0 / 60.0));
        if (steps == 0 && elapsed > 0)
        {
            steps = 1;
        }

        for (var i = 0; i < Math.Min(steps, 8); i++)
        {
            if (Math.Abs(inertiaVelocity) < 45)
            {
                StopInertia();
                break;
            }

            scrollTarget += inertiaVelocity / 60.0;
            inertiaVelocity *= 0.88;
            EmitScroll(1.0 / 60.0);
        }
    }

    private SwipeDirection? Swipe(double elapsed)
    {
        if (scrollStarted || startPoint is not { } start || lastPoint is not { } end)
        {
            return null;
        }

        var dx = end.X - start.X;
        var dy = end.Y - start.Y;
        var distance = Hypot(dx, dy);
        if (distance < SwipeMinimumDistance)
        {
            return null;
        }

        var duration = Math.Max(0.02, elapsed);
        if (distance / duration < SwipeMinimumSpeed)
        {
            return null;
        }

        if (Math.Abs(dx) >= Math.Abs(dy))
        {
            return dx > 0 ? SwipeDirection.Right : SwipeDirection.Left;
        }

        return dy > 0 ? SwipeDirection.Up : SwipeDirection.Down;
    }

    private void UpdatePress(double size, (double X, double Y) point, double now)
    {
        pressSamples.Add(new PressSample(now, size, point));
        while (pressSamples.Count > 0 && now - pressSamples[0].Time > PressWindow)
        {
            pressSamples.RemoveAt(0);
        }

        if (pressFrozen)
        {
            if (freezeOrigin is not { } origin || Hypot(point.X - origin.X, point.Y - origin.Y) > PressMoveMax)
            {
                pressFrozen = false;
            }

            return;
        }

        if (dragging || pressSamples.Count < 3)
        {
            return;
        }

        var oldest = pressSamples[0];
        var travel = Hypot(point.X - oldest.Point.X, point.Y - oldest.Point.Y);
        if (travel > PressMaxTravel)
        {
            return;
        }

        var rise = (size - oldest.Size) / Math.Max(oldest.Size, 0.02);
        if (rise < ClickRiseRatio)
        {
            return;
        }

        if (PressToDrag)
        {
            dragging = true;
            didMoveOrScroll = true;
            tapCandidate = false;
            OnDrag?.Invoke(true);
            return;
        }

        if (PressFreezeEnabled)
        {
            pressFrozen = true;
            freezeOrigin = point;
        }
    }

    private double UpdateVelocity(double distance, double now)
    {
        velocitySamples.Add((now, distance));
        while (velocitySamples.Count > 2 && now - velocitySamples[0].Time > 0.06)
        {
            velocitySamples.RemoveAt(0);
        }

        if (velocitySamples.Count < 2)
        {
            return distance * 60;
        }

        var span = Math.Max(0.008, velocitySamples[^1].Time - velocitySamples[0].Time);
        double travelled = 0;
        for (var i = 1; i < velocitySamples.Count; i++)
        {
            travelled += velocitySamples[i].Distance;
        }

        return travelled / span;
    }

    private static double PointerGain(double velocity)
    {
        const double minGain = 0.58;
        const double cruiseGain = 0.95;
        const double fastGain = 2.25;
        const double cruiseSpeed = 0.45;
        const double fastSpeed = 5.5;
        if (velocity <= cruiseSpeed)
        {
            var t = Math.Clamp(velocity / cruiseSpeed, 0, 1);
            return minGain + (cruiseGain - minGain) * t;
        }

        var blend = Math.Clamp((velocity - cruiseSpeed) / (fastSpeed - cruiseSpeed), 0, 1);
        var smooth = blend * blend * (3 - 2 * blend);
        var gain = cruiseGain + (fastGain - cruiseGain) * smooth;
        if (velocity > 2.5)
        {
            gain += 0.30 * Math.Log(1 + (velocity - 2.5) * 1.2);
        }

        return Math.Min(2.9, gain);
    }

    private static double ScrollGain(double speed)
    {
        var t = Math.Clamp((speed - ScrollSpeedLow) / (ScrollSpeedHigh - ScrollSpeedLow), 0, 1);
        var smooth = t * t * (3 - 2 * t);
        return ScrollGainSlow + (ScrollGainFast - ScrollGainSlow) * smooth;
    }

    private void EmitPointer(double x, double y)
    {
        residualX += x;
        residualY += y;
        var wholeX = Math.Truncate(residualX);
        var wholeY = Math.Truncate(residualY);
        if (wholeX == 0 && wholeY == 0)
        {
            return;
        }

        residualX -= wholeX;
        residualY -= wholeY;
        OnPointer?.Invoke((int)wholeX, (int)wholeY);
    }

    private void EmitScroll(double dt)
    {
        var eased = 1 - Math.Pow(1 - ScrollEase, dt * 60);
        scrollSmoothed += (scrollTarget - scrollSmoothed) * Math.Clamp(eased, 0.05, 1);
        var whole = Math.Truncate(scrollSmoothed);
        if (whole == 0)
        {
            return;
        }

        scrollSmoothed -= whole;
        scrollTarget -= whole;
        OnScroll?.Invoke((int)whole);
    }

    private void StartInertia()
    {
        if (Math.Abs(scrollVelocity) <= 320)
        {
            return;
        }

        inertiaVelocity = Math.Clamp(scrollVelocity, -2400, 2400);
        inertiaRunning = true;
    }

    private void StopInertia()
    {
        inertiaRunning = false;
        inertiaVelocity = 0;
    }

    private void StopDrag()
    {
        if (!dragging)
        {
            return;
        }

        dragging = false;
        OnDrag?.Invoke(false);
    }

    private void Jump(bool toTop)
    {
        StopInertia();
        scrollTarget = scrollSmoothed = scrollVelocity = 0;
        var sign = toTop ? -1 : 1;
        if (InvertScroll)
        {
            sign = -sign;
        }

        OnScroll?.Invoke(sign * JumpPixels);
        OnScroll?.Invoke(sign * (JumpPixels / 4));
        OnJump?.Invoke(toTop);
    }

    private static bool? Zone((double X, double Y)? point)
    {
        if (point is not { } value)
        {
            return null;
        }

        if (value.Y >= 1 - JumpBand)
        {
            return true;
        }

        if (value.Y <= JumpBand)
        {
            return false;
        }

        return null;
    }

    private void Reset()
    {
        StopDrag();
        touching = false;
        lastPoint = null;
        startPoint = null;
        lastAngle = null;
        tapCandidate = false;
        tapTravel = 0;
        didMoveOrScroll = false;
        circular = false;
        velocitySamples.Clear();
        smoothedX = smoothedY = residualX = residualY = 0;
        hasMotion = false;
        scrollStarted = false;
        scrollArmed = scrollTarget = scrollSmoothed = scrollVelocity = 0;
        pressFrozen = false;
        freezeOrigin = null;
        pressSamples.Clear();
    }

    private static (double X, double Y) Average(IReadOnlyList<Contact> contacts)
    {
        double x = 0, y = 0;
        foreach (var contact in contacts)
        {
            x += contact.X;
            y += contact.Y;
        }

        return (x / contacts.Count, y / contacts.Count);
    }

    private static double Hypot(double x, double y) => Math.Sqrt(x * x + y * y);

    private sealed class PendingTap(double at, TapAction action)
    {
        public double At { get; } = at;
        public TapAction Action { get; } = action;
        public bool Cancelled { get; set; }
        public bool ToTop => Action.ToTop;
    }

    private readonly record struct TapAction(bool IsDouble, bool ToTop)
    {
        public static TapAction Double { get; } = new(true, false);
    }

    private readonly record struct PressSample(double Time, double Size, (double X, double Y) Point);
}
