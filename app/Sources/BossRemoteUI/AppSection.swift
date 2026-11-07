import BossRemoteCore
import SwiftUI

public enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case mapping
    case apps
    case connection
    case history
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mapping: return L10n.t("按键", "Buttons")
        case .apps: return L10n.t("APP 适配", "Apps")
        case .connection: return L10n.t("连接", "Connection")
        case .history: return L10n.t("记录", "Records")
        case .settings: return L10n.t("设置", "Settings")
        }
    }

    public var symbol: String {
        switch self {
        case .mapping: return "keyboard"
        case .apps: return "square.grid.2x2"
        case .connection: return "link"
        case .history: return "text.bubble"
        case .settings: return "gearshape"
        }
    }
}
