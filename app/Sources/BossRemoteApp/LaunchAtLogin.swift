import BossRemoteCore
import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return L10n.t("已启用", "Enabled")
        case .requiresApproval:
            return L10n.t("等待系统批准", "Waiting for approval")
        case .notRegistered:
            return L10n.t("未启用", "Disabled")
        case .notFound:
            return L10n.t(
                "移到「应用程序」后可启用",
                "Move to Applications to enable"
            )
        @unknown default:
            return L10n.t("未知状态", "Unknown")
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status != .notRegistered else { return }
            try SMAppService.mainApp.unregister()
        }
    }
}
