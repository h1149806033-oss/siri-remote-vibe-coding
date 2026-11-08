using System.Net;
using System.Net.Sockets;
using System.Text;

namespace BossRemote.Relay;

public sealed class RelayException : Exception
{
    public RelayException(string message) : base(message)
    {
    }
}

/// <summary>
/// 只连接 127.0.0.1。调用方不能改目的地址。
/// </summary>
public sealed class RelayClient : IAsyncDisposable
{
    private readonly int port;
    private readonly string token;
    private readonly object gate = new();
    private readonly Queue<string> outbound = new();
    private readonly HashSet<string> held = new(StringComparer.Ordinal);
    private TcpClient? client;
    private NetworkStream? stream;
    private Task? writer;
    private bool ready;
    private bool stopping;

    public RelayClient(int port, string token)
    {
        if (port is < 1 or > 65535)
        {
            throw new ArgumentOutOfRangeException(nameof(port));
        }

        if (!RelayToken.IsWellFormed(token))
        {
            throw new RelayTokenException("token file must contain 16 to 128 letters or digits");
        }

        this.port = port;
        this.token = token;
    }

    public async Task ConnectAsync(CancellationToken cancellationToken = default)
    {
        client = new TcpClient { NoDelay = true };
        await client.ConnectAsync(IPAddress.Loopback, port, cancellationToken);
        stream = client.GetStream();
        var auth = Encoding.UTF8.GetBytes(RelayCodec.EncodeAuth(token) + "\n");
        await stream.WriteAsync(auth, cancellationToken);
        var reply = await ReadLineAsync(stream, cancellationToken);
        if (reply != "OK")
        {
            throw new RelayException("auth rejected");
        }

        writer = Task.Run(WriteLoop);
        ready = true;
    }

    public void SendButton(string control, bool down)
    {
        if (!RelayCodec.IsPhysical(control))
        {
            return;
        }

        lock (gate)
        {
            if (down)
            {
                held.Add(control);
            }
            else
            {
                held.Remove(control);
            }
        }

        Enqueue(RelayCodec.EncodeButton(control, down));
    }

    public void SendTouch(IReadOnlyList<RelayContact> contacts)
    {
        if (contacts.Count > RelayCodec.MaxContacts)
        {
            contacts = contacts.Take(RelayCodec.MaxContacts).ToArray();
        }

        Enqueue(RelayCodec.EncodeTouch(contacts));
    }

    public void Abandon()
    {
        ready = false;
        client?.Close();
    }

    public async Task StopAsync()
    {
        string[] release;
        lock (gate)
        {
            release = held.ToArray();
            held.Clear();
        }

        foreach (var control in release)
        {
            Enqueue(RelayCodec.EncodeButton(control, false));
        }

        Enqueue(RelayCodec.EncodeBye());
        lock (gate)
        {
            ready = false;
            stopping = true;
            Monitor.PulseAll(gate);
        }

        if (writer != null)
        {
            await writer;
        }

        client?.Close();
    }

    public async ValueTask DisposeAsync() => await StopAsync();

    private void Enqueue(string line)
    {
        lock (gate)
        {
            if (!ready && writer == null)
            {
                return;
            }

            while (outbound.Count >= 64 && outbound.TryPeek(out var oldest) && oldest.StartsWith("TOUCH ", StringComparison.Ordinal))
            {
                outbound.Dequeue();
            }

            if (outbound.Count < 128)
            {
                outbound.Enqueue(line);
            }

            Monitor.Pulse(gate);
        }
    }

    private async Task WriteLoop()
    {
        try
        {
            while (true)
            {
                string? line = null;
                lock (gate)
                {
                    while (outbound.Count == 0 && !stopping)
                    {
                        Monitor.Wait(gate, 50);
                    }

                    if (outbound.Count == 0)
                    {
                        break;
                    }

                    line = outbound.Dequeue();
                }

                if (stream == null)
                {
                    break;
                }

                var bytes = Encoding.UTF8.GetBytes(line + "\n");
                await stream.WriteAsync(bytes);
                await stream.FlushAsync();
            }
        }
        catch (IOException)
        {
        }
    }

    private static async Task<string?> ReadLineAsync(NetworkStream stream, CancellationToken cancellationToken)
    {
        using var memory = new MemoryStream();
        var one = new byte[1];
        while (memory.Length <= RelayCodec.MaxLineLength)
        {
            var read = await stream.ReadAsync(one.AsMemory(0, 1), cancellationToken);
            if (read == 0)
            {
                return null;
            }

            if (one[0] == (byte)'\n')
            {
                return Encoding.UTF8.GetString(memory.ToArray()).TrimEnd('\r');
            }

            memory.WriteByte(one[0]);
        }

        return null;
    }
}
