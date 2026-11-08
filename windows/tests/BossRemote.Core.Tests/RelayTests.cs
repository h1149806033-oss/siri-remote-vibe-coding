using System.Net;
using Xunit;
using System.Net.Sockets;
using System.Text;
using BossRemote.Relay;

namespace BossRemote.Core.Tests;

public class RelayTests
{
    private const string Token = "abcdefghijklmnopqrstuvwxyz012345";

    [Fact]
    public void Codec_matches_the_macos_line_format_and_rejects_non_remote_input()
    {
        Assert.Equal("BTN back 1", RelayCodec.EncodeButton("back", true));
        Assert.Equal("TOUCH 1 0 0.5000 0.2500 0.2000", RelayCodec.EncodeTouch(
            [new RelayContact(0, 0.5, 0.25, 0.2)]));
        Assert.Equal("TOUCH 0", RelayCodec.EncodeTouch([]));
        Assert.True(RelayCodec.TryDecode("BTN play_pause 0", out var up));
        Assert.Equal(new RelayButton("play_pause", false), up);
        Assert.False(RelayCodec.TryDecode("BTN swipeUp 1", out _));
        Assert.False(RelayCodec.TryDecode("BTN back 2", out _));
        Assert.False(RelayCodec.TryDecode("TEXT hello", out _));
        Assert.False(RelayCodec.TryDecode("TOUCH 1 0 1.5000 0.0000 0.0000", out _));
    }

    [Fact]
    public void Token_file_must_be_private_and_is_not_echoed()
    {
        var directory = Path.Combine(Path.GetTempPath(), "boss-relay-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, "token");
        RelayToken.CreateFile(path);
        var loaded = RelayToken.Load(path);
        Assert.Equal(64, loaded.Length);
        Assert.DoesNotContain(loaded, path);

        if (!OperatingSystem.IsWindows())
        {
            File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.GroupRead);
            var error = Assert.Throws<RelayTokenException>(() => RelayToken.Load(path));
            Assert.DoesNotContain(loaded, error.Message);
        }
        Directory.Delete(directory, true);
    }

    [Fact]
    public async Task Loopback_forwards_real_protocol_events_and_a_bad_token_forwards_nothing()
    {
        var sink = new RecordingSink();
        var log = new RecordingLog();
        await using var session = await RelaySession.Start(sink, log, Token);
        var client = new RelayClient(session.Port, Token);
        await client.ConnectAsync();
        client.SendButton("back", true);
        client.SendTouch([new RelayContact(0, 0.5, 0.25, 0.2)]);
        client.SendButton("back", false);
        await client.StopAsync();
        await sink.WaitFor(events => events.Contains("end:bye"));

        Assert.Contains("back:down:live", sink.Events);
        Assert.Contains("touch:1", sink.Events);
        Assert.Contains("back:up:live", sink.Events);
        Assert.DoesNotContain(log.Lines, line => line.Contains(Token, StringComparison.Ordinal));

        var rejected = new RecordingSink();
        var rejectedLog = new RecordingLog();
        await using var other = await RelaySession.Start(rejected, rejectedLog, Token);
        var bad = new RelayClient(other.Port, "zzzzzzzzzzzzzzzzzzzz");
        await Assert.ThrowsAsync<RelayException>(() => bad.ConnectAsync());
        await rejected.WaitFor(events => events.Any(item => item.StartsWith("end:", StringComparison.Ordinal)));
        Assert.DoesNotContain(rejected.Events, item => item.Contains("down", StringComparison.Ordinal));
        Assert.DoesNotContain(rejectedLog.Lines, line => line.Contains("zzzzzzzzzzzzzzzzzzzz", StringComparison.Ordinal));
    }

    [Fact]
    public async Task Disconnect_releases_a_held_button_and_the_listener_stays_on_loopback()
    {
        var sink = new RecordingSink();
        var log = new RecordingLog();
        await using var session = await RelaySession.Start(sink, log, Token);
        Assert.Equal(IPAddress.Loopback, session.Server.BoundEndPoint!.Address);

        var client = new RelayClient(session.Port, Token);
        await client.ConnectAsync();
        client.SendButton("siri", true);
        await sink.WaitFor(events => events.Contains("siri:down:live"));
        client.Abandon();
        await sink.WaitFor(events => events.Contains("siri:up:synthetic"));
        Assert.Contains("end:disconnect", sink.Events);
    }

    [Fact]
    public async Task Rate_limit_and_invalid_events_close_the_session()
    {
        var sink = new RecordingSink();
        await using var session = await RelaySession.Start(sink, new RecordingLog(), Token, maxEventsPerSecond: 3);
        var client = new RelayClient(session.Port, Token);
        await client.ConnectAsync();
        client.SendButton("up", true);
        client.SendButton("down", true);
        client.SendButton("left", true);
        client.SendButton("right", true);
        await sink.WaitFor(events => events.Contains("end:limit"));
        Assert.Contains("up:up:synthetic", sink.Events);
        await client.DisposeAsync();

        var invalid = new RecordingSink();
        await using var second = await RelaySession.Start(invalid, new RecordingLog(), Token);
        using var raw = new TcpClient();
        await raw.ConnectAsync(IPAddress.Loopback, second.Port);
        var stream = raw.GetStream();
        await stream.WriteAsync(Encoding.UTF8.GetBytes($"AUTH {Token}\n"));
        var ok = await ReadLine(stream);
        Assert.Equal("OK", ok);
        await stream.WriteAsync(Encoding.UTF8.GetBytes("BTN back 1\nBTN keyboard 1\n"));
        await invalid.WaitFor(events => events.Contains("end:invalid"));
        Assert.Contains("back:down:live", invalid.Events);
        Assert.Contains("back:up:synthetic", invalid.Events);
        Assert.DoesNotContain(invalid.Events, item => item.StartsWith("keyboard", StringComparison.Ordinal));
    }

    private static async Task<string?> ReadLine(NetworkStream stream)
    {
        using var memory = new MemoryStream();
        var one = new byte[1];
        while (memory.Length < 128)
        {
            if (await stream.ReadAsync(one.AsMemory(0, 1)) == 0)
            {
                return null;
            }

            if (one[0] == (byte)'\n')
            {
                return Encoding.UTF8.GetString(memory.ToArray());
            }

            memory.WriteByte(one[0]);
        }

        return null;
    }

    private sealed class RelaySession : IAsyncDisposable
    {
        public required RelayServer Server { get; init; }
        public required CancellationTokenSource Cancellation { get; init; }
        public int Port => Server.BoundEndPoint!.Port;

        public static async Task<RelaySession> Start(
            RecordingSink sink,
            RecordingLog log,
            string token,
            int maxEventsPerSecond = 300)
        {
            var server = new RelayServer(
                new RelayServerOptions(0, token, maxEventsPerSecond, 500),
                sink,
                log);
            var cancellation = new CancellationTokenSource();
            _ = server.RunAsync(cancellation.Token);
            var started = Environment.TickCount64;
            while (server.BoundEndPoint == null)
            {
                if (Environment.TickCount64 - started > 3000)
                {
                    throw new TimeoutException("relay server did not bind");
                }

                await Task.Delay(10);
            }

            return new RelaySession { Server = server, Cancellation = cancellation };
        }

        public async ValueTask DisposeAsync()
        {
            await Cancellation.CancelAsync();
            Cancellation.Dispose();
        }
    }

    private sealed class RecordingSink : IRelaySink
    {
        private readonly List<string> events = [];
        public IReadOnlyList<string> Events
        {
            get
            {
                lock (events)
                {
                    return events.ToArray();
                }
            }
        }

        public void OnButton(string control, bool down, bool syntheticRelease)
        {
            lock (events)
            {
                events.Add($"{control}:{(down ? "down" : "up")}:{(syntheticRelease ? "synthetic" : "live")}");
            }
        }

        public void OnTouch(IReadOnlyList<RelayContact> contacts)
        {
            lock (events)
            {
                events.Add($"touch:{contacts.Count}");
            }
        }

        public void OnSessionEnd(string reason)
        {
            lock (events)
            {
                events.Add("end:" + reason);
            }
        }

        public async Task WaitFor(Func<IReadOnlyList<string>, bool> predicate)
        {
            var started = Environment.TickCount64;
            while (!predicate(Events))
            {
                if (Environment.TickCount64 - started > 3000)
                {
                    throw new TimeoutException(string.Join(", ", Events));
                }

                await Task.Delay(20);
            }
        }
    }

    private sealed class RecordingLog : IRelayLog
    {
        private readonly List<string> lines = [];
        public IReadOnlyList<string> Lines
        {
            get
            {
                lock (lines)
                {
                    return lines.ToArray();
                }
            }
        }

        public void Info(string message)
        {
            lock (lines)
            {
                lines.Add(message);
            }
        }
    }
}
