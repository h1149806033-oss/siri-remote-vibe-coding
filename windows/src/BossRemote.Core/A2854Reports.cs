namespace BossRemote.Core;

/// <summary>
/// 公开逆向记录里的 A2854 原始报文。
/// 按键位来自 Amity / Yanndroid 的第 2 代及以后映射，并与 henaxxx 在 A2854
/// GATT 句柄 0x003a 上观察到的字节对齐（左键位 henaxxx 的样机按坏了，未复核）。
/// 触控布局来自同一来源对 0x32 报告的字段说明。此处只解析字节，不制造输入。
/// </summary>
public static class A2854Reports
{
    public const int TouchResolution = 1370;
    public const int TouchCenter = 360;
    public const int KnownButtonMask = 0x1FFF;

    public const int BitTv = 0x0001;
    public const int BitVolumeUp = 0x0002;
    public const int BitVolumeDown = 0x0004;
    public const int BitSelect = 0x0008;
    public const int BitPower = 0x0010;
    public const int BitSiri = 0x0020;
    public const int BitBack = 0x0040;
    public const int BitMute = 0x0080;
    public const int BitPlayPause = 0x0100;
    public const int BitUp = 0x0200;
    public const int BitRight = 0x0400;
    public const int BitDown = 0x0800;
    public const int BitLeft = 0x1000;

    public static bool TryParseButtons(ReadOnlySpan<byte> report, out int bits)
    {
        bits = 0;
        ReadOnlySpan<byte> body;
        if (report.Length == 2)
        {
            body = report;
        }
        else if (report.Length == 3)
        {
            body = report[1..];
        }
        else
        {
            return false;
        }

        var value = body[0] | (body[1] << 8);
        if ((value & ~KnownButtonMask) != 0)
        {
            return false;
        }

        bits = value;
        return true;
    }

    public static void CollectButtons(int bits, HashSet<RemoteControl> target)
    {
        Add(bits, BitTv, RemoteControl.Tv, target);
        Add(bits, BitVolumeUp, RemoteControl.VolumeUp, target);
        Add(bits, BitVolumeDown, RemoteControl.VolumeDown, target);
        Add(bits, BitSelect, RemoteControl.Select, target);
        Add(bits, BitPower, RemoteControl.Power, target);
        Add(bits, BitSiri, RemoteControl.Siri, target);
        Add(bits, BitBack, RemoteControl.Back, target);
        Add(bits, BitMute, RemoteControl.Mute, target);
        Add(bits, BitPlayPause, RemoteControl.PlayPause, target);
        Add(bits, BitUp, RemoteControl.Up, target);
        Add(bits, BitRight, RemoteControl.Right, target);
        Add(bits, BitDown, RemoteControl.Down, target);
        Add(bits, BitLeft, RemoteControl.Left, target);
    }

    public static bool TryParseTouch(ReadOnlySpan<byte> report, out List<Contact> contacts)
    {
        contacts = [];
        var offset = 0;
        if (report.Length >= 12 && report[0] != 0x32 && report[1] == 0x32)
        {
            offset = 1;
        }

        if (report.Length - offset < 11 || report[offset] != 0x32)
        {
            return false;
        }

        var body = report[offset..];
        AddFinger(body.Slice(4, 7), contacts);
        if (body.Length >= 18)
        {
            AddFinger(body.Slice(11, 7), contacts);
        }

        return true;
    }

    private static void AddFinger(ReadOnlySpan<byte> data, List<Contact> contacts)
    {
        var flags = data[6];
        // 公开注释把 bit1 标成悬停。悬停不是落在板上的接触，不能拿来推动指针。
        if ((flags & 0x02) != 0)
        {
            return;
        }

        var x = DecodeAxis(data, xAxis: true);
        var y = DecodeAxis(data, xAxis: false);
        var sizeByte = data[3] != 0 ? data[3] : data[5];
        var id = 1 - ((flags & 0x08) >> 3);
        contacts.Add(new Contact(
            id,
            Normalize(x),
            Normalize(y),
            sizeByte / 255.0));
    }

    private static int DecodeAxis(ReadOnlySpan<byte> data, bool xAxis)
    {
        int raw = xAxis
            ? ((data[1] & 0x0F) << 8) | data[0]
            : (data[2] << 4) | ((data[1] & 0xF0) >> 4);
        if ((raw & 0x800) != 0)
        {
            raw -= 0x1000;
        }

        return raw + TouchCenter;
    }

    public static double Normalize(int decoded)
    {
        var normalized = 0.5 + (decoded - TouchCenter) / (double)TouchResolution;
        return Math.Clamp(normalized, 0, 1);
    }

    private static void Add(int bits, int mask, RemoteControl control, HashSet<RemoteControl> target)
    {
        if ((bits & mask) != 0)
        {
            target.Add(control);
        }
    }
}

/// <summary>
/// 公开记录的第 3 代语音通知：100 字节，长度前缀的 Opus，TOC 为 0xB8。
/// 只抽出 Opus 包。不解码、不播放、不创建虚拟麦克风。
/// </summary>
public static class SiriVoiceFrame
{
    public static byte[]? TryExtractOpus(ReadOnlySpan<byte> value)
    {
        ReadOnlySpan<int> offsets = [0, 1, 2];
        foreach (var offset in offsets)
        {
            if (offset == 1 && (value.Length == 0 || value[0] != 0xFA))
            {
                continue;
            }

            if (offset == 2 && (value.Length < 2 || value[0] != 0xA1 || value[1] != 0xFA))
            {
                continue;
            }

            var remaining = value.Length - offset;
            if (remaining is < 99 or > 100 || value.Length - offset < 5)
            {
                continue;
            }

            var length = value[offset + 4];
            var start = offset + 5;
            var end = start + length;
            if (length == 0 || end > value.Length || (value[start] & 0xFC) != 0xB8)
            {
                continue;
            }

            for (var i = end; i < value.Length; i++)
            {
                if (value[i] != 0)
                {
                    length = 0;
                    break;
                }
            }

            if (length == 0)
            {
                continue;
            }

            return value.Slice(start, length).ToArray();
        }

        return null;
    }
}
