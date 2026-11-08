using System.Runtime.InteropServices;
using BossRemote.Core;

namespace BossRemote.Windows;

internal sealed class HidSession : IDisposable
{
    private const uint GenericRead = 0x80000000;
    private const uint GenericWrite = 0x40000000;
    private const uint Share = 0x3;
    private const uint OpenExisting = 3;
    private const int DigcfPresent = 0x2;
    private const int DigcfDeviceInterface = 0x10;
    private const uint GetReportDescriptor = 0x000B0007;

    private readonly List<Reader> readers = [];
    private readonly object gate = new();
    private bool running;

    public event Action<string, byte[], byte[]?>? Report;
    public event Action<string>? Log;
    public event Action<int>? InterfacesChanged;

    public void Start()
    {
        lock (gate)
        {
            if (running)
            {
                return;
            }

            running = true;
        }

        Rescan();
    }

    public void Rescan()
    {
        List<string> paths;
        try
        {
            paths = EnumeratePaths();
        }
        catch (Exception ex)
        {
            Log?.Invoke("枚举 HID 失败：" + ex.Message);
            return;
        }

        List<string> fresh;
        lock (gate)
        {
            if (!running)
            {
                return;
            }

            var known = readers.Select(reader => reader.Path).ToHashSet(StringComparer.OrdinalIgnoreCase);
            fresh = paths.Where(path => !known.Contains(path) && IsA2854Path(path)).ToList();
        }

        foreach (var path in fresh)
        {
            Open(path);
        }

        InterfacesChanged?.Invoke(InterfaceCount);
    }

    public int InterfaceCount
    {
        get
        {
            lock (gate)
            {
                return readers.Count(reader => reader.Alive);
            }
        }
    }

    public void Dispose()
    {
        lock (gate)
        {
            running = false;
            foreach (var reader in readers)
            {
                reader.Dispose();
            }

            readers.Clear();
        }
    }

    private static bool IsA2854Path(string path)
    {
        var value = path.ToLowerInvariant();
        return value.Contains("vid_004c", StringComparison.Ordinal) &&
               value.Contains("pid_0315", StringComparison.Ordinal);
    }

    private void Open(string path)
    {
        var handle = CreateFile(path, GenericRead | GenericWrite, Share, 0, OpenExisting, 0, 0);
        if (handle == -1)
        {
            handle = CreateFile(path, GenericRead, Share, 0, OpenExisting, 0, 0);
        }

        if (handle == -1)
        {
            Log?.Invoke($"打开 HID 失败 {path} Win32={Marshal.GetLastWin32Error()}");
            return;
        }

        var attributes = new HiddAttributes { Size = Marshal.SizeOf<HiddAttributes>() };
        if (!HidD_GetAttributes(handle, ref attributes) ||
            attributes.VendorID != HidUsageMap.VendorId ||
            attributes.ProductID != HidUsageMap.ProductId)
        {
            _ = CloseHandle(handle);
            return;
        }

        var descriptor = ReadDescriptor(handle);
        var reader = new Reader(path, handle, this);
        lock (gate)
        {
            if (!running)
            {
                _ = CloseHandle(handle);
                return;
            }

            readers.Add(reader);
        }

        reader.Start();
        Log?.Invoke(
            $"已打开 A2854 接口 VID={attributes.VendorID:X4} PID={attributes.ProductID:X4} " +
            $"描述符={(descriptor == null ? "没有" : descriptor.Length + " 字节")}");
        Report?.Invoke(path, [], descriptor);
    }

    private void OnReport(string path, byte[] data) => Report?.Invoke(path, data, null);

    private void OnReaderStopped(Reader reader)
    {
        lock (gate)
        {
            readers.Remove(reader);
        }

        var count = InterfaceCount;
        Log?.Invoke("HID 接口已断开");
        InterfacesChanged?.Invoke(count);
    }

    private static byte[]? ReadDescriptor(nint handle)
    {
        var buffer = new byte[4096];
        if (!DeviceIoControl(handle, GetReportDescriptor, 0, 0, buffer, (uint)buffer.Length, out var returned, 0) ||
            returned == 0)
        {
            return null;
        }

        return buffer.AsSpan(0, (int)returned).ToArray();
    }

    private static List<string> EnumeratePaths()
    {
        HidD_GetHidGuid(out var guid);
        var list = SetupDiGetClassDevs(ref guid, null, 0, DigcfPresent | DigcfDeviceInterface);
        if (list == -1)
        {
            return [];
        }

        try
        {
            var paths = new List<string>();
            var data = new SpDeviceInterfaceData();
            for (uint index = 0; ; index++)
            {
                data.cbSize = Marshal.SizeOf<SpDeviceInterfaceData>();
                if (!SetupDiEnumDeviceInterfaces(list, 0, ref guid, index, ref data))
                {
                    break;
                }

                var path = DetailPath(list, ref data);
                if (!string.IsNullOrWhiteSpace(path))
                {
                    paths.Add(path);
                }
            }

            return paths;
        }
        finally
        {
            _ = SetupDiDestroyDeviceInfoList(list);
        }
    }

    private static string? DetailPath(nint list, ref SpDeviceInterfaceData data)
    {
        _ = SetupDiGetDeviceInterfaceDetail(list, ref data, 0, 0, out var required, 0);
        if (required < 8)
        {
            return null;
        }

        var buffer = Marshal.AllocHGlobal((int)required);
        try
        {
            Marshal.WriteInt32(buffer, nint.Size == 8 ? 8 : 6);
            if (!SetupDiGetDeviceInterfaceDetail(list, ref data, buffer, required, out _, 0))
            {
                return null;
            }

            return Marshal.PtrToStringUni(buffer + 4);
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    private sealed class Reader : IDisposable
    {
        private readonly nint handle;
        private readonly HidSession owner;
        private readonly CancellationTokenSource cancel = new();
        public string Path { get; }
        public bool Alive { get; private set; } = true;

        public Reader(string path, nint handle, HidSession owner)
        {
            Path = path;
            this.handle = handle;
            this.owner = owner;
        }

        public void Start()
        {
            var thread = new Thread(Loop) { IsBackground = true, Name = "BossRemote HID" };
            thread.Start();
        }

        private void Loop()
        {
            var buffer = new byte[128];
            while (!cancel.IsCancellationRequested)
            {
                if (!ReadFile(handle, buffer, (uint)buffer.Length, out var read, 0) || read == 0)
                {
                    break;
                }

                var copy = buffer.AsSpan(0, (int)read).ToArray();
                owner.OnReport(Path, copy);
            }

            Alive = false;
            owner.OnReaderStopped(this);
        }

        public void Dispose()
        {
            cancel.Cancel();
            _ = CancelIoEx(handle, 0);
            _ = CloseHandle(handle);
        }
    }

    [DllImport("hid.dll")]
    private static extern void HidD_GetHidGuid(out Guid guid);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_GetAttributes(nint handle, ref HiddAttributes attributes);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint SetupDiGetClassDevs(ref Guid guid, string? enumerator, nint parent, int flags);

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiEnumDeviceInterfaces(
        nint list, nint device, ref Guid guid, uint index, ref SpDeviceInterfaceData data);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SetupDiGetDeviceInterfaceDetail(
        nint list, ref SpDeviceInterfaceData data, nint detail, uint size, out uint required, nint device);

    [DllImport("setupapi.dll")]
    private static extern bool SetupDiDestroyDeviceInfoList(nint list);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint CreateFile(
        string name, uint access, uint share, nint security, uint disposition, uint flags, nint template);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool ReadFile(nint handle, byte[] buffer, uint count, out uint read, nint overlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool DeviceIoControl(
        nint handle, uint code, nint input, uint inputSize, byte[] output, uint outputSize, out uint returned, nint overlapped);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(nint handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CancelIoEx(nint handle, nint overlapped);

    [StructLayout(LayoutKind.Sequential)]
    private struct HiddAttributes
    {
        public int Size;
        public ushort VendorID;
        public ushort ProductID;
        public ushort VersionNumber;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SpDeviceInterfaceData
    {
        public int cbSize;
        public Guid InterfaceClassGuid;
        public int Flags;
        public nint Reserved;
    }
}
