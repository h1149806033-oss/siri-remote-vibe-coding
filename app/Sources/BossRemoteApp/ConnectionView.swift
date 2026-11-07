import AppKit
import BossRemoteCore
import BossRemoteUI
import SwiftUI

struct ConnectionView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var batteryInsights: BatteryInsightsStore
    private let preview: Bool
    @State private var copied = false
    @State private var rechecking = false

    init(model: AppModel, preview: Bool = false) {
        self._model = ObservedObject(wrappedValue: model)
        self._batteryInsights = ObservedObject(wrappedValue: model.batteryInsights)
        self.preview = preview
    }

    var body: some View {
        Group {
            if preview {
                GeometryReader { proxy in
                    pageBody(scrollable: false)
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height,
                            alignment: .topLeading
                        )
                        .clipped()
                }
            } else {
                pageBody(scrollable: true)
            }
        }
        .onAppear {
            if !preview {
                model.refreshDiagnostics()
            }
        }
    }

    private func pageBody(scrollable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, BossMetrics.pageHorizontal)
                .padding(.top, BossMetrics.pageTop)
                .padding(.bottom, 18)

            if scrollable {
                ScrollView(.vertical, showsIndicators: true) {
                    contentSections
                }
            } else {
                contentSections
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var contentSections: some View {
        VStack(alignment: .leading, spacing: BossMetrics.sectionSpacing) {
            remoteSection
            sectionDivider
            permissionsSection
            sectionDivider
            pipelineSection
            sectionDivider
            BatteryInsightsCard(store: batteryInsights)
            sectionDivider
            diagnosticsSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, BossMetrics.pageHorizontal)
        .padding(.bottom, BossMetrics.pageBottom)
    }

    private var sectionDivider: some View {
        BossRule()
    }

    private var header: some View {
        BossPageHeader(
            title: L10n.t("连接", "Connection"),
            subtitle: L10n.t(
                "遥控器、触控、语音、电池与系统权限的实时状态",
                "Live status for remote, touch, voice, battery and permissions"
            )
        ) {
            HStack(spacing: 10) {
                statusPill(
                    dot: model.connected ? BossTheme.success : BossTheme.tertiary,
                    text: model.connected
                        ? L10n.t("已连接", "Connected")
                        : L10n.t("等待连接", "Waiting")
                )
                BossPillButton(
                    isEnabled: !rechecking,
                    action: {
                        rechecking = true
                        model.refreshDiagnostics()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            rechecking = false
                        }
                    },
                    content: {
                        Label(
                            rechecking
                                ? L10n.t("检测中", "Checking")
                                : L10n.t("重新检测", "Recheck"),
                            systemImage: "arrow.clockwise"
                        )
                        .font(BossTheme.label(9.5, weight: .medium))
                        .foregroundStyle(BossTheme.secondary)
                    }
                )
            }
        }
    }

    private var remoteSection: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.145, green: 0.158, blue: 0.184),
                                Color(red: 0.062, green: 0.070, blue: 0.086),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(BossTheme.hairline, lineWidth: 1)
                    )
                RemoteThumbnail(size: 44)
                    .padding(.top, 2)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.connected
                    ? (model.deviceName ?? "Siri Remote")
                    : "Siri Remote")
                    .font(BossTheme.display(16, weight: .semibold))
                    .foregroundStyle(BossTheme.text)
                HStack(spacing: 8) {
                    Text("A2854")
                    Text("USB-C")
                    Text(L10n.t(
                        "Siri Remote（第 3 代）",
                        "Siri Remote (3rd generation)"
                    ))
                }
                .font(BossTheme.label(10))
                .foregroundStyle(BossTheme.tertiary)
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.connected ? BossTheme.success : BossTheme.tertiary)
                        .frame(width: 5, height: 5)
                    Text(model.status)
                        .font(BossTheme.label(10, weight: .medium))
                        .foregroundStyle(BossTheme.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 10)
            if model.connected {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 3) {
                        Text(model.battery.map { "\($0)%" } ?? "—")
                            .font(BossTheme.mono(18, weight: .semibold))
                            .foregroundStyle(remoteBatteryColor)
                        if model.isCharging, model.battery != nil {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(BossTheme.success)
                        }
                    }
                    Text(remoteBatteryCaption)
                        .font(BossTheme.label(9.5))
                        .foregroundStyle(
                            model.isCharging
                                ? BossTheme.success
                                : BossTheme.tertiary
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var remoteBatteryColor: Color {
        guard let battery = model.battery else { return BossTheme.tertiary }
        if battery <= 20 { return BossTheme.danger }
        return model.isCharging ? BossTheme.success : BossTheme.text
    }

    private var remoteBatteryCaption: String {
        if model.isCharging { return L10n.t("充电中", "Charging") }
        if model.battery == nil {
            return L10n.t("电量不可用", "Battery unavailable")
        }
        return batteryInsights.batteryAvailable
            ? L10n.t("电量", "Battery")
            : L10n.t("上次电量", "Last known")
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            BossSectionHeader(
                icon: "checkmark.shield",
                title: L10n.t("权限", "Permissions")
            )
            .padding(.bottom, 6)
            permissionRow(
                title: L10n.t("辅助功能", "Accessibility"),
                granted: model.hasAccessibility,
                open: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                grant: model.requestAccessibility
            )
            hairline
            permissionRow(
                title: L10n.t("输入监控", "Input Monitoring"),
                granted: model.hasInputMonitoring,
                open: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
                grant: model.requestInputMonitoring
            )
            hairline
            permissionRow(
                title: L10n.t("蓝牙", "Bluetooth"),
                status: bluetoothStatus,
                granted: model.bluetoothState == .poweredOn,
                open: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
            )
            HStack {
                Spacer()
                BossPillButton(action: {
                    open("x-apple.systempreferences:com.apple.BluetoothSettings")
                }, content: {
                    Label(
                        L10n.t("打开蓝牙设置", "Open Bluetooth"),
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                    .font(BossTheme.label(9.5, weight: .medium))
                    .foregroundStyle(BossTheme.secondary)
                })
            }
            .padding(.top, 10)
        }
    }

    private func interfaceCountText(_ count: Int) -> String {
        L10n.t(
            "\(count) 个接口",
            count == 1 ? "1 interface" : "\(count) interfaces"
        )
    }

    private func deviceCountText(_ count: Int) -> String {
        L10n.t(
            "\(count) 个设备",
            count == 1 ? "1 device" : "\(count) devices"
        )
    }

    private var bluetoothStatus: String {
        switch model.bluetoothState {
        case .poweredOn: return L10n.t("已开启", "On")
        case .poweredOff: return L10n.t("已关闭", "Off")
        case .unauthorized: return L10n.t("未授权", "Denied")
        case .unsupported: return L10n.t("不可用", "Unavailable")
        case .resetting: return L10n.t("重置中", "Resetting")
        case .unknown: return L10n.t("检测中", "Checking")
        }
    }

    private var pipelineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            BossSectionHeader(
                icon: "point.3.connected.trianglepath.dotted",
                title: L10n.t("链路", "Pipeline"),
                detail: L10n.t(
                    "HID → 触控 → HCI → 虚拟麦克风",
                    "HID → touch → HCI → virtual mic"
                )
            )
            .padding(.bottom, 6)
            pipelineRow(
                icon: "appletvremote.gen4",
                title: L10n.t("HID 遥控器", "HID remote"),
                detail: model.hidDiagnostics.isConnected
                    ? interfaceCountText(model.hidDiagnostics.usagePages.count)
                    : L10n.t("等待遥控器", "Waiting for remote"),
                ok: model.hidDiagnostics.isConnected
            )
            hairline
            pipelineRow(
                icon: "hand.point.up.left",
                title: L10n.t("触控板", "Touchpad"),
                detail: model.touchDiagnostics.isRunning
                    ? deviceCountText(model.touchDiagnostics.deviceCount)
                    : L10n.t("未启动", "Not running"),
                ok: model.touchDiagnostics.isRunning
            )
            hairline
            pipelineRow(
                icon: "lock.shield",
                title: L10n.t("HCI 语音通道", "HCI voice"),
                detail: model.voiceDiagnostics.prepared
                    ? L10n.t("特权服务已就绪", "Privileged service ready")
                    : L10n.t("尚未就绪", "Not ready"),
                ok: model.voiceDiagnostics.prepared
            )
            hairline
            pipelineRow(
                icon: "waveform.badge.magnifyingglass",
                title: L10n.t("蓝牙包日志", "Packet logger"),
                detail: model.voiceDiagnostics.loggerState,
                ok: model.voiceDiagnostics.loggerState == L10n.t("已授权", "Authorized")
            )
            hairline
            pipelineRow(
                icon: "mic",
                title: L10n.t("虚拟麦克风", "Virtual mic"),
                detail: model.voiceDiagnostics.virtualMicRunning
                    ? L10n.t(
                        "MiRemoteV，\(model.voiceDiagnostics.decodedFrames) 帧",
                        "MiRemoteV, \(model.voiceDiagnostics.decodedFrames) frames"
                    )
                    : L10n.t("未启动", "Not running"),
                ok: model.voiceDiagnostics.virtualMicRunning
            )
            HStack {
                if model.voiceDiagnostics.capturing {
                    Capsule()
                        .fill(BossTheme.accent)
                        .frame(width: 5, height: 5)
                        .shadow(color: BossTheme.accent.opacity(0.7), radius: 4)
                    Text(L10n.t("正在采集", "Capturing"))
                        .font(BossTheme.label(9, weight: .medium))
                        .foregroundStyle(BossTheme.accent)
                }
                Spacer()
                BossPillButton(
                    isEnabled: !model.isRestartingVoice,
                    action: {
                        model.restartVoice()
                    },
                    content: {
                        Text(model.isRestartingVoice
                            ? L10n.t("重启中", "Restarting")
                            : L10n.t("重启语音服务", "Restart voice"))
                            .font(BossTheme.label(9.5, weight: .medium))
                            .foregroundStyle(BossTheme.secondary)
                    }
                )
            }
            .padding(.top, 10)
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            BossSectionHeader(
                icon: "doc.text.magnifyingglass",
                title: L10n.t("诊断日志", "Diagnostics")
            ) {
                HStack(spacing: 8) {
                    BossPillButton(action: {
                        if copyDiagnostics() {
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copied = false
                            }
                        } else {
                            model.noteDiagnostic("copy diagnostics failed")
                        }
                    }, content: {
                        HStack(spacing: 4) {
                            if copied {
                                Image(systemName: "checkmark")
                            }
                            Text(copied
                                ? L10n.t("已复制", "Copied")
                                : L10n.t("复制", "Copy"))
                        }
                        .font(BossTheme.label(9.5, weight: .medium))
                        .foregroundStyle(
                            copied ? BossTheme.success : BossTheme.secondary
                        )
                    })
                    BossPillButton(
                        isEnabled: logFileExists,
                        action: {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [model.logFileURL]
                            )
                        },
                        content: {
                            Image(systemName: "folder")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(BossTheme.secondary)
                        }
                    )
                    .accessibilityLabel(L10n.t(
                        "在 Finder 中显示诊断日志",
                        "Show diagnostics log in Finder"
                    ))
                    .help(logFileExists
                        ? L10n.t("在 Finder 中显示诊断日志", "Show diagnostics log in Finder")
                        : L10n.t("日志文件尚未生成", "The log file is not available yet"))
                }
            }
            .padding(.bottom, 10)

            let lines = Array(model.logLines.suffix(14))
            if lines.isEmpty {
                Text(L10n.t("暂无日志", "No log entries"))
                    .font(BossTheme.label(10))
                    .foregroundStyle(BossTheme.tertiary)
                    .padding(.vertical, 12)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(BossTheme.mono(9, weight: .regular))
                            .foregroundStyle(
                                line.contains("失败")
                                    || line.contains("failed")
                                    || line.contains("不可用")
                                    || line.lowercased().contains("unavailable")
                                    ? BossTheme.danger.opacity(0.8)
                                    : BossTheme.tertiary
                            )
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(line)
                    }
                }
            }
        }
    }

    private func statusPill(dot: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
                .shadow(color: dot.opacity(0.6), radius: 4)
            Text(text)
                .font(BossTheme.label(10.5, weight: .medium))
                .foregroundStyle(BossTheme.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Capsule().fill(BossTheme.surface.opacity(0.8)))
        .overlay(Capsule().stroke(BossTheme.hairline, lineWidth: 1))
    }

    private func pipelineRow(
        icon: String,
        title: String,
        detail: String,
        ok: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ok ? BossTheme.accent : BossTheme.tertiary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BossTheme.label(11, weight: .medium))
                    .foregroundStyle(BossTheme.text)
                Text(detail)
                    .font(BossTheme.label(9.5))
                    .foregroundStyle(BossTheme.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Circle()
                .fill(ok ? BossTheme.success : BossTheme.tertiary)
                .frame(width: 5, height: 5)
                .shadow(color: ok ? BossTheme.success.opacity(0.6) : .clear, radius: 3)
        }
        .padding(.vertical, 8)
    }

    private func permissionRow(
        title: String,
        status: String? = nil,
        granted: Bool,
        open url: String,
        grant: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(granted ? BossTheme.success : BossTheme.tertiary)
                .frame(width: 5, height: 5)
                .shadow(
                    color: granted
                        ? BossTheme.success.opacity(0.6)
                        : .clear,
                    radius: 3
                )
            Text(title)
                .font(BossTheme.label(11, weight: .medium))
                .foregroundStyle(BossTheme.text)
            Spacer(minLength: 4)
            Text(status ?? (granted
                ? L10n.t("已授权", "Allowed")
                : L10n.t("未授权", "Denied")))
                .font(BossTheme.label(9.5))
                .foregroundStyle(
                    granted ? BossTheme.success : BossTheme.tertiary
                )
            if !granted, let grant {
                smallButton(L10n.t("授权", "Grant"), action: grant)
            }
            smallButton(L10n.t("打开设置", "Open")) {
                open(url)
            }
        }
        .padding(.vertical, 8)
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        BossPillButton(action: action) {
            Text(title)
                .font(BossTheme.label(9.5, weight: .medium))
                .foregroundStyle(BossTheme.secondary)
        }
    }

    private var hairline: some View {
        BossRule()
    }

    private var logFileExists: Bool {
        FileManager.default.fileExists(atPath: model.logFileURL.path)
    }

    @discardableResult
    private func open(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else {
            model.noteDiagnostic("open settings failed: invalid url")
            return false
        }
        let opened = NSWorkspace.shared.open(url)
        if !opened {
            model.noteDiagnostic("open settings failed: \(urlString)")
        }
        return opened
    }

    @discardableResult
    private func copyDiagnostics() -> Bool {
        let text = """
        Boss Remote \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
        remote: \(model.deviceName ?? "-") connected=\(model.connected) battery=\(model.battery.map(String.init) ?? "-") charging=\(model.isCharging) available=\(batteryInsights.batteryAvailable) bluetooth=\(model.bluetoothState)
        hid: connected=\(model.hidDiagnostics.isConnected) pages=\(model.hidDiagnostics.usagePages.map { String(format: "0x%04x", $0) }.joined(separator: ","))
        touch: running=\(model.touchDiagnostics.isRunning) devices=\(model.touchDiagnostics.deviceCount)
        voice: prepared=\(model.voiceDiagnostics.prepared) logger=\(model.voiceDiagnostics.loggerState) mic=\(model.voiceDiagnostics.virtualMicRunning) frames=\(model.voiceDiagnostics.decodedFrames)
        permissions: accessibility=\(model.hasAccessibility) input=\(model.hasInputMonitoring)
        log:
        \(model.logLines.suffix(20).joined(separator: "\n"))
        """
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }
}

private enum BatteryChartRange: String, CaseIterable, Identifiable {
    case day
    case week

    var id: String { rawValue }
    var shortTitle: String { self == .day ? "24h" : "7d" }
    var label: String {
        self == .day
            ? L10n.t("过去 24 小时", "Last 24 hours")
            : L10n.t("过去 7 天", "Last 7 days")
    }
    var interval: TimeInterval {
        self == .day ? 24 * 3600 : 7 * 24 * 3600
    }
}

private enum BatteryDisplayState {
    case charging
    case externalPower
    case active
    case standby
    case disconnected
    case unavailable

    var title: String {
        switch self {
        case .charging: return L10n.t("充电中", "Charging")
        case .externalPower: return L10n.t("外接电源", "External power")
        case .active: return L10n.t("使用中", "In use")
        case .standby: return L10n.t("待机", "Standby")
        case .disconnected: return L10n.t("未连接", "Disconnected")
        case .unavailable: return L10n.t("电量不可用", "Battery unavailable")
        }
    }

    var color: Color {
        switch self {
        case .charging: return BossTheme.success
        case .externalPower: return BossTheme.success.opacity(0.8)
        case .active: return BossTheme.accent
        case .standby: return BossTheme.secondary
        case .disconnected: return BossTheme.tertiary
        case .unavailable: return BossTheme.tertiary
        }
    }
}

private struct BatteryInsightsCard: View {
    @ObservedObject var store: BatteryInsightsStore
    @AppStorage("bossRemote.batteryRange") private var rangeRaw =
        BatteryChartRange.day.rawValue

    private var range: BatteryChartRange {
        BatteryChartRange(rawValue: rangeRaw) ?? .day
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            card(now: context.date)
        }
    }

    private func card(now: Date) -> some View {
        let bounds = chartBounds(now: now)
        return VStack(alignment: .leading, spacing: 10) {
            header(now: now)
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(levelText)
                            .font(BossTheme.display(30, weight: .bold))
                            .foregroundStyle(levelColor)
                        Text(store.connected && store.batteryAvailable
                            ? L10n.t("当前电量", "Current")
                            : L10n.t("上次电量", "Last known"))
                            .font(BossTheme.label(10))
                            .foregroundStyle(BossTheme.tertiary)
                        Spacer()
                    }
                    Text(sessionLine(now: now))
                        .font(BossTheme.label(10.5))
                        .foregroundStyle(BossTheme.tertiary)
                        .lineLimit(1)
                    BatterySparkline(
                        samples: chartSamples(now: now),
                        start: now.addingTimeInterval(-range.interval),
                        end: now,
                        lower: bounds.lower,
                        upper: bounds.upper,
                        current: store.currentLevel,
                        isCharging: store.isCharging
                    )
                    .frame(height: 56)
                    HStack(spacing: 8) {
                        Text(
                            chartSamples(now: now).count >= 2
                                ? range.label
                                : L10n.t(
                                    "记录中，曲线会随时间积累",
                                    "Recording; the curve builds over time"
                                )
                        )
                        .font(BossTheme.label(9.5))
                        .foregroundStyle(BossTheme.tertiary)
                        .lineLimit(1)
                        Spacer()
                        Text(lastChargeLine(now: now))
                            .font(BossTheme.label(9.5))
                            .foregroundStyle(BossTheme.tertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                metrics(now: now)
                    .frame(width: 290)
            }
        }
    }

    private func header(now: Date) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "battery.75percent")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BossTheme.accent)
                .frame(width: 14)
            Text(L10n.t("电池", "Battery"))
                .font(BossTheme.display(14.5, weight: .semibold))
                .foregroundStyle(BossTheme.text)
            statePill(now: now)
            Text(updateText(now: now))
                .font(BossTheme.label(9.5))
                .foregroundStyle(BossTheme.tertiary)
                .lineLimit(1)
            Spacer()
            HStack(spacing: 3) {
                ForEach(BatteryChartRange.allCases) { item in
                    BatteryRangeButton(
                        item: item,
                        selected: range == item
                    ) {
                        withAnimation(.snappy(duration: 0.18)) {
                            rangeRaw = item.rawValue
                        }
                    }
                }
            }
            .padding(2)
            .background(Capsule().fill(BossTheme.controlFill))
        }
    }

    private func statePill(now: Date) -> some View {
        let state = displayState(now: now)
        return HStack(spacing: 5) {
            Circle()
                .fill(state.color)
                .frame(width: 5, height: 5)
                .shadow(color: state.color.opacity(0.55), radius: 3)
            Text(state.title)
                .font(BossTheme.label(9.5, weight: .medium))
                .foregroundStyle(state.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(state.color.opacity(0.08)))
    }

    private func metrics(now: Date) -> some View {
        let duration = sessionDuration(now: now)
        let rates = consumptionRates(now: now)
        let items: [(String, String)]
        if !store.batteryAvailable {
            items = [
                (L10n.t("本次连接", "Session"), formatDuration(duration)),
                (L10n.t("本次耗电", "Session use"), "—"),
                (L10n.t("今日耗电", "Today's use"), "—"),
                (L10n.t("今日充电", "Charged today"), "—"),
                (L10n.t("待机耗电", "Standby drain"), "—"),
                (L10n.t("使用耗电", "Active drain"), "—"),
            ]
        } else if store.isCharging {
            let charge = store.activeChargeSession
            let chargeDuration = charge.map {
                max(0, now.timeIntervalSince($0.startedAt))
            } ?? 0
            let gained = charge.flatMap { session -> Int? in
                guard let start = session.startLevel,
                      let end = session.endLevel
                else { return nil }
                return end - start
            }
            items = [
                (L10n.t("本次充电", "Charging for"), formatChargeDuration(chargeDuration)),
                (L10n.t("已充入", "Charged"), gainedText(gained)),
                (L10n.t("充电速度", "Charge rate"), rateText(store.chargeRate(now: now), sign: true)),
                (L10n.t("预计充满", "To full"), etaText(store.chargeTimeRemaining(now: now))),
                (L10n.t("今日充电", "Charged today"), chargeTodayText(now: now)),
                (L10n.t("本次连接", "Session"), formatDuration(duration)),
            ]
        } else {
            items = [
                (L10n.t("本次连接", "Session"), formatDuration(duration)),
                (L10n.t("本次耗电", "Session use"), sessionDrainText),
                (L10n.t("今日耗电", "Today's use"), "\(todayDrain(now: now))%"),
                (L10n.t("今日充电", "Charged today"), chargeTodayText(now: now)),
                (L10n.t("待机耗电", "Standby drain"), rateText(rates.standby)),
                (L10n.t("使用耗电", "Active drain"), rateText(rates.active)),
            ]
        }
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)],
            spacing: 12
        ) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.0)
                        .font(BossTheme.label(9.5))
                        .foregroundStyle(BossTheme.tertiary)
                    Text(item.1)
                        .font(BossTheme.mono(11.5, weight: .medium))
                        .foregroundStyle(BossTheme.text.opacity(0.9))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .help(L10n.t(
            "充电速度按电量变化估算；遥控器只上报电量，不上报瓦数",
            "Charge rate is estimated from level changes; the remote reports level only, not wattage"
        ))
    }

    private var levelText: String {
        store.currentLevel.map { "\($0)%" } ?? "—"
    }

    private var levelColor: Color {
        if let level = store.currentLevel, level <= 20 {
            return BossTheme.danger
        }
        return BossTheme.text
    }

    private var currentSession: BatterySession? {
        store.sessions.first(where: { $0.endedAt == nil })
            ?? store.sessions.first
    }

    private func sessionLine(now: Date) -> String {
        if store.connected, !store.batteryAvailable {
            return L10n.t(
                "蓝牙电量暂不可用，显示上次记录",
                "Battery unavailable; showing last known"
            )
        }
        if store.isCharging, let charge = store.activeChargeSession {
            let duration = formatChargeDuration(
                max(0, now.timeIntervalSince(charge.startedAt))
            )
            let start = charge.startLevel.map { "\($0)%" } ?? "—"
            let end = store.currentLevel.map { "\($0)%" } ?? "—"
            return L10n.t(
                "本次充电 \(duration)，\(start) → \(end)",
                "Charging \(duration), \(start) → \(end)"
            )
        }
        guard let session = currentSession else {
            return L10n.t("等待遥控器连接", "Waiting for remote")
        }
        let duration = formatDuration(sessionDuration(now: now))
        let prefix = store.connected
            ? L10n.t("本次连接", "This session")
            : L10n.t("上次连接", "Last session")
        let start = session.startLevel.map { "\($0)%" } ?? "—"
        let end = store.currentLevel.map { "\($0)%" } ?? "—"
        return "\(prefix) \(duration)，\(start) → \(end)"
    }

    private var sessionDrainText: String {
        guard let session = currentSession,
              let start = session.startLevel,
              let current = store.currentLevel
        else { return "—" }
        let delta = start - current
        if delta > 0 { return "\(delta)%" }
        if delta == 0 { return "0%" }
        return "—"
    }

    private func sessionDuration(now: Date) -> TimeInterval {
        guard let session = currentSession else { return 0 }
        return max(0, (session.endedAt ?? now).timeIntervalSince(session.startedAt))
    }

    private func displayState(now: Date) -> BatteryDisplayState {
        guard store.connected else { return .disconnected }
        guard store.batteryAvailable else { return .unavailable }
        if store.isCharging {
            return .charging
        }
        if store.chargeState == .externalPower,
           store.hasFreshChargeState(now: now) {
            return .externalPower
        }
        if let activity = store.lastActivityAt,
           now.timeIntervalSince(activity) < 90 {
            return .active
        }
        return .standby
    }

    private func chartSamples(now: Date) -> [BatterySample] {
        let start = now.addingTimeInterval(-range.interval)
        return store.samples.filter { $0.date >= start && $0.date <= now }
    }

    private func chartBounds(now: Date) -> (lower: Int, upper: Int) {
        let levels = chartSamples(now: now).map(\.level)
        let minLevel = levels.min() ?? store.currentLevel ?? 0
        let maxLevel = levels.max() ?? store.currentLevel ?? 100
        var lower = max(0, minLevel - 6)
        var upper = min(100, maxLevel + 6)
        if upper - lower < 10 {
            let mid = (upper + lower) / 2
            lower = max(0, mid - 5)
            upper = min(100, mid + 5)
        }
        return (lower, upper)
    }

    private func todayDrain(now: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        var previous = store.samples.last(where: { $0.date < start })
        var total = 0
        for sample in store.samples where sample.date >= start && sample.date <= now {
            if let last = previous, last.connected, sample.connected,
               sample.level < last.level {
                total += last.level - sample.level
            }
            previous = sample
        }
        return total
    }

    private func chargeMinutesToday(now: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        var previous: BatterySample?
        var seconds: TimeInterval = 0
        for sample in store.samples where sample.date >= start && sample.date <= now {
            if let last = previous, last.connected, sample.connected {
                let interval = sample.date.timeIntervalSince(last.date)
                if interval > 0, interval <= 1800,
                   sample.chargeState == .charging || sample.level > last.level {
                    seconds += interval
                }
            }
            previous = sample
        }
        if store.isCharging,
           let last = store.samples.last,
           last.date >= start,
           last.date <= now {
            seconds += max(0, now.timeIntervalSince(last.date))
        }
        return Int((seconds / 60).rounded())
    }

    private func chargeTodayText(now: Date) -> String {
        let minutes = chargeMinutesToday(now: now)
        if minutes <= 0 { return "—" }
        return L10n.t("\(minutes) 分钟", "\(minutes) min")
    }

    private func consumptionRates(now: Date) -> (standby: Double?, active: Double?) {
        let start = now.addingTimeInterval(-24 * 3600)
        let samples = store.samples.filter { $0.date >= start && $0.date <= now }
        guard samples.count > 1 else { return (nil, nil) }
        var idleDrop = 0
        var idleSeconds: TimeInterval = 0
        var activeDrop = 0
        var activeSeconds: TimeInterval = 0
        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let sample = samples[index]
            guard previous.connected, sample.connected else { continue }
            let interval = sample.date.timeIntervalSince(previous.date)
            guard interval > 0, interval <= 1800 else { continue }
            let drop = max(0, previous.level - sample.level)
            if sample.active {
                activeDrop += drop
                activeSeconds += interval
            } else {
                idleDrop += drop
                idleSeconds += interval
            }
        }
        let standby = idleSeconds >= 1800 && idleDrop >= 1
            ? Double(idleDrop) / (idleSeconds / 3600)
            : nil
        let active = activeSeconds >= 1800 && activeDrop >= 1
            ? Double(activeDrop) / (activeSeconds / 3600)
            : nil
        return (standby, active)
    }

    private func rateText(_ rate: Double?, sign: Bool = false) -> String {
        guard let rate else {
            return L10n.t("积累中", "Collecting")
        }
        return String(format: sign ? "+%.1f%%/h" : "%.1f%%/h", rate)
    }

    private func gainedText(_ gained: Int?) -> String {
        guard let gained else { return "—" }
        if gained > 0 { return "+\(gained)%" }
        if gained == 0 { return "0%" }
        return "—"
    }

    private func etaText(_ remaining: TimeInterval?) -> String {
        if let level = store.currentLevel, level >= 100 {
            return L10n.t("已充满", "Full")
        }
        guard let remaining, remaining.isFinite, remaining > 0 else {
            return L10n.t("积累中", "Collecting")
        }
        let minutes = Int((remaining / 60).rounded(.up))
        if minutes <= 1 {
            return L10n.t("不到 1 分钟", "< 1 min")
        }
        if minutes < 60 {
            return L10n.t("约 \(minutes) 分钟", "~\(minutes) min")
        }
        let hours = minutes / 60
        let rest = minutes % 60
        if rest == 0 {
            return L10n.t("约 \(hours) 小时", "~\(hours) h")
        }
        return L10n.t(
            "约 \(hours) 小时 \(rest) 分",
            "~\(hours) h \(rest) m"
        )
    }

    private func lastChargeLine(now: Date) -> String {
        if store.isCharging {
            if let level = store.currentLevel, level >= 100 {
                return L10n.t("已充满，100%", "Full, 100%")
            }
            if let remaining = store.chargeTimeRemaining(now: now) {
                return L10n.t(
                    "正在充电，约 \(formatDuration(remaining)) 后充满",
                    "Charging, full in \(formatDuration(remaining))"
                )
            }
            return L10n.t("正在充电，\(levelText)", "Charging, \(levelText)")
        }
        let samples = store.samples
        guard samples.count > 1 else {
            return L10n.t("还没有充电记录", "No charge records yet")
        }
        var end = samples.count - 1
        while end > 0 {
            let previous = samples[end - 1]
            let sample = samples[end]
            if sample.level > previous.level || sample.chargeState == .charging {
                break
            }
            end -= 1
        }
        guard end > 0 else {
            return L10n.t("还没有充电记录", "No charge records yet")
        }
        var start = end - 1
        while start > 0 {
            let previous = samples[start - 1]
            let sample = samples[start]
            if sample.level > previous.level || sample.chargeState == .charging {
                start -= 1
            } else {
                break
            }
        }
        let first = samples[start]
        let last = samples[end]
        let duration = formatDuration(
            max(0, last.date.timeIntervalSince(first.date))
        )
        return L10n.t(
            "上次充电 \(first.level)% → \(last.level)%，\(duration)",
            "Last charge \(first.level)% → \(last.level)%, \(duration)"
        )
    }

    private func updateText(now: Date) -> String {
        guard let reference = store.lastLevelReadAt
                ?? store.samples.last?.date
        else {
            return store.connected
                ? L10n.t("等待读取电量", "Waiting for battery")
                : L10n.t("电量不可用", "Battery unavailable")
        }
        let seconds = max(0, Int(now.timeIntervalSince(reference)))
        let age: String
        if seconds < 5 {
            age = L10n.t("刚刚", "just now")
        } else if seconds < 60 {
            age = L10n.t("\(seconds) 秒前", "\(seconds)s ago")
        } else if seconds < 3600 {
            age = L10n.t("\(seconds / 60) 分钟前", "\(seconds / 60)m ago")
        } else {
            age = L10n.t("\(seconds / 3600) 小时前", "\(seconds / 3600)h ago")
        }
        if store.batteryAvailable {
            return L10n.t("\(age)读取", "Read \(age)")
        }
        return L10n.t("电量不可用，上次 \(age)", "Unavailable, last \(age)")
    }

    private func formatChargeDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(max(0, duration.rounded()))
        if seconds < 60 {
            return L10n.t("\(seconds) 秒", "\(seconds)s")
        }
        guard seconds < 3600 else {
            return formatDuration(duration)
        }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return L10n.t(
            "\(minutes) 分 \(String(format: "%02d", remainder)) 秒",
            "\(minutes)m \(String(format: "%02d", remainder))s"
        )
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(max(0, duration.rounded()))
        if seconds < 60 {
            return L10n.t("\(seconds) 秒", "\(seconds)s")
        }
        if seconds < 3600 {
            return L10n.t("\(seconds / 60) 分钟", "\(seconds / 60)m")
        }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return L10n.t(
            "\(hours) 小时 \(String(format: "%02d", minutes)) 分",
            "\(hours)h \(String(format: "%02d", minutes))m"
        )
    }
}

private struct BatteryRangeButton: View {
    let item: BatteryChartRange
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Text(item.shortTitle)
                .font(BossTheme.mono(9.5, weight: .semibold))
                .foregroundStyle(
                    selected ? BossTheme.accent : BossTheme.tertiary
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(minHeight: 24)
                .background(
                    Capsule().fill(
                        selected
                            ? BossTheme.accent.opacity(0.11)
                            : (hovering ? BossTheme.rowHover : Color.clear)
                    )
                )
                .overlay(
                    Capsule().stroke(
                        BossTheme.accent.opacity(focused ? 0.75 : 0),
                        lineWidth: 1
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(BossPressButtonStyle())
        .onHover { hovering = $0 }
        .focused($focused)
        .focusable()
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(item.label)
    }
}

private struct BatterySparkline: View {
    let samples: [BatterySample]
    let start: Date
    let end: Date
    let lower: Int
    let upper: Int
    let current: Int?
    let isCharging: Bool

    var body: some View {
        GeometryReader { proxy in
            let labelWidth: CGFloat = 18
            let rect = CGRect(
                x: labelWidth,
                y: 3,
                width: max(1, proxy.size.width - labelWidth - 2),
                height: max(1, proxy.size.height - 6)
            )
            ZStack(alignment: .topLeading) {
                ForEach([0.25, 0.5, 0.75], id: \.self) { fraction in
                    Path { path in
                        let y = rect.minY + rect.height * fraction
                        path.move(to: CGPoint(x: rect.minX, y: y))
                        path.addLine(to: CGPoint(x: rect.maxX, y: y))
                    }
                    .stroke(
                        BossTheme.hairline,
                        style: StrokeStyle(
                            lineWidth: 0.6,
                            dash: fraction == 0.5 ? [] : [2, 4]
                        )
                    )
                }

                Text("\(upper)%")
                    .font(BossTheme.mono(7.5, weight: .medium))
                    .foregroundStyle(BossTheme.tertiary.opacity(0.75))
                    .position(x: labelWidth - 5, y: rect.minY + 3)
                Text("\(lower)%")
                    .font(BossTheme.mono(7.5, weight: .medium))
                    .foregroundStyle(BossTheme.tertiary.opacity(0.75))
                    .position(x: labelWidth - 5, y: rect.maxY - 3)

                chartPath(in: rect)
                latestPoint(in: rect)
            }
        }
    }

    private struct SamplePoint: Identifiable {
        let sample: BatterySample
        let point: CGPoint

        var id: UUID { sample.id }
    }

    @ViewBuilder
    private func chartPath(in rect: CGRect) -> some View {
        let points = samples.compactMap { sample -> SamplePoint? in
            guard sample.date >= start, sample.date <= end else { return nil }
            return SamplePoint(
                sample: sample,
                point: point(for: sample, in: rect)
            )
        }
        if points.isEmpty {
            Path { path in
                let y = yPosition(for: current ?? lower, in: rect)
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            .stroke(
                BossTheme.accent.opacity(0.35),
                style: StrokeStyle(lineWidth: 1, dash: [3, 4])
            )
        } else {
            let chargePoints = points.enumerated().compactMap {
                index, item -> SamplePoint? in
                let previous = index > 0 ? points[index - 1] : nil
                let rising = previous.map {
                    item.sample.level > $0.sample.level
                } ?? false
                return item.sample.chargeState == .charging || rising
                    ? item
                    : nil
            }

            Path { path in
                var segmentOpen = false
                for item in points {
                    if item.sample.connected {
                        if segmentOpen {
                            path.addLine(to: item.point)
                        } else {
                            path.move(to: item.point)
                        }
                        segmentOpen = true
                    } else {
                        segmentOpen = false
                    }
                }
            }
            .stroke(
                BossTheme.accent.opacity(0.82),
                style: StrokeStyle(
                    lineWidth: 1.5,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            Path { path in
                guard let firstPoint = points.first(where: { $0.sample.connected })
                else { return }
                path.move(to: CGPoint(x: firstPoint.point.x, y: rect.maxY))
                var last: CGPoint = firstPoint.point
                var segmentOpen = false
                for item in points {
                    if item.sample.connected {
                        if !segmentOpen {
                            path.move(to: CGPoint(x: item.point.x, y: rect.maxY))
                            path.addLine(to: item.point)
                        } else {
                            path.addLine(to: item.point)
                        }
                        segmentOpen = true
                        last = item.point
                    } else if segmentOpen {
                        path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
                        path.closeSubpath()
                        segmentOpen = false
                    }
                }
                if segmentOpen {
                    path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
                    path.closeSubpath()
                }
            }
            .fill(
                LinearGradient(
                    colors: [
                        BossTheme.accent.opacity(0.14),
                        BossTheme.accent.opacity(0.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            ForEach(Array(chargePoints.prefix(16))) { item in
                Circle()
                    .fill(BossTheme.success)
                    .frame(width: 3, height: 3)
                    .position(item.point)
            }
        }
    }

    @ViewBuilder
    private func latestPoint(in rect: CGRect) -> some View {
        if let last = samples.last(where: { $0.date >= start && $0.date <= end }) {
            let point = point(for: last, in: rect)
            Circle()
                .fill(
                    isCharging || last.chargeState == .charging
                        ? BossTheme.success
                        : BossTheme.accentBright
                )
                .frame(width: 5, height: 5)
                .overlay(Circle().stroke(BossTheme.background, lineWidth: 1.5))
                .position(point)
        }
    }

    private func point(for sample: BatterySample, in rect: CGRect) -> CGPoint {
        let total = max(1, end.timeIntervalSince(start))
        let fraction = min(max(sample.date.timeIntervalSince(start) / total, 0), 1)
        return CGPoint(
            x: rect.minX + rect.width * fraction,
            y: yPosition(for: sample.level, in: rect)
        )
    }

    private func yPosition(for level: Int, in rect: CGRect) -> CGFloat {
        let span = max(1, upper - lower)
        let fraction = min(max(CGFloat(level - lower) / CGFloat(span), 0), 1)
        return rect.maxY - rect.height * fraction
    }
}
