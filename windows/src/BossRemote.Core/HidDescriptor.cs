namespace BossRemote.Core;

public sealed class HidField
{
    public int ReportId { get; init; }
    public ushort UsagePage { get; init; }
    public ushort Usage { get; init; }
    public int BitOffset { get; init; }
    public int BitSize { get; init; }
    public int LogicalMin { get; init; }
    public int LogicalMax { get; init; }
    public bool Relative { get; init; }
    public ushort CollectionPage { get; init; }
    public ushort CollectionUsage { get; init; }
}

public sealed class DecodedHidReport
{
    public bool Recognized { get; init; }
    public HashSet<RemoteControl> Pressed { get; init; } = [];
    public HashSet<RemoteControl> MentionedButtons { get; init; } = [];
    public bool HasTouchAxes { get; init; }
    public List<Contact> Contacts { get; init; } = [];
    public int? Battery { get; init; }
}

/// <summary>
/// 只实现本遥控器需要的 HID 短项：用法、报告长度、Input 和集合。
/// 描述符来自设备；解析不出坐标时不会补一个触点。
/// </summary>
public sealed class HidReportLayout
{
    private readonly List<HidField> fields = [];

    public bool UsesReportIds { get; private set; }
    public IReadOnlyList<HidField> Fields => fields;

    public static HidReportLayout Parse(ReadOnlySpan<byte> descriptor)
    {
        var layout = new HidReportLayout();
        ushort usagePage = 0;
        int reportSize = 0;
        int reportCount = 0;
        int reportId = 0;
        int logicalMin = 0;
        int logicalMax = 0;
        var usages = new List<ushort>();
        ushort? usageMin = null;
        ushort? usageMax = null;
        var bitCursor = new Dictionary<int, int>();
        var collections = new Stack<(ushort Page, ushort Usage)>();
        var index = 0;

        while (index < descriptor.Length)
        {
            var header = descriptor[index++];
            if (header == 0xFE)
            {
                if (index + 2 > descriptor.Length)
                {
                    break;
                }

                var dataSize = descriptor[index++];
                index++;
                index += dataSize;
                continue;
            }

            var sizeCode = header & 0x03;
            var size = sizeCode == 3 ? 4 : sizeCode;
            var type = (header >> 2) & 0x03;
            var tag = (header >> 4) & 0x0F;
            if (index + size > descriptor.Length)
            {
                break;
            }

            var data = descriptor.Slice(index, size);
            index += size;
            var unsigned = Unsigned(data);
            var signed = SignExtend(data);

            if (type == 1)
            {
                switch (tag)
                {
                    case 0x0: usagePage = (ushort)unsigned; break;
                    case 0x1: logicalMin = signed; break;
                    case 0x2: logicalMax = signed; break;
                    case 0x7: reportSize = unsigned; break;
                    case 0x8:
                        reportId = unsigned;
                        layout.UsesReportIds = true;
                        break;
                    case 0x9: reportCount = unsigned; break;
                }
            }
            else if (type == 2)
            {
                switch (tag)
                {
                    case 0x0: usages.Add((ushort)unsigned); break;
                    case 0x1: usageMin = (ushort)unsigned; break;
                    case 0x2: usageMax = (ushort)unsigned; break;
                }
            }
            else if (type == 0)
            {
                if (tag == 0xA)
                {
                    var usage = usages.Count > 0 ? usages[^1] : (ushort)0;
                    collections.Push((usagePage, usage));
                }
                else if (tag == 0xC)
                {
                    if (collections.Count > 0)
                    {
                        collections.Pop();
                    }
                }
                else if (tag is 0x8 or 0x9 or 0xB)
                {
                    var constant = (unsigned & 0x1) != 0;
                    var relative = (unsigned & 0x4) != 0;
                    var count = Math.Max(reportCount, 0);
                    if (!bitCursor.ContainsKey(reportId))
                    {
                        bitCursor[reportId] = 0;
                    }

                    if (tag == 0x8 && !constant && reportSize > 0 && count > 0)
                    {
                        var collection = collections.Count > 0 ? collections.Peek() : default;
                        for (var i = 0; i < count; i++)
                        {
                            ushort usage = 0;
                            if (usageMin is { } min && usageMax is { } max && max >= min)
                            {
                                var assigned = min + i;
                                usage = (ushort)Math.Min(assigned, max);
                            }
                            else if (usages.Count == 1)
                            {
                                usage = (ushort)(usages[0] + i);
                            }
                            else if (i < usages.Count)
                            {
                                usage = usages[i];
                            }

                            layout.fields.Add(new HidField
                            {
                                ReportId = reportId,
                                UsagePage = usagePage,
                                Usage = usage,
                                BitOffset = bitCursor[reportId],
                                BitSize = reportSize,
                                LogicalMin = logicalMin,
                                LogicalMax = logicalMax,
                                Relative = relative,
                                CollectionPage = collection.Page,
                                CollectionUsage = collection.Usage,
                            });
                            bitCursor[reportId] += reportSize;
                        }
                    }
                    else
                    {
                        bitCursor[reportId] += Math.Max(reportSize, 0) * count;
                    }
                }

                usages.Clear();
                usageMin = null;
                usageMax = null;
            }
        }

        return layout;
    }

    public bool TryDecode(ReadOnlySpan<byte> report, out DecodedHidReport decoded)
    {
        decoded = new DecodedHidReport();
        if (report.IsEmpty || fields.Count == 0)
        {
            return false;
        }

        int reportId;
        ReadOnlySpan<byte> payload;
        if (UsesReportIds)
        {
            reportId = report[0];
            payload = report[1..];
        }
        else
        {
            reportId = 0;
            payload = report;
        }

        var relevant = fields.Where(field => field.ReportId == reportId).ToList();
        if (relevant.Count == 0)
        {
            return false;
        }

        var pressed = new HashSet<RemoteControl>();
        var mentioned = new HashSet<RemoteControl>();
        int? battery = null;
        var contacts = new List<Contact>();
        var hasAxes = false;
        ContactDraft? draft = null;

        void Flush()
        {
            if (draft is not { HasX: true, HasY: true } ready)
            {
                draft = null;
                return;
            }

            if (!ready.TipSeen || ready.TipDown)
            {
                contacts.Add(new Contact(
                    ready.Id,
                    Normalize(ready.X, ready.XMin, ready.XMax),
                    Normalize(ready.Y, ready.YMin, ready.YMax),
                    ready.Size));
            }

            draft = null;
        }

        foreach (var field in relevant)
        {
            var raw = Extract(payload, field.BitOffset, field.BitSize, field.LogicalMin < 0);
            var control = HidUsageMap.Control(field.UsagePage, field.Usage);
            if (control is { } known && !field.Relative)
            {
                mentioned.Add(known);
                if (raw != 0)
                {
                    pressed.Add(known);
                }
            }

            if (field.UsagePage == 0x06 && field.Usage == 0x20)
            {
                battery = HidUsageMap.NormalizeBattery(raw);
            }

            var inDigitizer = field.CollectionPage == 0x0D;
            var isX = field.UsagePage == 0x01 && field.Usage == 0x30 && inDigitizer && !field.Relative;
            var isY = field.UsagePage == 0x01 && field.Usage == 0x31 && inDigitizer && !field.Relative;
            var isTip = field.UsagePage == 0x0D && field.Usage == 0x42;
            var isId = field.UsagePage == 0x0D && field.Usage == 0x51;
            var isSize = field.UsagePage == 0x0D && field.Usage is 0x30 or 0x48;
            if (isX || isY || isTip)
            {
                hasAxes = true;
            }

            if (isTip || (isX && draft is { HasX: true }))
            {
                Flush();
                draft ??= new ContactDraft();
            }

            if (isTip)
            {
                draft ??= new ContactDraft();
                draft.TipSeen = true;
                draft.TipDown = raw != 0;
            }
            else if (isId && draft != null)
            {
                draft.Id = raw;
            }
            else if (isX)
            {
                draft ??= new ContactDraft();
                draft.HasX = true;
                draft.X = raw;
                draft.XMin = field.LogicalMin;
                draft.XMax = field.LogicalMax;
            }
            else if (isY && draft != null)
            {
                draft.HasY = true;
                draft.Y = raw;
                draft.YMin = field.LogicalMin;
                draft.YMax = field.LogicalMax;
            }
            else if (isSize && draft != null && field.LogicalMax > field.LogicalMin)
            {
                draft.Size = Math.Clamp((raw - field.LogicalMin) / (double)(field.LogicalMax - field.LogicalMin), 0, 1);
            }
        }

        Flush();
        var recognized = mentioned.Count > 0 || hasAxes || battery != null;
        decoded = new DecodedHidReport
        {
            Recognized = recognized,
            Pressed = pressed,
            MentionedButtons = mentioned,
            HasTouchAxes = hasAxes,
            Contacts = contacts,
            Battery = battery,
        };
        return recognized;
    }

    private static double Normalize(int value, int min, int max)
    {
        if (max <= min)
        {
            return 0;
        }

        return Math.Clamp((value - min) / (double)(max - min), 0, 1);
    }

    private static int Extract(ReadOnlySpan<byte> payload, int bitOffset, int bitSize, bool signed)
    {
        var value = 0;
        var width = Math.Min(bitSize, 31);
        for (var i = 0; i < width; i++)
        {
            var bit = bitOffset + i;
            var byteIndex = bit / 8;
            if ((uint)byteIndex >= (uint)payload.Length)
            {
                break;
            }

            if ((payload[byteIndex] & (1 << (bit % 8))) != 0)
            {
                value |= 1 << i;
            }
        }

        if (signed && width is > 0 and < 31 && (value & (1 << (width - 1))) != 0)
        {
            value |= -1 << width;
        }

        return value;
    }

    private static int Unsigned(ReadOnlySpan<byte> data)
    {
        var value = 0;
        for (var i = 0; i < data.Length; i++)
        {
            value |= data[i] << (8 * i);
        }

        return value;
    }

    private static int SignExtend(ReadOnlySpan<byte> data)
    {
        var value = Unsigned(data);

        var bits = data.Length * 8;
        if (data.Length is > 0 and < 4 && (value & (1 << (bits - 1))) != 0)
        {
            value |= -1 << bits;
        }

        return value;
    }

    private sealed class ContactDraft
    {
        public bool TipSeen;
        public bool TipDown;
        public bool HasX;
        public bool HasY;
        public int X;
        public int Y;
        public int XMin;
        public int XMax = 1;
        public int YMin;
        public int YMax = 1;
        public int Id;
        public double Size = 0.2;
    }
}
