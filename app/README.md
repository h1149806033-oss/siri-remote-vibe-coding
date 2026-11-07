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

## 致谢

灵感来自 [HyperVibe（SiriRemoteForge）](https://github.com/HOLODATA-COM/SiriRemoteForge)——它先证明了 Siri Remote 可以完整接管 Mac 的指针、按键和麦克风。本项目是独立的原生实现，没有使用它的代码。
