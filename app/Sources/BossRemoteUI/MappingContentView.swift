import BossRemoteCore
import SwiftUI

public struct MappingContentView: View {
    @ObservedObject private var store: MappingStore
    @Binding private var selected: RemoteControl
    private let active: Set<RemoteControl>
    private let connected: Bool
    private let battery: Int?
    private let batteryAvailable: Bool
    private let charging: Bool
    private let status: String
    private let voiceStatus: String
    @Binding private var scopeBundleID: String?
    private let onManageApps: () -> Void
    private let touchIndicator: TouchIndicatorModel?
    private let preview: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.bossCompact) private var compact
    @State private var hoveredRow: RemoteControl?
    @State private var keyPickerOpen = false
    @State private var holdPickerOpen = false
    @State private var scopePickerOpen = false
    @State private var keyMenuHovered = false
    @State private var holdMenuHovered = false
    @State private var keySearch = ""

    public init(
        store: MappingStore,
        selected: Binding<RemoteControl>,
        active: Set<RemoteControl>,
        connected: Bool,
        battery: Int?,
        batteryAvailable: Bool = true,
        charging: Bool = false,
        status: String,
        voiceStatus: String,
        scopeBundleID: Binding<String?> = .constant(nil),
        onManageApps: @escaping () -> Void = {},
        touchIndicator: TouchIndicatorModel? = nil,
        preview: Bool = false
    ) {
        self.store = store
        self._selected = selected
        self.active = active
        self.connected = connected
        self.battery = battery
        self.batteryAvailable = batteryAvailable
        self.charging = charging
        self.status = status
        self.voiceStatus = voiceStatus
        self._scopeBundleID = scopeBundleID
        self.onManageApps = onManageApps
        self.touchIndicator = touchIndicator
        self.preview = preview
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            GeometryReader { proxy in
                let narrow = proxy.size.width < 700
                let stageWidth: CGFloat = narrow ? 200 : 292
                let stageHeight = max(
                    narrow ? 400 : (compact ? 440 : 520),
                    min(760, proxy.size.height - 8)
                )
                HStack(alignment: .top, spacing: narrow ? 20 : 28) {
                    RemoteCanvas(
                        selected: Binding(
                            get: { selected.canvasControl },
                            set: { selected = $0 }
                        ),
                        active: active,
                        stageWidth: stageWidth,
                        stageHeight: stageHeight,
                        touchIndicator: touchIndicator
                    )
                    VStack(alignment: .leading, spacing: 22) {
                        inspector
                        if preview {
                            controlIndex
                        } else {
                            ScrollView(.vertical, showsIndicators: true) {
                                controlIndex
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(.horizontal, BossMetrics.pageHorizontal)
        .padding(.top, BossMetrics.pageTop)
        .padding(.bottom, BossMetrics.pageBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: selected) { _, _ in
            keyPickerOpen = false
            holdPickerOpen = false
        }
        .onChange(of: scopeBundleID) { _, _ in
            keyPickerOpen = false
            holdPickerOpen = false
            scopePickerOpen = false
        }
        .onChange(of: keyPickerOpen) { _, open in
            if !open {
                keySearch = ""
            }
        }
        .onChange(of: holdPickerOpen) { _, open in
            if !open {
                keySearch = ""
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(L10n.t("按键映射", "Button Mapping"))
                        .font(BossTheme.display(22, weight: .bold))
                        .foregroundStyle(BossTheme.text)
                    scopeChip
                }
                Text(status)
                    .font(BossTheme.label(11))
                    .foregroundStyle(BossTheme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 20)
            HStack(spacing: 10) {
                statusPill(
                    dot: connected ? BossTheme.success : BossTheme.tertiary,
                    title: connected
                        ? L10n.t("已连接", "Connected")
                        : L10n.t("等待连接", "Waiting"),
                    battery: connected ? battery : nil,
                    batteryAvailable: batteryAvailable,
                    charging: connected && charging
                )
                if !compact {
                    voicePill
                }
            }
        }
    }

    private var activeScopeBundleID: String? {
        guard let scopeBundleID, store.profile(for: scopeBundleID) != nil else {
            return nil
        }
        return scopeBundleID
    }

    private var isAppScope: Bool {
        activeScopeBundleID != nil
    }

    private var scopeProfile: AppProfile? {
        store.profile(for: activeScopeBundleID)
    }

    private var scopeTitle: String {
        scopeProfile?.displayName ?? L10n.t("全局映射", "Global")
    }

    private var scopeChip: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.20)) {
                scopePickerOpen.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isAppScope ? "app" : "globe")
                    .font(.system(size: 8.5, weight: .semibold))
                Text(scopeTitle)
                    .font(BossTheme.label(10, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .semibold))
                    .rotationEffect(.degrees(scopePickerOpen ? 180 : 0))
            }
            .foregroundStyle(isAppScope ? BossTheme.accent : BossTheme.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    isAppScope
                        ? BossTheme.accent.opacity(0.10)
                        : BossTheme.controlFill
                )
            )
            .overlay(
                Capsule().stroke(
                    isAppScope
                        ? BossTheme.accent.opacity(0.25)
                        : BossTheme.hairline,
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $scopePickerOpen, arrowEdge: .top) {
            scopePicker
        }
    }

    private var scopePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("映射作用域", "Mapping scope"))
                .font(BossTheme.label(9.5, weight: .semibold))
                .foregroundStyle(BossTheme.tertiary)
                .padding(.horizontal, 9)
                .padding(.top, 3)

            scopeChoice(
                bundleID: nil,
                name: L10n.t("全局映射", "Global"),
                symbol: "globe"
            )

            if store.profileList.isEmpty {
                Text(L10n.t(
                    "还没有 App 专属映射",
                    "No app-specific mappings yet"
                ))
                .font(BossTheme.label(9))
                .foregroundStyle(BossTheme.tertiary)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
            } else {
                ForEach(store.profileList) { profile in
                    scopeChoice(
                        bundleID: profile.bundleID,
                        name: profile.displayName,
                        symbol: "app"
                    )
                }
            }

            Rectangle()
                .fill(BossTheme.hairline)
                .frame(height: 1)
                .padding(.vertical, 3)

            Button {
                scopePickerOpen = false
                onManageApps()
            } label: {
                Label(
                    L10n.t("管理 App 适配…", "Manage app mappings…"),
                    systemImage: "square.grid.2x2"
                )
                .font(BossTheme.label(9.5, weight: .medium))
                .foregroundStyle(BossTheme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .frame(width: 260)
        .background(BossTheme.background)
    }

    private func scopeChoice(
        bundleID: String?,
        name: String,
        symbol: String
    ) -> some View {
        let selected = activeScopeBundleID == bundleID
        return Button {
            withAnimation(.snappy(duration: 0.20)) {
                scopeBundleID = bundleID
                scopePickerOpen = false
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .medium))
                    .frame(width: 16)
                Text(name)
                    .font(BossTheme.label(11, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                }
            }
            .foregroundStyle(selected ? BossTheme.accent : BossTheme.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? BossTheme.accent.opacity(0.10) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func resolvedAction(for control: RemoteControl) -> ButtonAction {
        store.action(for: control, bundleID: activeScopeBundleID)
    }

    private var appMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.150, green: 0.164, blue: 0.190),
                            Color(red: 0.058, green: 0.066, blue: 0.080),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.03),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)

            ZStack {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.960, green: 0.966, blue: 0.974),
                                Color(red: 0.706, green: 0.722, blue: 0.742),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 13, height: 27)
                Circle()
                    .fill(Color(red: 0.055, green: 0.060, blue: 0.070))
                    .frame(width: 8, height: 8)
                    .offset(y: -5)
                Capsule()
                    .fill(BossTheme.accent)
                    .frame(width: 4, height: 1.4)
                    .offset(y: 8)
            }
            .shadow(color: .black.opacity(0.28), radius: 2, x: 0, y: 1)
        }
        .frame(width: 42, height: 42)
    }

    private func statusPill(
        dot: Color,
        title: String,
        battery: Int?,
        batteryAvailable: Bool,
        charging: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
                .shadow(color: dot.opacity(0.7), radius: 4)
            Text(title)
                .font(BossTheme.label(10.5))
                .foregroundStyle(BossTheme.secondary)
            BossSeparator()
            if charging {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text(L10n.t("充电中", "Charging"))
                        .font(BossTheme.label(9, weight: .medium))
                }
                .foregroundStyle(BossTheme.success)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(
                    Capsule().fill(BossTheme.success.opacity(0.10))
                )
                .overlay(
                    Capsule().stroke(
                        BossTheme.success.opacity(0.22),
                        lineWidth: 0.8
                    )
                )
                .help(L10n.t(
                    "遥控器通过 BLE 只上报电量，充电状态根据电量上升判断",
                    "The remote only reports level over BLE; charging is inferred from rising level"
                ))
                BossSeparator()
            }
            if let battery {
                Image(systemName: batterySymbol(for: battery))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(
                        battery <= 20
                            ? BossTheme.danger
                            : (charging
                                ? BossTheme.success
                                : (batteryAvailable
                                    ? BossTheme.secondary
                                    : BossTheme.tertiary))
                    )
                Text("\(battery)%")
                    .font(BossTheme.mono(10, weight: .medium))
                    .foregroundStyle(
                        charging
                            ? BossTheme.success
                            : (batteryAvailable
                                ? BossTheme.secondary
                                : BossTheme.tertiary)
                    )
                    .help(batteryAvailable
                        ? L10n.t("当前电量", "Current battery")
                        : L10n.t(
                            "显示上次读取的电量",
                            "Showing the last known battery level"
                        ))
            } else {
                Image(systemName: "battery.0percent")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(BossTheme.tertiary)
                Text("—")
                    .font(BossTheme.mono(10, weight: .medium))
                    .foregroundStyle(BossTheme.tertiary)
                    .help(L10n.t(
                        "macOS 尚未提供 Siri Remote 电量",
                        "macOS has not provided the Siri Remote battery level"
                    ))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(BossTheme.surface.opacity(0.82)))
        .overlay(Capsule().stroke(BossTheme.hairline, lineWidth: 1))
    }

    private func batterySymbol(for level: Int) -> String {
        switch level {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private var voicePill: some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BossTheme.accent)
            Text(voiceStatus)
                .font(BossTheme.label(10.5))
                .foregroundStyle(BossTheme.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(BossTheme.surface.opacity(0.82)))
        .overlay(Capsule().stroke(BossTheme.hairline, lineWidth: 1))
        .help(voiceStatus)
    }

    // MARK: Inspector

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selected.title)
                        .font(BossTheme.display(20, weight: .semibold))
                        .foregroundStyle(BossTheme.text)
                    Text(selected.officialFunction)
                        .font(BossTheme.label(11))
                        .foregroundStyle(BossTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if !selected.isVoice {
                    tag(tagText, accent: tagAccent)
                }
            }

            BossRule()

            if selected.isVoice {
                voiceEditor
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    keyEditor
                    if !selected.isGesture {
                        holdEditor
                    }
                    if selected == .down {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.tap")
                                .font(.system(size: 9.5, weight: .medium))
                            Text(
                                L10n.t(
                                    "双击输入「，」",
                                    "Double-press types 「，」"
                                )
                            )
                            .font(BossTheme.label(10))
                        }
                        .foregroundStyle(BossTheme.tertiary)
                    }
                }
            }
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isGlobalScope: Bool {
        activeScopeBundleID == nil
    }

    private var isDefault: Bool {
        isGlobalScope && store.action(for: selected) == selected.defaultAction
    }

    private var isFollowingGlobal: Bool {
        isAppScope && !store.isOverride(for: selected, bundleID: activeScopeBundleID)
    }

    private var tagText: String {
        if isGlobalScope {
            return isDefault
                ? L10n.t("默认", "Default")
                : L10n.t("自定义", "Custom")
        }
        return isFollowingGlobal
            ? L10n.t("跟随全局", "Following global")
            : L10n.t("自定义", "Custom")
    }

    private var tagAccent: Bool {
        isGlobalScope ? !isDefault : !isFollowingGlobal
    }

    private var canReset: Bool {
        if isGlobalScope {
            return store.action(for: selected) != selected.defaultAction
        }
        return store.isOverride(for: selected, bundleID: activeScopeBundleID)
    }

    private var selectedAction: ButtonAction {
        store.action(for: selected, bundleID: activeScopeBundleID)
    }

    private var selectedHoldAction: ButtonAction {
        store.holdAction(for: selected, bundleID: activeScopeBundleID)
    }

    private func tag(_ text: String, accent: Bool) -> some View {
        Text(text)
            .font(BossTheme.label(9.5, weight: .semibold))
            .foregroundStyle(accent ? BossTheme.accent : BossTheme.tertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(
                    accent
                        ? BossTheme.accent.opacity(0.10)
                        : BossTheme.controlFill
                )
            )
            .overlay(
                Capsule().stroke(
                    accent
                        ? BossTheme.accent.opacity(0.28)
                        : BossTheme.hairline,
                    lineWidth: 0.8
                )
            )
    }

    private var holdEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("长按 0.5 秒", "Hold 0.5s"))
                .font(BossTheme.label(9.5, weight: .semibold))
                .foregroundStyle(BossTheme.tertiary)
            holdMenuButton
        }
    }

    private var keyEditor: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("发送按键", "Sends key"))
                    .font(BossTheme.label(9.5, weight: .semibold))
                    .foregroundStyle(BossTheme.tertiary)
                keyMenuButton
            }
            Spacer(minLength: 8)
            Button {
                keyPickerOpen = false
                holdPickerOpen = false
                if isGlobalScope {
                    setAction(selected.defaultAction, hold: false)
                } else {
                    followGlobal()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(
                        isGlobalScope
                            ? L10n.t("恢复默认", "Restore default")
                            : L10n.t("跟随全局", "Follow global")
                    )
                    .font(BossTheme.label(10))
                }
                .foregroundStyle(canReset ? BossTheme.secondary : BossTheme.tertiary.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(BossTheme.controlFill)
                )
                .overlay(Capsule().stroke(BossTheme.hairline, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canReset)
            .help(
                isGlobalScope
                    ? L10n.t("恢复这个按键的默认动作", "Restore this button's default action")
                    : L10n.t("移除这个 App 的覆盖，跟随全局", "Remove this app override and follow global")
            )
        }
    }

    private var keyMenuButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) {
                keyPickerOpen.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                keycap(
                    shortLabel(for: selectedAction.key),
                    emphasized: selectedAction.key != nil
                )
                Text(selectedAction.label)
                    .font(BossTheme.label(12, weight: .medium))
                    .foregroundStyle(
                        selectedAction.key == nil
                            ? BossTheme.tertiary
                            : BossTheme.text
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 18)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(BossTheme.tertiary)
                    .rotationEffect(.degrees(keyPickerOpen ? 180 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(
                maxWidth: compact ? .infinity : 300,
                alignment: .leading
            )
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        keyPickerOpen || keyMenuHovered
                            ? BossTheme.controlFillHover
                            : BossTheme.controlFill
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        keyPickerOpen
                            ? BossTheme.accent.opacity(0.35)
                            : BossTheme.hairline,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                keyMenuHovered = hovering
            }
        }
        .popover(isPresented: $keyPickerOpen, arrowEdge: .top) {
            keyPicker(hold: false)
        }
    }

    private var holdMenuButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) {
                holdPickerOpen.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                keycap(
                    shortLabel(for: selectedHoldAction.key),
                    emphasized: selectedHoldAction.key != nil
                )
                Text(
                    selectedHoldAction == .none
                        ? L10n.t("不执行操作", "No action")
                        : selectedHoldAction.label
                )
                .font(BossTheme.label(12, weight: .medium))
                .foregroundStyle(
                    selectedHoldAction == .none
                        ? BossTheme.tertiary
                        : BossTheme.text
                )
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: 18)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(BossTheme.tertiary)
                    .rotationEffect(.degrees(holdPickerOpen ? 180 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(
                maxWidth: compact ? .infinity : 300,
                alignment: .leading
            )
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        holdPickerOpen || holdMenuHovered
                            ? BossTheme.controlFillHover
                            : BossTheme.controlFill
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        holdPickerOpen
                            ? BossTheme.accent.opacity(0.35)
                            : BossTheme.hairline,
                        lineWidth: 1
                    )
            )
            .contentShape(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                holdMenuHovered = hovering
            }
        }
        .popover(isPresented: $holdPickerOpen, arrowEdge: .top) {
            keyPicker(hold: true)
        }
    }

    private func keyPicker(hold: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(hold
                    ? L10n.t("长按动作", "Hold action")
                    : L10n.t("发送按键", "Sends key"))
                    .font(BossTheme.label(9.5, weight: .semibold))
                    .foregroundStyle(BossTheme.tertiary)
                Spacer()
                if isAppScope, !hold {
                    Button {
                        followGlobal()
                        withAnimation(.snappy(duration: 0.20)) {
                            keyPickerOpen = false
                        }
                    } label: {
                        Text(L10n.t("跟随全局", "Follow global"))
                            .font(BossTheme.label(9.5, weight: .medium))
                            .foregroundStyle(BossTheme.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(BossTheme.controlFill))
                            .overlay(Capsule().stroke(BossTheme.hairline, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .disabled(isFollowingGlobal)
                    .opacity(isFollowingGlobal ? 0.4 : 1)
                }
                Button {
                    choose(.none, hold: hold)
                } label: {
                    Text(L10n.t("不执行操作", "No action"))
                        .font(BossTheme.label(9.5, weight: .medium))
                        .foregroundStyle(BossTheme.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(BossTheme.controlFill))
                        .overlay(Capsule().stroke(BossTheme.hairline, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }

            searchField

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(KeyBinding.Group.allCases) { group in
                        let groupKeys = keys(in: group)
                        if !groupKeys.isEmpty {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(group.title)
                                    .font(BossTheme.label(
                                        9.5,
                                        weight: .semibold
                                    ))
                                    .foregroundStyle(BossTheme.tertiary)
                                LazyVGrid(
                                    columns: [GridItem(
                                        .adaptive(minimum: 150),
                                        spacing: 8
                                    )],
                                    spacing: 8
                                ) {
                                    ForEach(groupKeys) { key in
                                        keyChoice(key, hold: hold)
                                    }
                                }
                            }
                        }
                    }
                    if !hasMatches {
                        Text(L10n.t(
                            "没有匹配的操作",
                            "No matching actions"
                        ))
                        .font(BossTheme.label(10.5))
                        .foregroundStyle(BossTheme.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 380)
        }
        .padding(14)
        .frame(width: 560)
        .background(BossTheme.background)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(BossTheme.tertiary)
            TextField(
                L10n.t("搜索操作", "Search actions"),
                text: $keySearch
            )
            .textFieldStyle(.plain)
            .font(BossTheme.label(10.5))
            .foregroundStyle(BossTheme.text)
            if !keySearch.isEmpty {
                Button {
                    keySearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(BossTheme.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(BossTheme.controlFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BossTheme.hairline, lineWidth: 0.8)
        )
    }

    private func keys(in group: KeyBinding.Group) -> [KeyBinding] {
        let groupKeys = KeyBinding.allCases.filter { $0.group == group }
        guard !keySearch.isEmpty else { return groupKeys }
        return groupKeys.filter {
            $0.title.localizedCaseInsensitiveContains(keySearch)
        }
    }

    private var hasMatches: Bool {
        guard !keySearch.isEmpty else { return true }
        return KeyBinding.allCases.contains {
            $0.title.localizedCaseInsensitiveContains(keySearch)
        }
    }

    private func keyChoice(_ key: KeyBinding, hold: Bool) -> some View {
        let action = hold ? selectedHoldAction : selectedAction
        let current = action.key == key
        return Button {
            choose(.key(key), hold: hold)
        } label: {
            HStack(spacing: 6) {
                Text(key.title)
                    .font(BossTheme.label(10.5, weight: current ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if current {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                }
            }
            .foregroundStyle(
                current
                    ? BossTheme.accent
                    : BossTheme.text.opacity(0.86)
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        current
                            ? BossTheme.accent.opacity(0.12)
                            : BossTheme.controlFill
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        current
                            ? BossTheme.accent.opacity(0.28)
                            : BossTheme.hairline,
                        lineWidth: 0.8
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(key.title)
    }

    private func choose(_ action: ButtonAction, hold: Bool) {
        setAction(action, hold: hold)
        withAnimation(.snappy(duration: 0.20)) {
            keyPickerOpen = false
            holdPickerOpen = false
        }
    }

    @ViewBuilder
    private func keycap(_ label: String?, emphasized: Bool) -> some View {
        Text(label ?? "—")
            .font(BossTheme.mono(10.5, weight: .semibold))
            .foregroundStyle(emphasized ? BossTheme.text : BossTheme.tertiary)
            .frame(minWidth: 20)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(BossTheme.keycapFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(BossTheme.keycapStroke, lineWidth: 1)
            )
            .shadow(color: BossTheme.objectShadowSoft, radius: 1, x: 0, y: 1)
    }

    private var voiceEditor: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(BossTheme.accent.opacity(0.12))
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BossTheme.accentBright)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(voiceStatus)
                    .font(BossTheme.label(12, weight: .medium))
                    .foregroundStyle(BossTheme.text)
                    .lineLimit(1)
                Text(L10n.t(
                    "按住 Siri 键采集遥控器麦克风，松开后交给豆包。",
                    "Hold Siri to capture the remote mic, release to send to Doubao."
                ))
                .font(BossTheme.label(10.5))
                .foregroundStyle(BossTheme.tertiary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("Siri")
                .font(BossTheme.label(9, weight: .semibold))
                .foregroundStyle(BossTheme.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(BossTheme.accent.opacity(0.10)))
                .overlay(Capsule().stroke(BossTheme.accent.opacity(0.24), lineWidth: 0.8))
        }
    }

    // MARK: Control index

    private var controlIndex: some View {
        VStack(alignment: .leading, spacing: 0) {
            group(
                L10n.t("触控板", "Clickpad"),
                RemoteControl.directionalControls
            )
            group(
                L10n.t("滑动", "Swipe"),
                RemoteControl.swipeControls
            )
            .padding(.top, 18)
            group(
                L10n.t("外环", "Outer ring"),
                RemoteControl.ringControls
            )
            .padding(.top, 18)
            group(
                L10n.t("双击", "Double tap"),
                RemoteControl.tapControls
            )
            .padding(.top, 18)
            group(
                L10n.t("按钮", "Buttons"),
                RemoteControl.buttonControls
            )
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func group(
        _ title: String,
        _ controls: [RemoteControl]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            groupHeader(title, count: controls.count)
            ForEach(controls) { control in
                controlRow(control)
            }
        }
    }

    private func groupHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(BossTheme.label(10, weight: .semibold))
                .foregroundStyle(BossTheme.secondary)
            Text("\(count)")
                .font(BossTheme.mono(9, weight: .medium))
                .foregroundStyle(BossTheme.tertiary)
            Rectangle()
                .fill(BossTheme.hairline)
                .frame(height: 1)
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    private func controlRow(_ control: RemoteControl) -> some View {
        let isSelected = selected == control
        let isHovered = hoveredRow == control
        let isActive = active.contains(control)
        let isCustom = isAppScope
            ? store.isOverride(for: control, bundleID: activeScopeBundleID)
            : store.action(for: control) != control.defaultAction

        return Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
                selected = control
            }
        } label: {
            HStack(spacing: 9) {
                iconBadge(control, isSelected: isSelected)
                Text(control.title)
                    .font(BossTheme.label(13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(
                        isSelected
                            ? BossTheme.text
                            : BossTheme.text.opacity(0.82)
                    )
                    .lineLimit(1)
                    .layoutPriority(1)
                if !compact {
                    BossSeparator()
                    Text(control.officialFunction)
                        .font(BossTheme.label(10.5))
                        .foregroundStyle(BossTheme.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isActive {
                    Circle()
                        .fill(BossTheme.accent)
                        .frame(width: 5, height: 5)
                        .shadow(color: BossTheme.accent.opacity(0.8), radius: 4)
                }
                actionBadge(control, action: resolvedAction(for: control))
                    .overlay(alignment: .topTrailing) {
                        if isCustom && !control.isVoice {
                            Circle()
                                .fill(BossTheme.accent)
                                .frame(width: 4, height: 4)
                                .offset(x: 2, y: -2)
                        }
                    }
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(
                        isSelected
                            ? BossTheme.accent.opacity(0.82)
                            : BossTheme.tertiary.opacity(0.45)
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? BossTheme.accent.opacity(0.10)
                            : (isHovered ? BossTheme.controlFill : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected
                            ? BossTheme.accent.opacity(0.20)
                            : Color.clear,
                        lineWidth: 0.8
                    )
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(BossTheme.hairline.opacity(0.55))
                    .frame(height: 1)
                    .padding(.leading, 42)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                if hovering {
                    hoveredRow = control
                } else if hoveredRow == control {
                    hoveredRow = nil
                }
            }
        }
        .help(control.officialFunction)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func iconBadge(_ control: RemoteControl, isSelected: Bool) -> some View {
        Image(systemName: iconName(for: control))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isSelected ? BossTheme.accentBright : BossTheme.secondary)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .fill(
                        isSelected
                            ? BossTheme.accent.opacity(0.14)
                            : BossTheme.controlFill
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .stroke(BossTheme.controlFill, lineWidth: 0.8)
            )
    }

    private func iconName(for control: RemoteControl) -> String {
        switch control {
        case .power: return "power"
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        case .select: return "circle.circle"
        case .back: return "chevron.backward"
        case .tv: return "tv"
        case .playPause: return "playpause"
        case .volumeUp: return "speaker.plus"
        case .volumeDown: return "speaker.minus"
        case .mute: return "speaker.slash"
        case .siri: return "waveform"
        case .ringUp: return "arrow.turn.up.left"
        case .ringDown: return "arrow.turn.down.right"
        case .ringLeft: return "arrow.turn.up.right"
        case .ringRight: return "arrow.turn.down.left"
        case .swipeUp: return "arrow.up"
        case .swipeDown: return "arrow.down"
        case .swipeLeft: return "arrow.left"
        case .swipeRight: return "arrow.right"
        case .tapTwo: return "hand.tap"
        }
    }

    @ViewBuilder
    private func actionBadge(_ control: RemoteControl, action: ButtonAction) -> some View {
        if control.isVoice {
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.system(size: 8.5, weight: .semibold))
                Text(L10n.t("语音输入", "Voice"))
                    .font(BossTheme.label(9, weight: .medium))
            }
            .foregroundStyle(BossTheme.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(BossTheme.accent.opacity(0.09)))
            .overlay(Capsule().stroke(BossTheme.accent.opacity(0.18), lineWidth: 0.8))
        } else if let key = action.key {
            keycap(shortLabel(for: key), emphasized: true)
        } else {
            Text(L10n.t("未映射", "Unmapped"))
                .font(BossTheme.label(9, weight: .medium))
                .foregroundStyle(BossTheme.tertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(BossTheme.controlFill))
                .overlay(Capsule().stroke(BossTheme.hairline, lineWidth: 0.8))
        }
    }

    // MARK: Helpers

    private func setAction(_ action: ButtonAction, hold: Bool) {
        withAnimation(.snappy(duration: 0.22)) {
            if hold {
                if let bundleID = activeScopeBundleID {
                    store.setHoldAction(
                        action,
                        for: selected,
                        bundleID: bundleID
                    )
                } else {
                    store.setHoldAction(action, for: selected)
                }
                return
            }
            if let bundleID = activeScopeBundleID {
                store.setAction(action, for: selected, bundleID: bundleID)
            } else {
                store.setAction(action, for: selected)
            }
        }
    }

    private func followGlobal() {
        guard let bundleID = activeScopeBundleID else { return }
        withAnimation(.snappy(duration: 0.22)) {
            store.clearOverride(for: selected, bundleID: bundleID)
        }
    }

    private func shortLabel(for key: KeyBinding?) -> String? {
        guard let key else { return nil }
        switch key {
        case .returnKey: return "↩"
        case .escape: return "esc"
        case .space: return L10n.t("空格", "space")
        case .tab: return "⇥"
        case .delete: return "⌫"
        case .forwardDelete: return "⌦"
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .pageUp: return "⇞"
        case .pageDown: return "⇟"
        case .home: return "home"
        case .end: return "end"
        case .undo: return "⌘Z"
        case .redo: return "⇧⌘Z"
        case .cut: return "⌘X"
        case .copy: return "⌘C"
        case .paste: return "⌘V"
        case .selectAll: return "⌘A"
        case .find: return "⌘F"
        case .save: return "⌘S"
        case .newItem: return "⌘N"
        case .openItem: return "⌘O"
        case .closeWindow: return "⌘W"
        case .quitApp: return "⌘Q"
        case .hideApp: return "⌘H"
        case .minimize: return "⌘M"
        case .fullScreen: return "⌃⌘F"
        case .reload: return "⌘R"
        case .goBack: return "⌘["
        case .goForward: return "⌘]"
        case .newTab: return "⌘T"
        case .reopenTab: return "⇧⌘T"
        case .nextTab: return "⌃⇥"
        case .previousTab: return "⌃⇧⇥"
        case .addressBar: return "⌘L"
        case .appSwitcher: return "⌘⇥"
        case .lockScreen: return "⌃⌘Q"
        case .spotlight: return L10n.t("⌘空格", "⌘Space")
        case .missionControl: return "⌃↑"
        case .appExpose: return "⌃↓"
        case .showDesktop: return "F11"
        case .launchpad: return "F4"
        case .screenshot: return "⇧⌘4"
        case .mediaPlayPause: return L10n.t("播放", "Play")
        case .mediaNext: return L10n.t("下一首", "Next")
        case .mediaPrevious: return L10n.t("上一首", "Prev")
        case .volumeUp: return L10n.t("音量 +", "Vol +")
        case .volumeDown: return L10n.t("音量 −", "Vol −")
        case .mute: return L10n.t("静音", "Mute")
        case .brightnessUp: return L10n.t("亮度 +", "Bright +")
        case .brightnessDown: return L10n.t("亮度 −", "Bright −")
        }
    }
}
