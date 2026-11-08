using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32;

namespace BossRemote.Windows;

internal static class ForegroundProcess
{
    public static string? ExecutablePath()
    {
        var hwnd = GetForegroundWindow();
        if (hwnd == 0)
        {
            return null;
        }

        _ = GetWindowThreadProcessId(hwnd, out var pid);
        if (pid == 0)
        {
            return null;
        }

        var handle = OpenProcess(0x1000, false, pid);
        if (handle == 0)
        {
            return null;
        }

        try
        {
            var buffer = new StringBuilder(1024);
            var size = buffer.Capacity;
            return QueryFullProcessImageName(handle, 0, buffer, ref size) ? buffer.ToString() : null;
        }
        finally
        {
            _ = CloseHandle(handle);
        }
    }

    [DllImport("user32.dll")]
    private static extern nint GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint hwnd, out uint pid);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern nint OpenProcess(uint access, bool inherit, uint pid);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool QueryFullProcessImageName(nint handle, int flags, StringBuilder buffer, ref int size);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(nint handle);
}

internal static class StartupRegistration
{
    private const string Name = "BossRemote";

    public static void Set(bool enabled)
    {
        using var key = Registry.CurrentUser.OpenSubKey(
            @"Software\Microsoft\Windows\CurrentVersion\Run",
            writable: true);
        if (key == null)
        {
            return;
        }

        if (!enabled)
        {
            key.DeleteValue(Name, throwOnMissingValue: false);
            return;
        }

        var path = Environment.ProcessPath;
        if (!string.IsNullOrWhiteSpace(path))
        {
            key.SetValue(Name, $"\"{path}\"");
        }
    }
}
