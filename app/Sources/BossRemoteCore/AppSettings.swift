import Combine
import Foundation

public final class AppSettings: ObservableObject {
    private enum Key {
        static let launchAtLogin = "bossRemote.settings.launchAtLogin"
        static let siriRightCommand = "bossRemote.settings.siriRightCommand"
        static let pointerEnabled = "bossRemote.settings.pointerEnabled"
        static let scrollEnabled = "bossRemote.settings.scrollEnabled"
        static let tapToClick = "bossRemote.settings.tapToClick"
        static let pressFreeze = "bossRemote.settings.pressFreeze"
        static let pointerSpeed = "bossRemote.settings.pointerSpeed"
        static let scrollSpeed = "bossRemote.settings.scrollSpeed"
        static let historyEnabled = "bossRemote.settings.historyEnabled"
        static let appearance = "bossRemote.settings.appearance"
    }

    @Published public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    @Published public var siriRightCommand: Bool {
        didSet { defaults.set(siriRightCommand, forKey: Key.siriRightCommand) }
    }

    @Published public var pointerEnabled: Bool {
        didSet { defaults.set(pointerEnabled, forKey: Key.pointerEnabled) }
    }

    @Published public var scrollEnabled: Bool {
        didSet { defaults.set(scrollEnabled, forKey: Key.scrollEnabled) }
    }

    @Published public var tapToClick: Bool {
        didSet { defaults.set(tapToClick, forKey: Key.tapToClick) }
    }

    @Published public var pressFreeze: Bool {
        didSet { defaults.set(pressFreeze, forKey: Key.pressFreeze) }
    }

    @Published public var pointerSpeed: Double {
        didSet { defaults.set(pointerSpeed, forKey: Key.pointerSpeed) }
    }

    @Published public var scrollSpeed: Double {
        didSet { defaults.set(scrollSpeed, forKey: Key.scrollSpeed) }
    }

    @Published public var historyEnabled: Bool {
        didSet { defaults.set(historyEnabled, forKey: Key.historyEnabled) }
    }

    @Published public var appearance: AppearancePreference {
        didSet {
            defaults.set(appearance.rawValue, forKey: Key.appearance)
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false
        siriRightCommand = defaults.object(forKey: Key.siriRightCommand) as? Bool ?? true
        pointerEnabled = defaults.object(forKey: Key.pointerEnabled) as? Bool ?? true
        scrollEnabled = defaults.object(forKey: Key.scrollEnabled) as? Bool ?? true
        tapToClick = defaults.object(forKey: Key.tapToClick) as? Bool ?? true
        pressFreeze = defaults.object(forKey: Key.pressFreeze) as? Bool ?? true
        pointerSpeed = defaults.object(forKey: Key.pointerSpeed) as? Double ?? 1
        scrollSpeed = defaults.object(forKey: Key.scrollSpeed) as? Double ?? 1
        historyEnabled = defaults.object(forKey: Key.historyEnabled) as? Bool ?? true
        appearance = AppearancePreference(
            rawValue: defaults.string(forKey: Key.appearance) ?? ""
        ) ?? .dark
    }

    public static func storedAppearance(
        in defaults: UserDefaults = .standard
    ) -> AppearancePreference {
        AppearancePreference(
            rawValue: defaults.string(forKey: Key.appearance) ?? ""
        ) ?? .dark
    }

    public func resetInputDefaults() {
        pointerEnabled = true
        scrollEnabled = true
        tapToClick = true
        pressFreeze = true
        pointerSpeed = 1
        scrollSpeed = 1
    }
}
