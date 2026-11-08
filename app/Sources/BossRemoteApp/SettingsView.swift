import AppKit
import BossRemoteCore
import BossRemoteUI
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject private var mapping: MappingStore
    @ObservedObject private var history: HistoryStore
    private let preview: Bool

    @State private var launchError: String?
    @State private var confirmResetMappings = false
    @State private var confirmClearProfiles = false
    @State private var confirmClearHistory = false
    @State private var hoveredAppearance: AppearancePreference?
    @State private var showSupport = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.bossCompact) private var compact

    init(model: AppModel, settings: AppSettings, preview: Bool = false) {
        self._model = ObservedObject(wrappedValue: model)
        self._settings = ObservedObject(wrappedValue: settings)
        self._mapping = ObservedObject(wrappedValue: model.mapping)
        self._history = ObservedObject(wrappedValue: model.history)
        self.preview = preview
    }

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if preview {
                columns
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    columns
                }
            }
        }
        .padding(.horizontal, BossMetrics.pageHorizontal)
        .padding(.top, BossMetrics.pageTop)
        .padding(.bottom, BossMetrics.pageBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if !preview {
                model.refreshPermissions()
            }
            settings.launchAtLogin = LaunchAtLogin.isEnabled
        }
        .alert(
            L10n.t("恢复全局默认映射？", "Restore global defaults?"),
            isPresented: $confirmResetMappings
        ) {
            Button(L10n.t("恢复", "Restore"), role: .destructive) {
                mapping.reset()
            }
            Button(L10n.t("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t(
                "所有全局按键恢复默认；App 专属映射不受影响。",
                "All global buttons return to defaults; app overrides are kept."
            ))
        }
        .alert(
            L10n.t("清除所有 App 适配？", "Clear all app mappings?"),
            isPresented: $confirmClearProfiles
        ) {
            Button(L10n.t("清除", "Clear"), role: .destructive) {
                mapping.resetProfiles()
            }
            Button(L10n.t("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t(
                "所有 App 的专属映射会被删除，之后统一使用全局映射。",
                "Every app override will be removed; all apps fall back to global."
            ))
        }
        .alert(
            L10n.t("清除记录？", "Clear records?"),
            isPresented: $confirmClearHistory
        ) {
            Button(L10n.t("清除", "Clear"), role: .destructive) {
                model.clearHistory()
            }
            Button(L10n.t("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t(
                "本机的按键、语音会话和映射变更记录会被删除。",
                "Local button, voice-session and mapping records will be removed."
            ))
        }
    }

    private var columns: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 30) {
                    startupAndPermissions
                    voiceCard
                    aboutCard
                    appearanceSection
                    inputCard
                    relayCard
                    dataCard
                }
            } else {
                HStack(alignment: .top, spacing: 36) {
                    VStack(alignment: .leading, spacing: 30) {
                        startupAndPermissions
                        voiceCard
                        aboutCard
                    }
                    VStack(alignment: .leading, spacing: 30) {
                        appearanceSection
                        inputCard
                        relayCard
                        dataCard
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var appearanceSection: some View {
        SettingsCard(
            title: L10n.t("外观", "Appearance"),
            symbol: "circle.lefthalf.filled",
            subtitle: settings.appearance.title
        ) {
            HStack(spacing: 4) {
                ForEach(AppearancePreference.allCases) { mode in
                    let selected = settings.appearance == mode
                    let hovered = hoveredAppearance == mode
                    Button {
                        settings.appearance = mode
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 9, weight: .semibold))
                            Text(mode.title)
                                .font(BossTheme.label(
                                    10.5,
                                    weight: selected ? .semibold : .medium
                                ))
                        }
                        .foregroundStyle(
                            selected ? BossTheme.accent : BossTheme.secondary
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(
                                selected
                                    ? BossTheme.accent.opacity(0.10)
                                    : (hovered
                                        ? BossTheme.controlFillHover
                                        : Color.clear)
                            )
                        )
                        .overlay(
                            Capsule().stroke(
                                selected
                                    ? BossTheme.accent.opacity(0.24)
                                    : Color.clear,
                                lineWidth: 1
                            )
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.12)) {
                            if hovering {
                                hoveredAppearance = mode
                            } else if hoveredAppearance == mode {
                                hoveredAppearance = nil
                            }
                        }
                    }
                    .accessibilityLabel(mode.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Capsule().fill(BossTheme.controlFill))
        }
    }

    private var header: some View {
        BossPageHeader(
            title: L10n.t("设置", "Settings"),
            subtitle: L10n.t(
                "启动、输入、语音与映射数据",
                "Startup, input, voice and mapping data"
            )
        ) {
            Text(version)
                .font(BossTheme.mono(10, weight: .medium))
                .foregroundStyle(BossTheme.tertiary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(BossTheme.surface.opacity(0.8)))
                .overlay(Capsule().stroke(BossTheme.hairline, lineWidth: 1))
        }
    }

    private var startupAndPermissions: some View {
        SettingsCard(
            title: L10n.t("启动与权限", "Startup & access"),
            symbol: "power",
            subtitle: LaunchAtLogin.statusDescription
        ) {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    title: L10n.t("登录时启动", "Launch at login"),
                    subtitle: L10n.t(
                        "登录 macOS 后自动运行 Boss Remote。",
                        "Start Boss Remote automatically after login."
                    ),
                    isOn: launchBinding
                )
                if launchError != nil {
                    Text(launchError ?? "")
                        .font(BossTheme.label(10))
                        .foregroundStyle(BossTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 6)
                }

                hairline

                permissionRow(
                    title: L10n.t("辅助功能", "Accessibility"),
                    detail: L10n.t(
                        "发送按键、移动指针和点击。",
                        "Sends keys, moves the pointer and clicks."
                    ),
                    granted: model.hasAccessibility,
                    grant: model.requestAccessibility,
                    open: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )

                hairline

                permissionRow(
                    title: L10n.t("输入监控", "Input Monitoring"),
                    detail: L10n.t(
                        "读取 Siri Remote 的按键与触控板。",
                        "Reads Siri Remote buttons and touchpad."
                    ),
                    granted: model.hasInputMonitoring,
                    grant: model.requestInputMonitoring,
                    open: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
                )
            }
        }
    }

    private var relayCard: some View {
        SettingsCard(
            title: L10n.t("云端转发", "Cloud relay"),
            symbol: "arrow.left.arrow.right",
            subtitle: L10n.t("默认关闭，只发遥控器事件", "Off by default; remote events only")
        ) {
            SettingsToggleRow(
                title: L10n.t("转发到本机回环", "Forward to loopback"),
                subtitle: L10n.t(
                    "把真实按键和触控发到 127.0.0.1。跨网请自己用 SSH 隧道。不转发麦克风，也不监听公网。",
                    "Sends real buttons and touch to 127.0.0.1. Use your own SSH tunnel off-box. No microphone and no public listener."
                ),
                isOn: relayBinding
            )
        }
    }

    private var inputCard: some View {
        SettingsCard(
            title: L10n.t("输入", "Input"),
            symbol: "hand.draw",
            subtitle: L10n.t("触控板与环形滚动", "Touchpad & ring scroll")
        ) {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    title: L10n.t("移动指针", "Move pointer"),
                    subtitle: L10n.t(
                        "滑动触控板内侧区域移动鼠标。",
                        "Slide the inner touch area to move the pointer."
                    ),
                    isOn: pointerBinding
                )
                hairline
                SettingsToggleRow(
                    title: L10n.t("环形滚动", "Ring scrolling"),
                    subtitle: L10n.t(
                        "沿触控板外圈滑动进行滚动。",
                        "Scroll by sliding along the outer ring."
                    ),
                    isOn: scrollBinding
                )
                hairline
                SettingsToggleRow(
                    title: L10n.t("轻点点击", "Tap to click"),
                    subtitle: L10n.t(
                        "轻点触控板发送一次鼠标点击。",
                        "Tap the touchpad to send a click."
                    ),
                    isOn: tapBinding
                )
                hairline
                SettingsToggleRow(
                    title: L10n.t("按下锁定指针", "Freeze pointer on press"),
                    subtitle: L10n.t(
                        "按下触控板时锁住指针，点击不会带偏光标。",
                        "Freeze the pointer while you press, so a click never drags the cursor."
                    ),
                    isOn: pressFreezeBinding
                )
                hairline
                speedRow(
                    title: L10n.t("指针速度", "Pointer speed"),
                    value: pointerSpeedBinding
                )
                speedRow(
                    title: L10n.t("滚动速度", "Scroll speed"),
                    value: scrollSpeedBinding
                )
                HStack {
                    Spacer()
                    Button(L10n.t("恢复输入默认值", "Reset input defaults")) {
                        settings.resetInputDefaults()
                        model.applySettings()
                    }
                    .buttonStyle(.plain)
                    .font(BossTheme.label(10, weight: .medium))
                    .foregroundStyle(BossTheme.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(BossTheme.controlFill))
                    .overlay(Capsule().stroke(BossTheme.hairline, lineWidth: 1))
                }
                .padding(.top, 6)
            }
        }
    }

    private var voiceCard: some View {
        SettingsCard(
            title: L10n.t("语音", "Voice"),
            symbol: "waveform",
            subtitle: nil
        ) {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    title: L10n.t("按住 Siri 发送右 Command", "Send right Command on Siri"),
                    subtitle: L10n.t(
                        "让豆包等语音输入识别为快捷键。",
                        "Lets Doubao and similar voice input see the shortcut."
                    ),
                    isOn: siriBinding
                )
                hairline
                HStack(spacing: 10) {
                    Circle()
                        .fill(BossTheme.accent)
                        .frame(width: 5, height: 5)
                        .shadow(color: BossTheme.accent.opacity(0.6), radius: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.t("语音服务", "Voice service"))
                            .font(BossTheme.label(12, weight: .medium))
                            .foregroundStyle(BossTheme.text)
                        Text(model.voiceStatus)
                            .font(BossTheme.label(10.5))
                            .foregroundStyle(BossTheme.tertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        model.restartVoice()
                    } label: {
                        Text(model.isRestartingVoice
                            ? L10n.t("重启中", "Restarting")
                            : L10n.t("重启", "Restart"))
                            .font(BossTheme.label(10, weight: .medium))
                            .foregroundStyle(BossTheme.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(BossTheme.controlFill))
                            .overlay(Capsule().stroke(BossTheme.hairline, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isRestartingVoice)
                    .opacity(model.isRestartingVoice ? 0.45 : 1)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var dataCard: some View {
        SettingsCard(
            title: L10n.t("映射与数据", "Mappings & data"),
            symbol: "square.stack.3d.up",
            subtitle: nil
        ) {
            VStack(spacing: 0) {
                dataRow(
                    title: L10n.t("恢复全局默认映射", "Restore global defaults"),
                    detail: L10n.t("保留 App 专属映射", "App overrides are kept"),
                    destructive: false
                ) {
                    confirmResetMappings = true
                }
                hairline
                dataRow(
                    title: L10n.t("清除所有 App 适配", "Clear app mappings"),
                    detail: L10n.t(
                        "\(mapping.profileList.count) 个 App",
                        mapping.profileList.count == 1
                            ? "1 app"
                            : "\(mapping.profileList.count) apps"
                    ),
                    destructive: true
                ) {
                    confirmClearProfiles = true
                }
                hairline
                dataRow(
                    title: L10n.t("清除记录", "Clear records"),
                    detail: L10n.t(
                        "\(history.events.count) 条记录",
                        history.events.count == 1
                            ? "1 record"
                            : "\(history.events.count) records"
                    ),
                    destructive: true
                ) {
                    confirmClearHistory = true
                }
            }
        }
    }

    private var aboutCard: some View {
        SettingsCard(
            title: L10n.t("关于", "About"),
            symbol: "info.circle",
            subtitle: nil
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Boss Remote")
                        .font(BossTheme.label(12, weight: .semibold))
                        .foregroundStyle(BossTheme.text)
                    Spacer()
                    Text(version)
                        .font(BossTheme.mono(10))
                        .foregroundStyle(BossTheme.tertiary)
                }
                Text(L10n.t(
                    "为 Siri Remote 设计的 macOS 按键映射与语音桥接。",
                    "Button mapping and voice bridge for the Siri Remote on macOS."
                ))
                .font(BossTheme.label(10.5))
                .foregroundStyle(BossTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    aboutLink(L10n.t("GitHub 说明", "GitHub guide")) {
                        openURL("https://github.com/h1149806033-oss/siri-remote-vibe-coding")
                    }
                    aboutLink(L10n.t("Apple 支持", "Apple support")) {
                        openURL("https://support.apple.com/102337")
                    }
                    supportToggle
                }
                if showSupport {
                    hairline
                        .padding(.top, 6)
                    supportBlock
                        .transition(.opacity)
                }
            }
        }
    }

    private var supportToggle: some View {
        Button {
            if reduceMotion {
                showSupport.toggle()
            } else {
                withAnimation(.easeOut(duration: 0.18)) {
                    showSupport.toggle()
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(L10n.t("支持开发者", "Support"))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .rotationEffect(.degrees(showSupport ? 180 : 0))
            }
            .font(BossTheme.label(10.5, weight: .medium))
            .foregroundStyle(BossTheme.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("支持开发者", "Support the developer"))
        .accessibilityValue(showSupport
            ? L10n.t("已展开", "Expanded")
            : L10n.t("已收起", "Collapsed"))
    }

    private var supportBlock: some View {
        HStack(alignment: .center, spacing: 16) {
            if let qr = Self.supportQR {
                Image(nsImage: qr)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 132, height: 132)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(BossTheme.hairline, lineWidth: 1)
                    )
                    .shadow(
                        color: BossTheme.objectShadowSoft,
                        radius: 6,
                        y: 2
                    )
                    .accessibilityLabel(L10n.t("赞赏码", "Tip QR code"))
            }
            Text(L10n.t(
                "一个人、几个通宵，慢慢磨出来的小工具。如果它让你顺手了一点，随意支持就好。",
                "A small tool built alone over a handful of late nights. If it makes your day a little smoother, a tip is welcome — never expected."
            ))
            .font(BossTheme.label(10.5))
            .foregroundStyle(BossTheme.tertiary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private static let supportQR: NSImage? = {
        guard let url = Bundle.main.url(
            forResource: "SupportQR",
            withExtension: "png"
        ) else { return nil }
        return NSImage(contentsOf: url)
    }()

    private var pointerBinding: Binding<Bool> {
        Binding(
            get: { settings.pointerEnabled },
            set: { settings.pointerEnabled = $0; model.applySettings() }
        )
    }

    private var scrollBinding: Binding<Bool> {
        Binding(
            get: { settings.scrollEnabled },
            set: { settings.scrollEnabled = $0; model.applySettings() }
        )
    }

    private var pressFreezeBinding: Binding<Bool> {
        Binding(
            get: { settings.pressFreeze },
            set: { settings.pressFreeze = $0; model.applySettings() }
        )
    }

    private var tapBinding: Binding<Bool> {
        Binding(
            get: { settings.tapToClick },
            set: { settings.tapToClick = $0; model.applySettings() }
        )
    }

    private var siriBinding: Binding<Bool> {
        Binding(
            get: { settings.siriRightCommand },
            set: { settings.siriRightCommand = $0 }
        )
    }

    private var pointerSpeedBinding: Binding<Double> {
        Binding(
            get: { settings.pointerSpeed },
            set: { settings.pointerSpeed = $0; model.applySettings() }
        )
    }

    private var scrollSpeedBinding: Binding<Double> {
        Binding(
            get: { settings.scrollSpeed },
            set: { settings.scrollSpeed = $0; model.applySettings() }
        )
    }

    private var relayBinding: Binding<Bool> {
        Binding(
            get: { settings.relayEnabled },
            set: { settings.relayEnabled = $0; model.refreshRelay() }
        )
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { enabled in
                do {
                    try LaunchAtLogin.setEnabled(enabled)
                    settings.launchAtLogin = enabled
                    launchError = nil
                } catch {
                    settings.launchAtLogin = LaunchAtLogin.isEnabled
                    launchError = error.localizedDescription
                }
            }
        )
    }

    private var hairline: some View {
        Rectangle()
            .fill(BossTheme.hairline)
            .frame(height: 1)
    }

    private func permissionRow(
        title: String,
        detail: String,
        granted: Bool,
        grant: @escaping () -> Void,
        open: String
    ) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(granted ? BossTheme.success : BossTheme.tertiary)
                .frame(width: 6, height: 6)
                .shadow(
                    color: granted ? BossTheme.success.opacity(0.5) : .clear,
                    radius: 3
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(BossTheme.label(12, weight: .medium))
                    .foregroundStyle(BossTheme.text)
                Text(detail)
                    .font(BossTheme.label(10.5))
                    .foregroundStyle(BossTheme.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if !granted {
                smallButton(L10n.t("授权", "Grant"), action: grant)
            }
            smallButton(L10n.t("打开设置", "Open")) {
                if let url = URL(string: open) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(.vertical, 10)
    }

    private func speedRow(title: String, value: Binding<Double>) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title)
                    .font(BossTheme.label(11.5, weight: .medium))
                    .foregroundStyle(BossTheme.secondary)
                Spacer()
                Text(String(format: "%.2f×", value.wrappedValue))
                    .font(BossTheme.mono(10.5, weight: .medium))
                    .foregroundStyle(BossTheme.tertiary)
            }
            BossSlider(value: value, in: 0.5...2.0, step: 0.05)
        }
        .padding(.vertical, 8)
    }

    private func dataRow(
        title: String,
        detail: String,
        destructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(BossTheme.label(12, weight: .medium))
                    .foregroundStyle(destructive ? BossTheme.danger : BossTheme.text)
                Text(detail)
                    .font(BossTheme.label(10.5))
                    .foregroundStyle(BossTheme.tertiary)
            }
            Spacer()
            Button(action: action) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(BossTheme.tertiary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(BossTheme.controlFill))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
    }

    private func aboutLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(BossTheme.label(10.5, weight: .medium))
                .foregroundStyle(BossTheme.accent)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(BossTheme.label(10, weight: .medium))
                .foregroundStyle(BossTheme.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(BossTheme.controlFill))
                .overlay(Capsule().stroke(BossTheme.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    let subtitle: String?
    let content: Content

    init(
        title: String,
        symbol: String,
        subtitle: String?,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BossSectionHeader(
                icon: symbol,
                title: title,
                detail: subtitle
            )
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(BossTheme.label(12, weight: .medium))
                    .foregroundStyle(BossTheme.text)
                Text(subtitle)
                    .font(BossTheme.label(10.5))
                    .foregroundStyle(BossTheme.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            BossSwitch(isOn: $isOn)
                .accessibilityLabel(title)
        }
        .padding(.vertical, 10)
    }
}
