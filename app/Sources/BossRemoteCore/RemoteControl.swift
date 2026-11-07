import Foundation

/// The eight physical controls on the Siri Remote (3rd generation), plus the
/// four directions and centre of its clickpad.
public enum RemoteControl: String, CaseIterable, Codable, Identifiable, Sendable {
    case power
    case up
    case down
    case left
    case right
    case select
    case back
    case tv
    case playPause = "play_pause"
    case volumeUp = "volume_up"
    case volumeDown = "volume_down"
    case mute
    case siri

    // Gesture targets: not physical buttons, but placeable on the clickpad.
    case ringUp
    case ringDown
    case ringLeft
    case ringRight
    case swipeUp
    case swipeDown
    case swipeLeft
    case swipeRight
    case tapTwo

    public var id: String { rawValue }

    public static let buttonControls: [RemoteControl] = [
        .power, .back, .tv, .playPause,
        .volumeUp, .volumeDown, .mute, .siri,
    ]

    public static let directionalControls: [RemoteControl] = [
        .up, .down, .left, .right, .select,
    ]

    public static let ringControls: [RemoteControl] = [
        .ringUp, .ringDown, .ringLeft, .ringRight,
    ]

    public static let swipeControls: [RemoteControl] = [
        .swipeUp, .swipeDown, .swipeLeft, .swipeRight,
    ]

    public static let tapControls: [RemoteControl] = [.tapTwo]

    public var isGesture: Bool {
        switch self {
        case .ringUp, .ringDown, .ringLeft, .ringRight,
             .swipeUp, .swipeDown, .swipeLeft, .swipeRight, .tapTwo:
            return true
        default:
            return false
        }
    }

    /// Which physical control the canvas should light up for this target.
    public var canvasControl: RemoteControl {
        switch self {
        case .ringUp, .swipeUp: return .up
        case .ringDown, .swipeDown: return .down
        case .ringLeft, .swipeLeft: return .left
        case .ringRight, .swipeRight: return .right
        case .tapTwo: return .select
        default: return self
        }
    }

    public var title: String {
        switch self {
        case .power: return L10n.t("电源", "Power")
        case .up: return L10n.t("上", "Up")
        case .down: return L10n.t("下", "Down")
        case .left: return L10n.t("左", "Left")
        case .right: return L10n.t("右", "Right")
        case .select: return L10n.t("确定键", "Select")
        case .back: return L10n.t("返回", "Back")
        case .tv: return L10n.t("TV", "TV")
        case .playPause: return L10n.t("播放 / 暂停", "Play / Pause")
        case .volumeUp: return L10n.t("音量 +", "Volume Up")
        case .volumeDown: return L10n.t("音量 −", "Volume Down")
        case .mute: return L10n.t("静音", "Mute")
        case .siri: return L10n.t("Siri 语音键", "Siri")
        case .ringUp: return L10n.t("外环上滑", "Ring up")
        case .ringDown: return L10n.t("外环下滑", "Ring down")
        case .ringLeft: return L10n.t("外环左滑", "Ring left")
        case .ringRight: return L10n.t("外环右滑", "Ring right")
        case .swipeUp: return L10n.t("上滑", "Swipe up")
        case .swipeDown: return L10n.t("下滑", "Swipe down")
        case .swipeLeft: return L10n.t("左滑", "Swipe left")
        case .swipeRight: return L10n.t("右滑", "Swipe right")
        case .tapTwo: return L10n.t("双击触控板", "Double tap")
        }
    }

    /// Official behaviour from Apple's Siri Remote guide. The app does not
    /// have to copy the Apple TV action, but this is the reference shown in
    /// the mapping page.
    public var officialFunction: String {
        switch self {
        case .power: return L10n.t("开机或关机", "Turn on or off")
        case .up, .down, .left, .right: return L10n.t("在屏幕上导航", "Navigate the screen")
        case .select: return L10n.t("确认当前选择", "Confirm the selection")
        case .back: return L10n.t("返回上一屏；长按回主屏幕", "Back; hold for Home")
        case .tv: return L10n.t("打开 Apple TV；长按控制中心", "Open Apple TV; hold for Control Center")
        case .playPause: return L10n.t("播放或暂停", "Play or pause")
        case .volumeUp, .volumeDown: return L10n.t("调节音量", "Adjust volume")
        case .mute: return L10n.t("静音或恢复", "Mute or unmute")
        case .siri: return L10n.t("按住说话或听写", "Hold to talk or dictate")
        case .ringUp, .ringDown, .ringLeft, .ringRight:
            return L10n.t("沿外环滑动", "Slide along the outer ring")
        case .swipeUp, .swipeDown, .swipeLeft, .swipeRight:
            return L10n.t("在触控板上快速划过", "Flick across the clickpad")
        case .tapTwo: return L10n.t("连续轻点两次", "Two quick taps")
        }
    }

    public var isVoice: Bool { self == .siri }

    public var isDirectional: Bool {
        switch self {
        case .up, .down, .left, .right: return true
        default: return false
        }
    }

    public var defaultAction: ButtonAction {
        switch self {
        case .select: return .key(.returnKey)
        case .back: return .key(.delete)
        case .tv: return .key(.appSwitcher)
        case .playPause: return .key(.mediaPlayPause)
        case .up: return .key(.upArrow)
        case .down: return .key(.downArrow)
        case .left: return .key(.leftArrow)
        case .right: return .key(.rightArrow)
        case .volumeUp: return .key(.volumeUp)
        case .volumeDown: return .key(.volumeDown)
        case .mute: return .key(.mute)
        case .power: return .key(.lockScreen)
        case .siri: return .none
        case .ringUp, .ringDown, .ringLeft, .ringRight,
             .swipeUp, .swipeDown, .swipeLeft, .swipeRight, .tapTwo:
            return .none
        }
    }

    public static var defaultActions: [RemoteControl: ButtonAction] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.defaultAction) })
    }
}
