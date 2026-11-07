# Boss Remote

把 Apple Siri Remote（第 3 代，A2854）变成 Mac 的触控板、快捷键键盘和语音输入设备。

一个原生 SwiftUI App，不依赖第三方映射工具：触控板读取、按键映射、语音桥接、映射界面全部自己实现。

## 下载

从 [Releases](https://github.com/h1149806033-oss/siri-remote-vibe-coding/releases) 下载 `Boss-Remote-<版本>-arm64.dmg`，打开后把 `Boss Remote.app` 拖进「应用程序」。

这个包用 Apple Development 证书签名、**没有经过 Apple 公证**，首次打开会被系统拦下，任选一种方式放行：

- 右键点 App →「打开」→ 再确认一次
- 或执行 `xattr -dr com.apple.quarantine "/Applications/Boss Remote.app"`

只提供 Apple Silicon 版本，需要 macOS 14 或更高。

## 功能

**触控**

- 滑动触控板移动指针，轻点发送鼠标点击
- 外环环形滚动：手指沿圆盘外圈转圈即滚动，带 0.35 弧度起始阈值、反向抖动抑制和平滑
- 按下时锁定指针（可关），按住点击时光标不会漂移
- 遥控器图形上有一颗跟手的实时光点；手指落到外环时，圆盘边缘会透出一圈暖光

**映射**

- 22 个可映射目标：13 个实体按键（电源、返回、TV、播放/暂停、音量 ±、静音、Siri、四向 + 确定）+ 9 个手势（上下左右滑、外环四向滑、双击）
- 每个实体按键还可以单独配一个**长按 0.5 秒**动作，不配就和原来一样按下即触发
- 动作库 53 项：按键、系统快捷键、系统功能（调度中心、聚焦搜索、截图等）、媒体与音量
- 按 App 自动切换：每个 App 一套专属映射，未覆盖的按键回落到全局

**语音**

- 按住 Siri 键说话，遥控器麦克风经本地桥接进系统输入设备
- 可选把 Siri 键按住时映射为右 Command，配合语音输入法使用
- 用时可查看录音状态与语音组件健康度

**其它**

- 遥控器电量（HID + BLE 双通道）、充电曲线、连接诊断
- 使用记录与近 7 天语音时长统计
- 日间 / 夜间主题，跟随系统或手动切换
- 中英双语界面

## 系统要求

- macOS 14 或更高
- Xcode 16 / Swift 6 工具链（构建用）
- Apple Siri Remote 第 3 代（A2854），已与 Mac 配对

## 构建

```bash
cd app
./scripts/build-app.sh
open "dist/Boss Remote Dev.app"
```

脚本会用本机的 `Apple Development` 证书签名；没有证书时可以指定：

```bash
BOSS_REMOTE_SIGN_IDENTITY="Apple Development: 你的名字 (TEAMID)" ./scripts/build-app.sh
```

HCI 抓包辅助工具（用于遥控器麦克风的音频通道）需要单独安装，要输密码：

```bash
sudo ./scripts/install-hci.sh
```

## 首次运行

1. 打开 App，按提示授予**辅助功能**（移动指针、发送按键）和**输入监控**（读取遥控器按键与触控板）
2. 遥控器与 Mac 配对后，按键映射页右上角会显示「已连接」
3. 在「按键」页选中任一控件，右侧可设置它发送什么按键；选中某个 App 时设置的是该 App 的专属映射

## 目录结构

```
app/
├── Package.swift
├── Sources/
│   ├── BossRemoteApp/        应用入口、状态、各页面
│   ├── BossRemoteCore/       设置、映射、记录、语音统计等模型
│   ├── BossRemoteHID/        HID 按键、私有 MultitouchSupport 触控、指针注入
│   ├── BossRemoteUI/         主题、侧栏、遥控器画布、映射界面
│   ├── BossRemoteVoice/      遥控器麦克风采集与虚拟输入设备
│   ├── BossRemoteHCIProtocol/主机与辅助进程之间的协议
│   └── BossRemoteHCIService/ 特权辅助工具：HCI 抓包
├── Resources/                图标、Info.plist、libopus
└── scripts/                  构建、安装/卸载辅助工具
```

## 已知限制

- 使用私有框架 `MultitouchSupport` 读取触控板，无法上架 Mac App Store
- 构建产物未公证；分发给别人时需要对方在「隐私与安全性」里放行，或自行签名
- 触控坐标按第 3 代遥控器实测标定，换用其他型号可能需要重测

## 给 AI 代理的排查指南

如果你是被叫来「帮我把这个装上」或「帮我修一下」的代理，按症状对号入座。每条都是**症状 → 怎么判断 → 怎么处理**，命令可以直接复制执行。

先确认装的是哪个版本：

```bash
defaults read "/Applications/Boss Remote.app/Contents/Info.plist" CFBundleShortVersionString
defaults read "/Applications/Boss Remote.app/Contents/Info.plist" CFBundleIdentifier
# 发布版是 com.bossremote.app，本地开发版是 com.bossremote.dev
```

### 1. 打不开：提示「已损坏，无法打开」或「无法验证开发者」

原因只有一个：包用 Development 证书签名，没有 Apple 公证，被 Gatekeeper 拦了。文件本身没坏。

```bash
xattr -dr com.apple.quarantine "/Applications/Boss Remote.app"
open "/Applications/Boss Remote.app"
```

想让用户自己操作：右键点 App →「打开」→ 在弹窗里再点一次「打开」。

确认文件确实完整：

```bash
codesign -dv --verbose=2 "/Applications/Boss Remote.app" 2>&1 | head -6
codesign --verify --deep --strict "/Applications/Boss Remote.app" && echo OK
```

### 2. 装好了，但遥控器按键没反应

按顺序排查，前一条不成立再看下一条：

**a) 权限没给。** App 内「连接」页顶部会显示「还需要系统权限」。让用户在这里手动打开两个开关：

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
```

「辅助功能」用于移动指针和发送按键，「输入监控」用于读取遥控器。两个都要给。

**b) 遥控器没和 Mac 配对。** 配对前必须先让遥控器断开 Apple TV：拔掉 Apple TV 电源，长按遥控器「返回 + 音量+」约 5 秒，然后到「系统设置 → 蓝牙」里连接新出现的设备。

**c) 遥控器同时连着 Apple TV。** 同一时间只能连一台主机，先断开另一台。

判断当前有没有连上：App 内「连接」页会显示已连接/等待连接，日志里也会写。

### 3. 指针会动，但点不了，或者光标乱飘

- 先看「设置 → 输入」里「轻点点击」是否开着
- 「按下锁定指针」依赖遥控器上报压力数据；如果设备不报，这个功能自然不生效，**不是故障**
- 触控坐标是按第 3 代遥控器（A2854）实测标定的。换成别的型号，光点位置会偏——这是已知限制，不是 bug
- 想确认触控有没有在上报：

```bash
tail -20 ~/Library/Logs/BossRemoteDev/runtime.log | grep "touch"
```

### 4. 语音没反应 / 语音组件不就绪

**a) HCI 辅助工具没装。** 遥控器的麦克风音频要靠一个特权辅助工具桥接，装它需要 sudo（要输密码，代理不要替用户输入）：

```bash
cd <源码目录>/app && sudo ./scripts/install-hci.sh
ls -l /Library/PrivilegedHelperTools/com.bossremote.hci   # 确认装上了
```

**b) 麦克风权限没给：**

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
```

**c) 看状态。** App 内「连接」页的语音/麦克风区块会显示当前状态，日志里搜 `voice` 和 `virtual microphone`。

### 5. Intel Mac 上打不开

只提供 arm64 版本，Rosetta 不能运行 arm64 二进制。要么用 Apple Silicon，要么从源码构建（需要 Xcode 16 以上）：

```bash
git clone https://github.com/h1149806033-oss/siri-remote-vibe-coding.git
cd siri-remote-vibe-coding/app && ./scripts/build-app.sh
```

### 6. 遇到任何说不清的问题

日志在这里，先看它再猜：

```bash
tail -60 ~/Library/Logs/BossRemoteDev/runtime.log
```

日志记录连接状态、权限、每次按键、触控接触点数、每次触摸落下的原始坐标与压力值、语音状态、电池。开发版和发布版共用这个目录。

### 7. 想彻底重来

```bash
defaults delete com.bossremote.app        # 发布版；开发版换成 com.bossremote.dev
rm -rf ~/Library/Logs/BossRemoteDev
cd <源码目录>/app && sudo ./scripts/uninstall-hci.sh
```

`defaults delete` 会连同所有按键映射和 App 专属配置一起清空，执行前提醒用户。

## 致谢

灵感来自 [HyperVibe（SiriRemoteForge）](https://github.com/HOLODATA-COM/SiriRemoteForge)——它先证明了 Siri Remote 可以完整接管 Mac 的指针、按键和麦克风。本项目是独立的原生实现，没有使用它的代码。
