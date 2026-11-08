using System.Globalization;
using System.Text;

namespace BossRemote.Relay;

public readonly record struct RelayContact(int Id, double X, double Y, double Size);

public abstract record RelayMessage;

public sealed record RelayAuth(string Token) : RelayMessage;

public sealed record RelayButton(string Control, bool Down) : RelayMessage;

public sealed record RelayTouch(IReadOnlyList<RelayContact> Contacts) : RelayMessage;

public sealed record RelayPing : RelayMessage;

public sealed record RelayBye : RelayMessage;

/// <summary>
/// 文本行协议。macOS 发送端必须发出同样的行。
/// 只接受 13 个实体键和触控点，不接受手势名、按键扫描码或任意文本。
/// </summary>
public static class RelayCodec
{
    public const int MaxLineLength = 512;
    public const int MaxContacts = 2;

    public static readonly string[] PhysicalControls =
    [
        "power", "up", "down", "left", "right", "select", "back", "tv",
        "play_pause", "volume_up", "volume_down", "mute", "siri",
    ];

    private static readonly HashSet<string> Physical = new(PhysicalControls, StringComparer.Ordinal);

    public static bool IsPhysical(string control) => Physical.Contains(control);

    public static string EncodeAuth(string token) => "AUTH " + token;

    public static string EncodeButton(string control, bool down) =>
        FormattableString.Invariant($"BTN {control} {(down ? 1 : 0)}");

    public static string EncodeTouch(IReadOnlyList<RelayContact> contacts)
    {
        var builder = new StringBuilder();
        builder.Append("TOUCH ").Append(contacts.Count.ToString(CultureInfo.InvariantCulture));
        foreach (var contact in contacts)
        {
            builder.Append(' ').Append(contact.Id.ToString(CultureInfo.InvariantCulture));
            builder.Append(' ').Append(contact.X.ToString("0.0000", CultureInfo.InvariantCulture));
            builder.Append(' ').Append(contact.Y.ToString("0.0000", CultureInfo.InvariantCulture));
            builder.Append(' ').Append(contact.Size.ToString("0.0000", CultureInfo.InvariantCulture));
        }

        return builder.ToString();
    }

    public static string EncodePing() => "PING";

    public static string EncodeBye() => "BYE";

    public static bool TryDecode(string line, out RelayMessage? message)
    {
        message = null;
        if (line.Length == 0 || line.Length > MaxLineLength || line.IndexOf('\0') >= 0)
        {
            return false;
        }

        var parts = line.Split(' ');
        switch (parts[0])
        {
            case "AUTH" when parts.Length == 2 && RelayToken.IsWellFormed(parts[1]):
                message = new RelayAuth(parts[1]);
                return true;
            case "BTN" when parts.Length == 3 && IsPhysical(parts[1]) && parts[2] is "0" or "1":
                message = new RelayButton(parts[1], parts[2] == "1");
                return true;
            case "TOUCH" when TryContacts(parts, out var contacts):
                message = new RelayTouch(contacts);
                return true;
            case "PING" when parts.Length == 1:
                message = new RelayPing();
                return true;
            case "BYE" when parts.Length == 1:
                message = new RelayBye();
                return true;
            default:
                return false;
        }
    }

    private static bool TryContacts(string[] parts, out List<RelayContact> contacts)
    {
        contacts = [];
        if (parts.Length < 2 || !int.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out var count))
        {
            return false;
        }

        if (count is < 0 or > MaxContacts || parts.Length != 2 + count * 4)
        {
            return false;
        }

        for (var i = 0; i < count; i++)
        {
            var offset = 2 + i * 4;
            if (!int.TryParse(parts[offset], NumberStyles.None, CultureInfo.InvariantCulture, out var id) ||
                id is < 0 or > 15 ||
                !double.TryParse(parts[offset + 1], NumberStyles.Float, CultureInfo.InvariantCulture, out var x) ||
                !double.TryParse(parts[offset + 2], NumberStyles.Float, CultureInfo.InvariantCulture, out var y) ||
                !double.TryParse(parts[offset + 3], NumberStyles.Float, CultureInfo.InvariantCulture, out var size) ||
                x is < 0 or > 1 || y is < 0 or > 1 || size is < 0 or > 64 ||
                double.IsNaN(x) || double.IsNaN(y) || double.IsNaN(size))
            {
                return false;
            }

            contacts.Add(new RelayContact(id, x, y, size));
        }

        return true;
    }
}
