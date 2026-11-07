import CoreGraphics
import Foundation

public struct ButtonAction: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case none
        case key
    }

    public var kind: Kind
    public var key: KeyBinding?

    public init(kind: Kind, key: KeyBinding? = nil) {
        self.kind = kind
        self.key = key
    }

    public static let none = ButtonAction(kind: .none)

    public static func key(_ key: KeyBinding) -> ButtonAction {
        ButtonAction(kind: .key, key: key)
    }

    public var label: String {
        switch kind {
        case .none: return L10n.t("不执行操作", "No action")
        case .key: return key?.title ?? L10n.t("按键", "Key")
        }
    }
}

public enum KeyBinding: String, Codable, CaseIterable, Identifiable, Sendable {
    public enum Group: String, CaseIterable, Identifiable, Sendable {
        case keys
        case shortcuts
        case system
        case media

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .keys: return L10n.t("按键", "Keys")
            case .shortcuts: return L10n.t("快捷键", "Shortcuts")
            case .system: return L10n.t("系统", "System")
            case .media: return L10n.t("媒体与音量", "Media & Volume")
            }
        }
    }

    case returnKey
    case escape
    case space
    case tab
    case delete
    case forwardDelete
    case upArrow
    case downArrow
    case leftArrow
    case rightArrow
    case pageUp
    case pageDown
    case home
    case end

    case undo
    case redo
    case cut
    case copy
    case paste
    case selectAll
    case find
    case save
    case newItem
    case openItem
    case closeWindow
    case quitApp
    case hideApp
    case minimize
    case fullScreen
    case reload
    case goBack
    case goForward
    case newTab
    case reopenTab
    case nextTab
    case previousTab
    case addressBar

    case appSwitcher
    case lockScreen
    case spotlight
    case missionControl
    case appExpose
    case showDesktop
    case launchpad
    case screenshot

    case mediaPlayPause
    case mediaNext
    case mediaPrevious
    case volumeUp
    case volumeDown
    case mute
    case brightnessUp
    case brightnessDown

    public var id: String { rawValue }

    public var group: Group {
        switch self {
        case .returnKey, .escape, .space, .tab, .delete, .forwardDelete,
             .upArrow, .downArrow, .leftArrow, .rightArrow,
             .pageUp, .pageDown, .home, .end:
            return .keys
        case .undo, .redo, .cut, .copy, .paste, .selectAll, .find, .save,
             .newItem, .openItem, .closeWindow, .quitApp, .hideApp,
             .minimize, .fullScreen, .reload, .goBack, .goForward,
             .newTab, .reopenTab, .nextTab, .previousTab, .addressBar:
            return .shortcuts
        case .appSwitcher, .lockScreen, .spotlight, .missionControl,
             .appExpose, .showDesktop, .launchpad, .screenshot:
            return .system
        case .mediaPlayPause, .mediaNext, .mediaPrevious, .volumeUp,
             .volumeDown, .mute, .brightnessUp, .brightnessDown:
            return .media
        }
    }

    public var title: String {
        switch self {
        case .returnKey: return L10n.t("Return", "Return")
        case .escape: return L10n.t("Esc", "Esc")
        case .space: return L10n.t("空格", "Space")
        case .tab: return L10n.t("Tab", "Tab")
        case .delete: return L10n.t("删除", "Delete")
        case .forwardDelete: return L10n.t("前向删除", "Forward Delete")
        case .upArrow: return L10n.t("↑", "Up arrow")
        case .downArrow: return L10n.t("↓", "Down arrow")
        case .leftArrow: return L10n.t("←", "Left arrow")
        case .rightArrow: return L10n.t("→", "Right arrow")
        case .pageUp: return L10n.t("Page Up", "Page Up")
        case .pageDown: return L10n.t("Page Down", "Page Down")
        case .home: return L10n.t("Home", "Home")
        case .end: return L10n.t("End", "End")
        case .undo: return L10n.t("撤销", "Undo")
        case .redo: return L10n.t("重做", "Redo")
        case .cut: return L10n.t("剪切", "Cut")
        case .copy: return L10n.t("复制", "Copy")
        case .paste: return L10n.t("粘贴", "Paste")
        case .selectAll: return L10n.t("全选", "Select All")
        case .find: return L10n.t("查找", "Find")
        case .save: return L10n.t("保存", "Save")
        case .newItem: return L10n.t("新建", "New")
        case .openItem: return L10n.t("打开", "Open")
        case .closeWindow: return L10n.t(
            "关闭窗口或标签页",
            "Close Window or Tab"
        )
        case .quitApp: return L10n.t("退出 App", "Quit App")
        case .hideApp: return L10n.t("隐藏 App", "Hide App")
        case .minimize: return L10n.t("最小化", "Minimize")
        case .fullScreen: return L10n.t("全屏", "Full Screen")
        case .reload: return L10n.t("刷新", "Reload")
        case .goBack: return L10n.t("后退", "Go Back")
        case .goForward: return L10n.t("前进", "Go Forward")
        case .newTab: return L10n.t("新建标签页", "New Tab")
        case .reopenTab: return L10n.t("恢复标签页", "Reopen Tab")
        case .nextTab: return L10n.t("下一个标签页", "Next Tab")
        case .previousTab: return L10n.t("上一个标签页", "Previous Tab")
        case .addressBar: return L10n.t("地址栏", "Address Bar")
        case .appSwitcher: return L10n.t(
            "切换 App（⌘Tab）",
            "App switcher (⌘Tab)"
        )
        case .lockScreen: return L10n.t(
            "锁定屏幕（⌃⌘Q）",
            "Lock screen (⌃⌘Q)"
        )
        case .spotlight: return L10n.t(
            "聚焦搜索（⌘Space）",
            "Spotlight (⌘Space)"
        )
        case .missionControl: return L10n.t("调度中心", "Mission Control")
        case .appExpose: return L10n.t("窗口预览", "App Exposé")
        case .showDesktop: return L10n.t("显示桌面", "Show Desktop")
        case .launchpad: return L10n.t("启动台", "Launchpad")
        case .screenshot: return L10n.t("区域截图", "Screenshot")
        case .mediaPlayPause: return L10n.t(
            "媒体播放 / 暂停",
            "Media play / pause"
        )
        case .mediaNext: return L10n.t("下一首", "Next Track")
        case .mediaPrevious: return L10n.t("上一首", "Previous Track")
        case .volumeUp: return L10n.t("系统音量 +", "System volume up")
        case .volumeDown: return L10n.t("系统音量 −", "System volume down")
        case .mute: return L10n.t("系统静音", "System mute")
        case .brightnessUp: return L10n.t("亮度 +", "Brightness Up")
        case .brightnessDown: return L10n.t("亮度 −", "Brightness Down")
        }
    }

    public var keyCode: CGKeyCode {
        switch self {
        case .returnKey: return 36
        case .escape: return 53
        case .space: return 49
        case .tab, .appSwitcher: return 48
        case .delete: return 51
        case .forwardDelete: return 117
        case .upArrow: return 126
        case .downArrow: return 125
        case .leftArrow: return 123
        case .rightArrow: return 124
        case .pageUp: return 116
        case .pageDown: return 121
        case .home: return 115
        case .end: return 119
        case .undo, .redo: return 6
        case .cut: return 7
        case .copy: return 8
        case .paste: return 9
        case .selectAll: return 0
        case .find, .fullScreen: return 3
        case .save: return 1
        case .newItem: return 45
        case .openItem: return 31
        case .closeWindow: return 13
        case .quitApp: return 12
        case .hideApp: return 4
        case .minimize: return 46
        case .reload: return 15
        case .goBack: return 33
        case .goForward: return 30
        case .newTab, .reopenTab: return 17
        case .nextTab, .previousTab: return 48
        case .addressBar: return 37
        case .lockScreen: return 12
        case .spotlight: return 49
        case .missionControl: return 126
        case .appExpose: return 125
        case .showDesktop: return 103
        case .launchpad: return 118
        case .screenshot: return 21
        case .volumeUp: return 72
        case .volumeDown: return 73
        case .mute: return 74
        case .mediaPlayPause, .mediaNext, .mediaPrevious,
             .brightnessUp, .brightnessDown:
            return 0
        }
    }

    public var flags: CGEventFlags {
        switch self {
        case .undo, .cut, .copy, .paste, .selectAll, .find, .save,
             .newItem, .openItem, .closeWindow, .quitApp, .hideApp,
             .minimize, .reload, .goBack, .goForward, .newTab,
             .addressBar, .spotlight:
            return [.maskCommand]
        case .redo, .reopenTab, .screenshot:
            return [.maskCommand, .maskShift]
        case .fullScreen:
            return [.maskCommand, .maskControl]
        case .appSwitcher:
            return [.maskCommand]
        case .lockScreen:
            return [.maskCommand, .maskControl]
        case .nextTab:
            return [.maskControl]
        case .previousTab:
            return [.maskControl, .maskShift]
        case .missionControl, .appExpose:
            return [.maskControl]
        default:
            return []
        }
    }
}
