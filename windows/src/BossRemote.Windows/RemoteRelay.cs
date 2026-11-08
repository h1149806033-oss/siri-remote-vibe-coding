using BossRemote.Core;
using BossRemote.Relay;

namespace BossRemote.Windows;

/// <summary>
/// Forwards events that already came from the HID/GATT reader. It does not invent input.
/// </summary>
internal sealed class RemoteRelay : IAsyncDisposable
{
    private RelayClient? client;

    public async Task StartAsync(Action<string> log)
    {
        await StopAsync();
        var path = Environment.GetEnvironmentVariable("BOSS_REMOTE_RELAY_TOKEN_FILE");
        if (string.IsNullOrWhiteSpace(path))
        {
            log("转发未启动：请设置环境变量 BOSS_REMOTE_RELAY_TOKEN_FILE。token 不会写进配置文件。");
            return;
        }

        string token;
        try
        {
            token = RelayToken.Load(path);
        }
        catch (RelayTokenException ex)
        {
            log("转发未启动：" + ex.Message);
            return;
        }

        var port = 4777;
        if (int.TryParse(Environment.GetEnvironmentVariable("BOSS_REMOTE_RELAY_PORT"), out var parsed) &&
            parsed is >= 1 and <= 65535)
        {
            port = parsed;
        }

        var next = new RelayClient(port, token);
        try
        {
            await next.ConnectAsync();
        }
        catch (RelayException)
        {
            log("转发认证失败。确认本机 127.0.0.1 上的接收端或 SSH 隧道已经打开。");
            await next.DisposeAsync();
            return;
        }
        catch (Exception ex)
        {
            log("转发连接失败：" + ex.GetType().Name);
            await next.DisposeAsync();
            return;
        }

        client = next;
        log($"转发已连接 127.0.0.1:{port}。只发送遥控器按键和触控。");
    }

    public void Forward(RemoteEvent remoteEvent)
    {
        var current = client;
        if (current == null)
        {
            return;
        }

        switch (remoteEvent)
        {
            case ButtonChanged button when RelayCodec.IsPhysical(RemoteCatalog.Id(button.Control)):
                current.SendButton(RemoteCatalog.Id(button.Control), button.Down);
                break;
            case TouchFrame touch:
                current.SendTouch(touch.Contacts.Select(contact => new RelayContact(
                    Math.Clamp(contact.Id, 0, 15),
                    Math.Clamp(contact.X, 0, 1),
                    Math.Clamp(contact.Y, 0, 1),
                    Math.Clamp(contact.Size, 0, 64))).Take(RelayCodec.MaxContacts).ToArray());
                break;
        }
    }

    public async Task StopAsync()
    {
        var current = client;
        client = null;
        if (current != null)
        {
            await current.StopAsync();
        }
    }

    public async ValueTask DisposeAsync() => await StopAsync();
}
