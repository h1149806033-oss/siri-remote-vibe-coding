namespace BossRemote.Core;

/// <summary>
/// macOS 端用 MultitouchSupport 的归一化坐标标定过第 3 代触控圆盘。
/// 这些常数与 Swift <c>TouchGeometry</c> 一致，只用于同一套传感器坐标。
/// Windows 从公开的 A2854 原始触控报文换算到以圆心为 0.5 的 0..1 坐标，
/// 不再套这层仿射，避免标定被做两次。
/// </summary>
public static class TouchGeometry
{
    public const double XAtLeft = 0.068;
    public const double XAtRight = 0.902;
    public const double YAtBottom = 0.025;
    public const double YAtTop = 0.892;
    public const double RingRadius = 0.40;
    public const double RingExitRadius = 0.28;

    public static (double X, double Y) NormalizeMultitouch(double x, double y) =>
    (
        Math.Clamp((x - XAtLeft) / (XAtRight - XAtLeft), 0, 1),
        Math.Clamp((YAtTop - y) / (YAtTop - YAtBottom), 0, 1)
    );

    public static double Radius(double x, double y)
    {
        var dx = x - 0.5;
        var dy = y - 0.5;
        return Math.Sqrt(dx * dx + dy * dy);
    }

    public static bool IsOnRing(double x, double y, bool alreadyOnRing) =>
        Radius(x, y) >= (alreadyOnRing ? RingExitRadius : RingRadius);
}

public readonly record struct Contact(int Id, double X, double Y, double Size);
