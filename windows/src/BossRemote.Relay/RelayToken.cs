using System.Security.Cryptography;

namespace BossRemote.Relay;

public sealed class RelayTokenException : Exception
{
    public RelayTokenException(string message) : base(message)
    {
    }
}

public static class RelayToken
{
    public static bool IsWellFormed(string token)
    {
        if (token.Length is < 16 or > 128)
        {
            return false;
        }

        foreach (var ch in token)
        {
            if (ch is not ((>= '0' and <= '9') or (>= 'a' and <= 'z') or (>= 'A' and <= 'Z')))
            {
                return false;
            }
        }

        return true;
    }

    public static void CreateFile(string path)
    {
        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant();
        var temp = path + ".tmp";
        File.WriteAllText(temp, token + "\n");
        TryRestrict(temp);
        File.Move(temp, path, overwrite: true);
        TryRestrict(path);
    }

    public static string Load(string path)
    {
        if (!File.Exists(path))
        {
            throw new RelayTokenException("token file is missing");
        }

        EnsurePrivate(path);
        var token = File.ReadAllText(path).Trim();
        if (!IsWellFormed(token))
        {
            throw new RelayTokenException("token file must contain 16 to 128 letters or digits");
        }

        return token;
    }

    private static void EnsurePrivate(string path)
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        var mode = File.GetUnixFileMode(path);
        const UnixFileMode risky =
            UnixFileMode.GroupRead | UnixFileMode.GroupWrite | UnixFileMode.GroupExecute |
            UnixFileMode.OtherRead | UnixFileMode.OtherWrite | UnixFileMode.OtherExecute;
        if ((mode & risky) != 0)
        {
            throw new RelayTokenException("token file is readable by the group or other users");
        }
    }

    private static void TryRestrict(string path)
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite);
    }
}
