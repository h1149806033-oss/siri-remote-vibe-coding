# 遥控器事件转发

本地 Mac 用蓝牙连上 Siri Remote，只把**已经收到的按键和触控**送到云端 Linux。云端默认只打印这些事件，不控制桌面，不转发麦克风，不执行命令。

这次的本机是 MacBook Pro。macOS 发送端是主路径，Windows 发送端同样只连 `127.0.0.1`。两边都不会把程序监听口开到公网，也不会替你建立隧道。

回环测试不能证明遥控器或 Windows 蓝牙已经工作。没有实机时，只能证明：协议、认证、断线松键和 Linux 接收进程是通的。

## 线路

```text
Siri Remote --蓝牙--> Mac 上的老板遥控
                         |
                         | 只连 127.0.0.1:4777
                         v
                    你自己执行的 SSH 隧道
                         |
                         v
              Linux 云电脑 127.0.0.1:4777 接收端
```

接收端只绑定 `127.0.0.1`。别人不能从公网直接连到它。要跨过互联网，在 **Mac** 上自己执行：

```bash
ssh -N -L 4777:127.0.0.1:4777 <云端用户>@<云端主机>
```

这条命令把 Mac 的 `127.0.0.1:4777` 转到云端本机的 `127.0.0.1:4777`。程序不会运行 `ssh`，也不会打开 ngrok、cloudflared 或其他公网隧道。

## 云端：启动接收端

需要 .NET 8 SDK，或者使用下面的自包含二进制。不需要桌面，不需要 root。

在仓库里生成 token。命令只打印“已创建”，**不会打印 token**：

```bash
dotnet run --project windows/src/BossRemote.Relay.Server -c Release -- \
  --init-token "$HOME/.config/boss-remote/relay.token"
chmod 600 "$HOME/.config/boss-remote/relay.token"
```

把同一个文件用 `scp` 拷到 Mac，并同样设成 `600`。不要把 token 放进 shell 历史、聊天记录或配置仓库。

启动接收端：

```bash
dotnet run --project windows/src/BossRemote.Relay.Server -c Release -- \
  --token-file "$HOME/.config/boss-remote/relay.token" \
  --port 4777
```

自包含包的构建位置：

```bash
dotnet publish windows/src/BossRemote.Relay.Server -c Release -r linux-x64 \
  --self-contained true -p:PublishSingleFile=true \
  -p:IncludeNativeLibrariesForSelfExtract=true \
  -o windows/artifacts/relay-linux-x64
```

产物是 `windows/artifacts/relay-linux-x64/BossRemote.Relay.Server`。这个目录被 git 忽略。GitHub Actions 的 `windows` 工作流会另外上传名为 `BossRemote-Relay-linux-x64` 的 artifact。

`--inject` 会直接拒绝启动。这一版没有经过验证的桌面注入，避免误控云电脑。接收端只把事件写到标准输出，例如 `button back down`、`touch 1`、`release siri reason=disconnect`。

token 文件如果同组或其他用户可读，接收端会退出，并且不显示文件内容。

## Mac：发送端

先让 SSH 隧道保持运行，再打开 App。转发默认关闭。

```bash
export BOSS_REMOTE_RELAY=1
export BOSS_REMOTE_RELAY_TOKEN_FILE="$HOME/.config/boss-remote/relay.token"
export BOSS_REMOTE_RELAY_PORT=4777   # 可省略
open "/Applications/Boss Remote.app"
```

也可以在 App 的设置里打开「转发到本机回环」。无论用哪一种，token 都只从环境变量指向的文件读取，不会写进 `UserDefaults`。

发送的只有实体键和触控板接触点。本地指针、点击、语音都不走这条链路。隧道还没通时按下的那一下不会事后补发。断开时，接收端会松开还按着的键。

从源码构建 Mac App 的方法仍是 `app/README.md` 里的 `./scripts/build-app.sh`。这次的 Linux 环境没有编译 Swift，所以 Mac 发送端还没有在这台云电脑上编译或连上真遥控器。

## Windows：可选发送端

Windows 版同样只连 `127.0.0.1`。在设置里勾选转发之前，用同一个 token 文件设置：

```text
BOSS_REMOTE_RELAY_TOKEN_FILE
BOSS_REMOTE_RELAY_PORT
```

这不能证明 Windows 蓝牙硬件已经可用。勾选之后，只有 HID/GATT 读到的按键和触控才会发出去。

## 协议

一行一条 UTF-8 消息，以换行结束。第一条必须是 `AUTH <token>`。token 只含 16 到 128 位字母或数字。

之后只接受：

- `BTN <实体键> <0|1>`，实体键是 `power`、`up`、`down`、`left`、`right`、`select`、`back`、`tv`、`play_pause`、`volume_up`、`volume_down`、`mute`、`siri`
- `TOUCH <个数> <id> <x> <y> <size> ...`，最多 2 个接触点，`x`/`y` 在 0 到 1
- `PING` / `BYE`

手势名、键盘文本、音频和任意路径都会被拒绝，连接随后关闭。每秒最多 300 条按键或触控。超过后连接关闭，并松开还按着的键。

## 已测和未测

已在这台 Linux 上自动测试：

- 行格式与非法输入
- token 文件权限
- 本机回环上的认证、按键、触控、正常结束
- 错误 token 不会送进接收端，日志里也不出现 token
- 连接突然断开时松开按住的键
- 超速和非法按键会结束会话
- 监听地址是 `127.0.0.1`

未测：

- 真的 Siri Remote
- Mac App 的实际编译和点击
- Windows 程序的实际点击
- 通过真实 SSH 到达另一台机器
- 云桌面注入（故意拒绝 `--inject`）
