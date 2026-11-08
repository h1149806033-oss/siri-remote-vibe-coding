using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;

namespace BossRemote.Relay;

public interface IRelaySink
{
    void OnButton(string control, bool down, bool syntheticRelease);
    void OnTouch(IReadOnlyList<RelayContact> contacts);
    void OnSessionEnd(string reason);
}

public interface IRelayLog
{
    void Info(string message);
}

public sealed record RelayServerOptions(int Port, string Token, int MaxEventsPerSecond = 300, int AuthTimeoutMs = 3000);

/// <summary>
/// 只监听 127.0.0.1。跨机器转发必须由用户自己的 SSH 隧道把远端端口接到这个回环地址。
/// </summary>
public sealed class RelayServer
{
    private readonly RelayServerOptions options;
    private readonly IRelaySink sink;
    private readonly IRelayLog log;
    private TcpListener? listener;
    private int sessionActive;

    public RelayServer(RelayServerOptions options, IRelaySink sink, IRelayLog log)
    {
        if (!RelayToken.IsWellFormed(options.Token))
        {
            throw new RelayTokenException("token file must contain 16 to 128 letters or digits");
        }

        if (options.Port is < 0 or > 65535)
        {
            throw new ArgumentOutOfRangeException(nameof(options));
        }

        this.options = options;
        this.sink = sink;
        this.log = log;
    }

    public IPEndPoint? BoundEndPoint { get; private set; }

    public async Task RunAsync(CancellationToken cancellationToken)
    {
        listener = new TcpListener(IPAddress.Loopback, options.Port);
        listener.Start();
        BoundEndPoint = (IPEndPoint)listener.LocalEndpoint;
        log.Info($"relay listening {BoundEndPoint.Address}:{BoundEndPoint.Port}");
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                TcpClient client;
                try
                {
                    client = await listener.AcceptTcpClientAsync(cancellationToken);
                }
                catch (OperationCanceledException)
                {
                    break;
                }

                if (Interlocked.CompareExchange(ref sessionActive, 1, 0) != 0)
                {
                    Reject(client, "ERR busy");
                    continue;
                }

                _ = Task.Run(() => HandleAsync(client, cancellationToken), cancellationToken);
            }
        }
        finally
        {
            listener.Stop();
        }
    }

    private async Task HandleAsync(TcpClient client, CancellationToken cancellationToken)
    {
        var held = new HashSet<string>(StringComparer.Ordinal);
        var recent = new Queue<long>();
        var reason = "disconnect";
        try
        {
            client.NoDelay = true;
            await using var stream = client.GetStream();
            using var authTimeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            authTimeout.CancelAfter(options.AuthTimeoutMs);
            var first = await ReadLineAsync(stream, authTimeout.Token);
            if (first == null || !RelayCodec.TryDecode(first, out var auth) || auth is not RelayAuth token ||
                !FixedEquals(token.Token, options.Token))
            {
                log.Info("relay auth failed");
                await WriteAsync(stream, "ERR auth\n", CancellationToken.None);
                reason = "auth";
                return;
            }

            log.Info("relay auth ok");
            await WriteAsync(stream, "OK\n", cancellationToken);
            while (!cancellationToken.IsCancellationRequested)
            {
                var line = await ReadLineAsync(stream, cancellationToken);
                if (line == null)
                {
                    break;
                }

                if (!RelayCodec.TryDecode(line, out var message) || message is RelayAuth)
                {
                    log.Info("relay rejected invalid event");
                    await WriteAsync(stream, "ERR invalid\n", CancellationToken.None);
                    reason = "invalid";
                    break;
                }

                if (message is RelayPing)
                {
                    await WriteAsync(stream, "PONG\n", cancellationToken);
                    continue;
                }

                if (message is RelayBye)
                {
                    reason = "bye";
                    break;
                }

                if (message is RelayButton or RelayTouch)
                {
                    if (!Allow(recent))
                    {
                        log.Info("relay rate limit");
                        await WriteAsync(stream, "ERR limit\n", CancellationToken.None);
                        reason = "limit";
                        break;
                    }
                }

                switch (message)
                {
                    case RelayButton button:
                        sink.OnButton(button.Control, button.Down, false);
                        if (button.Down)
                        {
                            held.Add(button.Control);
                        }
                        else
                        {
                            held.Remove(button.Control);
                        }

                        log.Info($"relay button {button.Control} {(button.Down ? "down" : "up")}");
                        break;
                    case RelayTouch touch:
                        sink.OnTouch(touch.Contacts);
                        log.Info($"relay touch contacts={touch.Contacts.Count}");
                        break;
                }
            }
        }
        catch (OperationCanceledException)
        {
            reason = "stopped";
        }
        catch (RelayProtocolException)
        {
            reason = "invalid";
            log.Info("relay rejected invalid event");
        }
        catch (IOException)
        {
            reason = "disconnect";
        }
        catch (Exception ex)
        {
            reason = "error";
            log.Info("relay session error " + ex.GetType().Name);
        }
        finally
        {
            foreach (var control in held)
            {
                sink.OnButton(control, false, true);
                log.Info($"relay release {control} reason={reason}");
            }

            sink.OnSessionEnd(reason);
            client.Dispose();
            Interlocked.Exchange(ref sessionActive, 0);
            log.Info($"relay session end reason={reason}");
        }
    }

    private bool Allow(Queue<long> recent)
    {
        var now = Environment.TickCount64;
        while (recent.Count > 0 && now - recent.Peek() >= 1000)
        {
            recent.Dequeue();
        }

        if (recent.Count >= options.MaxEventsPerSecond)
        {
            return false;
        }

        recent.Enqueue(now);
        return true;
    }

    private static bool FixedEquals(string presented, string expected)
    {
        var left = Encoding.UTF8.GetBytes(presented);
        var right = Encoding.UTF8.GetBytes(expected);
        return left.Length == right.Length && CryptographicOperations.FixedTimeEquals(left, right);
    }

    private static void Reject(TcpClient client, string line)
    {
        try
        {
            client.Client.Send(Encoding.UTF8.GetBytes(line + "\n"));
        }
        catch (IOException)
        {
        }
        finally
        {
            client.Dispose();
        }
    }

    private static async Task WriteAsync(NetworkStream stream, string text, CancellationToken cancellationToken)
    {
        var bytes = Encoding.UTF8.GetBytes(text);
        await stream.WriteAsync(bytes, cancellationToken);
    }

    private static async Task<string?> ReadLineAsync(NetworkStream stream, CancellationToken cancellationToken)
    {
        using var memory = new MemoryStream();
        var one = new byte[1];
        while (true)
        {
            var read = await stream.ReadAsync(one.AsMemory(0, 1), cancellationToken);
            if (read == 0)
            {
                return null;
            }

            if (one[0] == (byte)'\n')
            {
                break;
            }

            if (one[0] != (byte)'\r')
            {
                memory.WriteByte(one[0]);
            }

            if (memory.Length > RelayCodec.MaxLineLength)
            {
                throw new RelayProtocolException();
            }
        }

        return Encoding.UTF8.GetString(memory.ToArray());
    }

    private sealed class RelayProtocolException : Exception;
}
