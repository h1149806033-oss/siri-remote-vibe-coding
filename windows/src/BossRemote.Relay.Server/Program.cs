using BossRemote.Relay;

var port = 4777;
string? tokenFile = null;
var initToken = false;
for (var i = 0; i < args.Length; i++)
{
    switch (args[i])
    {
        case "--port" when i + 1 < args.Length && int.TryParse(args[++i], out var parsed):
            port = parsed;
            break;
        case "--token-file" when i + 1 < args.Length:
            tokenFile = args[++i];
            break;
        case "--init-token" when i + 1 < args.Length:
            initToken = true;
            tokenFile = args[++i];
            break;
        case "--inject":
            Console.Error.WriteLine("拒绝启动：--inject 会把事件写进云桌面。这一版没有经过验证的注入实现，因此不会进入注入模式。");
            return 2;
        case "--help":
        case "-h":
            PrintUsage();
            return 0;
        default:
            Console.Error.WriteLine("无法识别的参数。用 --help 查看用法。");
            return 2;
    }
}

if (initToken)
{
    if (string.IsNullOrWhiteSpace(tokenFile))
    {
        Console.Error.WriteLine("需要 token 文件路径。");
        return 2;
    }

    RelayToken.CreateFile(tokenFile);
    Console.WriteLine("已创建 token 文件。内容不会打印。");
    return 0;
}

if (string.IsNullOrWhiteSpace(tokenFile))
{
    Console.Error.WriteLine("需要 --token-file。用 --init-token 生成，不要把 token 写进命令行。");
    return 2;
}

string token;
try
{
    token = RelayToken.Load(tokenFile);
}
catch (RelayTokenException ex)
{
    Console.Error.WriteLine("token 文件不可用：" + ex.Message);
    return 2;
}

using var stop = new CancellationTokenSource();
Console.CancelKeyPress += (_, eventArgs) =>
{
    eventArgs.Cancel = true;
    stop.Cancel();
};

var server = new RelayServer(
    new RelayServerOptions(port, token),
    new DiagnosticSink(),
    new ConsoleLog());
Console.WriteLine("接收端只监听 127.0.0.1。它不打开公网端口，也不建立隧道。");
try
{
    await server.RunAsync(stop.Token);
}
catch (OperationCanceledException)
{
}

return 0;

static void PrintUsage()
{
    Console.WriteLine("""
        老板遥控 Linux 接收端

          --init-token <path>   创建仅本人可读的 token 文件，不打印内容
          --token-file <path>   读取 token。文件必须是 600 权限
          --port <port>         回环端口，默认 4777
          --inject              拒绝启动。桌面注入未实现

        跨网时由你自己执行 SSH 本地转发，例如：
          ssh -N -L 4777:127.0.0.1:4777 user@cloud
        """);
}

file sealed class DiagnosticSink : IRelaySink
{
    public void OnButton(string control, bool down, bool syntheticRelease)
    {
        Console.WriteLine(syntheticRelease
            ? $"release {control} synthetic"
            : $"button {control} {(down ? "down" : "up")}");
    }

    public void OnTouch(IReadOnlyList<RelayContact> contacts) =>
        Console.WriteLine($"touch {contacts.Count}");

    public void OnSessionEnd(string reason) =>
        Console.WriteLine($"session {reason}");
}

file sealed class ConsoleLog : IRelayLog
{
    public void Info(string message) => Console.WriteLine(message);
}
