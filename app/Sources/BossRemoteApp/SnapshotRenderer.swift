import AppKit
import BossRemoteCore
import BossRemoteUI
import SwiftUI

@MainActor
enum SnapshotRenderer {
    static func renderIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["BOSS_REMOTE_UI_SNAPSHOT"] else {
            return false
        }
        let suite = "BossRemote.Snapshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let store = MappingStore(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: suite) }

        let canvasOnly = ProcessInfo.processInfo.environment[
            "BOSS_REMOTE_SNAPSHOT_CANVAS"
        ] == "1"
        let snapshotWidth = CGFloat(
            Double(ProcessInfo.processInfo.environment[
                "BOSS_REMOTE_SNAPSHOT_WIDTH"
            ] ?? "") ?? 1180
        )
        let snapshotHeight = CGFloat(
            Double(ProcessInfo.processInfo.environment[
                "BOSS_REMOTE_SNAPSHOT_HEIGHT"
            ] ?? "") ?? 820
        )
        let previewActive: Set<RemoteControl> = {
            switch ProcessInfo.processInfo.environment["BOSS_REMOTE_SNAPSHOT_ACTIVE"] {
            case "siri": return [.siri]
            case "volumeUp": return [.volumeUp]
            case "volumeDown": return [.volumeDown]
            default: return []
            }
        }()
        let content: AnyView
        if let pageName = ProcessInfo.processInfo.environment["BOSS_REMOTE_SNAPSHOT_PAGE"] {
            content = snapshotShell(
                page: pageName,
                width: snapshotWidth,
                height: snapshotHeight
            )
        } else if canvasOnly {
            content = AnyView(
                RemoteCanvas(
                    selected: .constant(.select),
                    active: previewActive
                )
                .padding(24)
                .background(Color(white: 0.08))
            )
        } else {
            content = AnyView(
                MappingContentView(
                    store: store,
                    selected: .constant(.select),
                    active: previewActive,
                    connected: true,
                    battery: 47,
                    batteryAvailable: true,
                    status: L10n.t("已连接，按遥控器按钮测试", "Connected, try a remote button"),
                    voiceStatus: L10n.t("语音组件就绪", "Voice ready"),
                    preview: true
                )
                .frame(width: snapshotWidth, height: snapshotHeight)
                .background(BossBackground())
            )
        }

        let appearanceName = ProcessInfo.processInfo.environment[
            "BOSS_REMOTE_SNAPSHOT_APPEARANCE"
        ]
        let preference = appearanceName.flatMap(
            AppearancePreference.init(rawValue:)
        ) ?? AppSettings.storedAppearance()
        let scheme = AppAppearance.colorScheme(for: preference)
        let rendered = scheme.map {
            AnyView(content.environment(\.colorScheme, $0))
        } ?? content
        let renderer = ImageRenderer(content: rendered)
        renderer.scale = 2
        renderer.proposedSize = canvasOnly
            ? ProposedViewSize(width: 340, height: 900)
            : ProposedViewSize(width: snapshotWidth, height: snapshotHeight)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return false }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("BOSS_REMOTE_SNAPSHOT \(path)")
            return true
        } catch {
            return false
        }
    }

    private static func snapshotShell(
        page: String,
        width: CGFloat,
        height: CGFloat
    ) -> AnyView {
        let sidebarCollapsed = ProcessInfo.processInfo.environment[
            "BOSS_REMOTE_SNAPSHOT_SIDEBAR_COLLAPSED"
        ] == "1"
        let suite = "BossRemote.Snapshot.Page.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let historyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BossRemote-preview-history-\(UUID().uuidString).json"
            )
        let batteryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BossRemote-preview-battery-\(UUID().uuidString).json"
            )
        let voiceStatsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BossRemote-preview-voicestats-\(UUID().uuidString).json"
            )
        let model = AppModel(
            defaults: defaults,
            historyFileURL: historyURL,
            batteryFileURL: batteryURL,
            voiceStatsFileURL: voiceStatsURL
        )

        model.mapping.ensureProfile(bundleID: "com.apple.Safari", displayName: "Safari")
        model.mapping.setAction(
            .key(.appSwitcher),
            for: .back,
            bundleID: "com.apple.Safari"
        )
        model.mapping.ensureProfile(bundleID: "com.apple.dt.Xcode", displayName: "Xcode")
        model.mapping.setAction(
            .key(.space),
            for: .tv,
            bundleID: "com.apple.dt.Xcode"
        )
        model.seedSnapshotState()

        let now = Date()
        model.history.record(ActivityEvent(
            date: now,
            kind: .button,
            control: .select,
            actionLabel: KeyBinding.returnKey.title,
            appName: "Safari",
            bundleID: "com.apple.Safari",
            scopeLabel: "Safari",
            count: 3
        ))
        model.history.record(ActivityEvent(
            date: now.addingTimeInterval(-45),
            kind: .voice,
            appName: "Safari",
            bundleID: "com.apple.Safari",
            scopeLabel: "Safari",
            duration: 2.4,
            frames: 58,
            detail: L10n.t("按住 Siri 语音输入", "Siri voice input")
        ))
        model.history.record(ActivityEvent(
            date: now.addingTimeInterval(-3600),
            kind: .mapping,
            control: .back,
            actionLabel: KeyBinding.appSwitcher.title,
            appName: "Safari",
            bundleID: "com.apple.Safari",
            scopeLabel: "Safari",
            detail: L10n.t("设置 App 专属按键", "Set app override")
        ))
        model.history.record(ActivityEvent(
            date: now.addingTimeInterval(-3700),
            kind: .app,
            appName: "Safari",
            bundleID: "com.apple.Safari",
            scopeLabel: "Safari",
            detail: L10n.t("已切换到 App 专属映射", "Switched to app mapping")
        ))
        model.history.record(ActivityEvent(
            date: now.addingTimeInterval(-25 * 3600),
            kind: .button,
            control: .playPause,
            actionLabel: KeyBinding.mediaPlayPause.title,
            appName: "Xcode",
            bundleID: "com.apple.dt.Xcode",
            scopeLabel: L10n.t("全局", "Global"),
            count: 2
        ))

        let indicator = TouchIndicatorModel()
        if let raw = ProcessInfo.processInfo.environment[
            "BOSS_REMOTE_SNAPSHOT_TOUCH"
        ] {
            let parts = raw.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                indicator.setForPreview(x: parts[0], y: parts[1])
            }
        }

        let section: AppSection
        let pageView: AnyView
        switch page {
        case "apps":
            section = .apps
            pageView = AnyView(
                AppAdaptationView(model: model, preview: true) { _ in }
            )
        case "connection":
            section = .connection
            pageView = AnyView(ConnectionView(model: model, preview: true))
        case "history":
            section = .history
            pageView = AnyView(
                HistoryView(
                    model: model,
                    history: model.history,
                    settings: model.settings,
                    preview: true
                )
            )
        case "settings":
            section = .settings
            pageView = AnyView(
                SettingsView(
                    model: model,
                    settings: model.settings,
                    preview: true
                )
            )
        default:
            section = .mapping
            pageView = AnyView(
                MappingContentView(
                    store: model.mapping,
                    selected: .constant(model.selectedControl),
                    active: [],
                    connected: model.connected,
                    battery: model.battery,
                    batteryAvailable: model.batteryInsights.batteryAvailable,
                    charging: model.isCharging,
                    status: model.status,
                    voiceStatus: model.voiceStatus,
                    scopeBundleID: .constant(nil),
                    onManageApps: {},
                    touchIndicator: indicator,
                    preview: true
                )
            )
        }

        return AnyView(
            ZStack {
                HStack(spacing: 0) {
                    SidebarBackdrop()
                        .frame(width: sidebarCollapsed ? 68 : 204)
                        .overlay(alignment: .trailing) {
                            Rectangle()
                                .fill(BossTheme.hairline)
                                .frame(width: 1)
                        }
                    BossBackground()
                }
                .ignoresSafeArea()

                HStack(spacing: 0) {
                    SidebarView(
                        selection: .constant(section),
                        connected: model.connected,
                        deviceName: model.deviceName,
                        voiceStatus: model.voiceStatus,
                        appVersion: "0.1.0",
                        profileCount: model.appProfileCount,
                        collapsed: sidebarCollapsed,
                        onToggle: {}
                    )
                    pageView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: width, height: height)
            .environment(
                \.bossCompact,
                width - (sidebarCollapsed ? 68 : 204) < 1000
            )
        )
    }
}
