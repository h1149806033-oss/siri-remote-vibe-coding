import AppKit
import BossRemoteCore
import BossRemoteHID
import BossRemoteVoice
import Combine
import CoreGraphics
import OSLog

@MainActor
final class AppModel: ObservableObject {
    @Published var connected = false
    @Published var deviceName: String?
    @Published var battery: Int?
    @Published var isCharging = false
    @Published private(set) var bluetoothState: BLEBatteryMonitor.State = .unknown
    @Published var activeControls: Set<RemoteControl> = []
    @Published var selectedControl: RemoteControl = .select
    @Published var status = L10n.t("等待 Siri Remote", "Waiting for Siri Remote")
    @Published var voiceStatus = L10n.t("语音尚未准备", "Voice not ready")
    @Published var hasAccessibility = PointerController.hasAccessibility
    @Published var hasInputMonitoring = CGPreflightListenEventAccess()
    @Published var logLines: [String] = []
    @Published private(set) var frontmostBundleID: String?
    @Published private(set) var frontmostAppName: String?
    @Published private(set) var hidDiagnostics = HIDRemoteMonitor.Diagnostics(
        isRunning: false,
        isConnected: false,
        usagePages: []
    )
    @Published private(set) var touchDiagnostics = TouchSurface.Diagnostics(
        isRunning: false,
        deviceCount: 0
    )
    @Published private(set) var voiceDiagnostics = VoiceEngine.Diagnostics()
    @Published private(set) var appProfileCount = 0
    @Published private(set) var isRestartingVoice = false

    let mapping: MappingStore
    let settings: AppSettings
    let history: HistoryStore
    let voiceStats: VoiceStatsStore
    let batteryInsights: BatteryInsightsStore
    let voice = VoiceEngine()

    private let hid = HIDRemoteMonitor()
    private let touch = TouchSurface()
    private let gestures = TouchGestureController()
    public let touchIndicator = TouchIndicatorModel()
    private let frontmost = FrontmostAppMonitor()
    private let bleBattery = BLEBatteryMonitor()
    private let logger = Logger(subsystem: "com.bossremote.dev", category: "runtime")
    private let logClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
    private let logFileFormatter = ISO8601DateFormatter()
    private var frontmostCancellable: AnyCancellable?
    private var profileCountCancellable: AnyCancellable?
    private var chargingLogCancellable: AnyCancellable?
    private var batteryAvailabilityCancellable: AnyCancellable?
    private var terminateObserver: NSObjectProtocol?
    private var started = false
    private var stopped = false
    private var voiceRestartID = 0
    private var lastTouchContactCount = 0
    private var hidBatteryLevel: Int?
    private var bleBatteryLevel: Int?
    private var lastDownAt: [RemoteControl: TimeInterval] = [:]
    private let doublePressWindow: TimeInterval = 0.35
    private let holdThreshold: TimeInterval = 0.5
    private var pendingHold: PendingHold?

    private struct PendingHold {
        var control: RemoteControl
        var work: DispatchWorkItem
        var tapAction: ButtonAction
        var app: (bundleID: String?, name: String?)
        var scopeBundleID: String?
        var doublePress: Bool
    }
    private var logBytes = -1
    private let logByteLimit = 2 * 1024 * 1024
    private lazy var logURL: URL = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Logs/BossRemoteDev", isDirectory: true)
            ?? URL(fileURLWithPath: "/tmp/BossRemoteDev", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("runtime.log")
    }()

    init(
        defaults: UserDefaults = .standard,
        historyFileURL: URL? = nil,
        batteryFileURL: URL? = nil,
        voiceStatsFileURL: URL? = nil
    ) {
        mapping = MappingStore(defaults: defaults)
        settings = AppSettings(defaults: defaults)
        history = HistoryStore(fileURL: historyFileURL)
        voiceStats = VoiceStatsStore(fileURL: voiceStatsFileURL)
        batteryInsights = BatteryInsightsStore(fileURL: batteryFileURL)
        voiceStats.backfillIfNeeded(from: history.events)
        batteryInsights.$isCharging
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .assign(to: &$isCharging)
        chargingLogCancellable = batteryInsights.$isCharging
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.appendLog("charging=\(value)")
            }
        batteryAvailabilityCancellable = batteryInsights.$batteryAvailable
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.appendLog("battery available=\(value)")
            }
    }

    func seedSnapshotState() {
        connected = true
        deviceName = "Siri Remote"
        battery = 47
        bluetoothState = .poweredOn
        status = L10n.t("已连接，按遥控器按钮测试", "Connected, try a remote button")
        voiceStatus = L10n.t("语音组件就绪", "Voice ready")
        frontmostBundleID = "com.apple.Safari"
        frontmostAppName = "Safari"
        hidDiagnostics = HIDRemoteMonitor.Diagnostics(
            isRunning: true,
            isConnected: true,
            usagePages: [0x01, 0x0C, 0x0D, 0xFF00]
        )
        touchDiagnostics = TouchSurface.Diagnostics(
            isRunning: true,
            deviceCount: 1
        )
        voiceDiagnostics = VoiceEngine.Diagnostics(
            prepared: true,
            capturing: false,
            virtualMicRunning: true,
            decodedFrames: 0,
            loggerState: L10n.t("已授权", "Authorized"),
            lastStatus: L10n.t("语音组件就绪", "Voice ready")
        )
        appProfileCount = mapping.appProfiles.count
        let snapshotCharging = ProcessInfo.processInfo.environment[
            "BOSS_REMOTE_SNAPSHOT_CHARGING"
        ] == "1"
        let snapshotUnavailable = ProcessInfo.processInfo.environment[
            "BOSS_REMOTE_SNAPSHOT_BATTERY_UNAVAILABLE"
        ] == "1"
        batteryInsights.seedPreview(
            charging: snapshotCharging,
            available: !snapshotUnavailable
        )
        voiceStats.seedPreview()
        battery = batteryInsights.currentLevel ?? battery
        isCharging = batteryInsights.isCharging
    }

    func start() {
        guard !started else { return }
        started = true
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stop()
            }
        }
        appendLog("app started accessibility=\(hasAccessibility) input=\(hasInputMonitoring)")

        gestures.onPointerMove = { dx, dy in
            PointerController.move(dx: dx, dy: dy)
        }
        gestures.onScroll = { pixels in
            PointerController.scroll(pixels: pixels)
        }
        gestures.onClick = { [weak self] in
            self?.appendLog("touch click")
            PointerController.click()
        }
        gestures.onLog = { [weak self] message in
            self?.appendLog(message)
        }
        gestures.onSwipe = { [weak self] direction, fromRing in
            guard let self else { return }
            self.runGesture(
                self.gestureControl(for: direction, fromRing: fromRing)
            )
        }
        gestures.onDoubleTap = { [weak self] in
            guard let self else { return }
            self.runGesture(.tapTwo)
        }
        gestures.doubleTapAvailable = { [weak self] in
            guard let self else { return false }
            return self.mapping.action(
                for: .tapTwo,
                bundleID: self.effectiveFrontmost.bundleID
            ) != .none
        }

        touch.onFrame = { [weak self] contacts, _ in
            guard let self else { return }
            if contacts.count != self.lastTouchContactCount {
                if contacts.count > 0, self.lastTouchContactCount == 0 {
                    self.batteryInsights.markActivity()
                }
                self.lastTouchContactCount = contacts.count
                self.appendLog("touch contacts=\(contacts.count)")
            }
            if contacts.isEmpty {
                self.touchIndicator.clear()
            } else {
                let count = Double(contacts.count)
                let x = contacts.reduce(0) { $0 + $1.x } / count
                let y = contacts.reduce(0) { $0 + $1.y } / count
                self.touchIndicator.update(x: x, y: y)
            }
            self.gestures.handle(contacts: contacts)
        }
        touch.onLog = { [weak self] message in
            self?.appendLog(message)
        }

        hid.onConnection = { [weak self] connected, name in
            guard let self else { return }
            self.connected = connected
            self.deviceName = name
            self.status = connected
                ? L10n.t("已连接，按遥控器按钮测试", "Connected, try a remote button")
                : L10n.t("等待 Siri Remote", "Waiting for Siri Remote")
            if !connected {
                self.hidBatteryLevel = nil
            } else if self.touchDiagnostics.deviceCount == 0 {
                self.touch.refreshDiagnostics()
            }
            self.publishBattery()
            self.batteryInsights.setConnected(connected, level: nil)
        }
        hid.onBattery = { [weak self] level in
            guard let self else { return }
            self.hidBatteryLevel = level
            self.publishBattery()
            self.batteryInsights.update(level: level, chargeState: nil)
        }
        hid.onButton = { [weak self] control, down in
            self?.handle(control: control, down: down)
        }
        hid.onLog = { [weak self] message in
            self?.appendLog(message)
        }
        hid.onDiagnostics = { [weak self] diagnostics in
            self?.hidDiagnostics = diagnostics
        }
        touch.onDiagnostics = { [weak self] diagnostics in
            self?.touchDiagnostics = diagnostics
        }
        voice.onDiagnostics = { [weak self] diagnostics in
            self?.voiceDiagnostics = diagnostics
        }

        voice.onStatus = { [weak self] message in
            self?.voiceStatus = message
            self?.appendLog("voice \(message)")
        }
        voice.onLog = { [weak self] message in
            self?.appendLog(message)
        }
        voice.onSessionEnded = { [weak self] summary in
            guard let self else { return }
            self.appendLog(
                "voice session ended frames=\(summary.frames) " +
                    "duration=\(String(format: "%.1f", summary.duration))"
            )
            guard self.settings.historyEnabled else { return }
            let app = self.effectiveFrontmost
            self.history.record(ActivityEvent(
                date: summary.endedAt,
                kind: .voice,
                appName: app.name,
                bundleID: app.bundleID,
                scopeLabel: self.scopeLabel(for: app.bundleID),
                duration: summary.duration,
                frames: summary.frames,
                detail: L10n.t("按住 Siri 语音输入", "Siri voice input")
            ))
            self.voiceStats.record(
                duration: summary.duration,
                at: summary.endedAt
            )
        }

        mapping.onMappingChange = { [weak self] control, action, bundleID in
            guard let self, self.settings.historyEnabled else { return }
            let profile = self.mapping.profile(for: bundleID)
            let detail: String
            if let bundleID {
                detail = self.mapping.isOverride(for: control, bundleID: bundleID)
                    ? L10n.t("设置 App 专属按键", "Set app override")
                    : L10n.t("跟随全局映射", "Following global")
            } else {
                detail = L10n.t("更新全局映射", "Updated global mapping")
            }
            self.history.record(ActivityEvent(
                kind: .mapping,
                control: control,
                actionLabel: action.label,
                appName: bundleID == nil
                    ? nil
                    : (profile?.displayName ?? self.frontmostAppName),
                bundleID: bundleID,
                scopeLabel: self.scopeLabel(for: bundleID),
                detail: detail
            ))
        }

        appProfileCount = mapping.appProfiles.count
        profileCountCancellable = mapping.$appProfiles
            .map(\.count)
            .receive(on: RunLoop.main)
            .sink { [weak self] count in
                self?.appProfileCount = count
            }

        bleBattery.onBattery = { [weak self] level in
            guard let self else { return }
            self.bleBatteryLevel = level
            self.publishBattery()
            if let level {
                self.batteryInsights.update(level: level, chargeState: nil)
            } else if self.hidBatteryLevel == nil {
                self.batteryInsights.markBatteryUnavailable()
            }
        }
        bleBattery.onChargeState = { [weak self] state in
            self?.batteryInsights.update(chargeState: state ?? .unknown)
        }
        bleBattery.onState = { [weak self] state in
            guard let self else { return }
            self.bluetoothState = state
            switch state {
            case .unauthorized, .poweredOff, .unsupported:
                self.bleBatteryLevel = nil
                self.publishBattery()
                self.batteryInsights.update(chargeState: .unknown)
                self.batteryInsights.markBatteryUnavailable()
            case .unknown, .resetting, .poweredOn:
                break
            }
        }
        bleBattery.onLog = { [weak self] message in
            self?.appendLog("BLE \(message)")
        }
        bleBattery.start()
        batteryInsights.start()

        frontmostCancellable = frontmost.$bundleID
            .combineLatest(frontmost.$name)
            .receive(on: RunLoop.main)
            .sink { [weak self] bundleID, name in
                guard let self else { return }
                let previous = self.frontmostBundleID
                self.frontmostBundleID = bundleID
                self.frontmostAppName = name
                if bundleID != previous {
                    self.appendLog("frontmost \(bundleID ?? "-")")
                }
                guard bundleID != previous,
                      let bundleID,
                      let profile = self.mapping.profile(for: bundleID),
                      self.settings.historyEnabled
                else { return }
                self.history.record(ActivityEvent(
                    kind: .app,
                    appName: name,
                    bundleID: bundleID,
                    scopeLabel: profile.displayName,
                    detail: L10n.t("已切换到 App 专属映射", "Switched to app mapping")
                ))
            }

        hid.start()
        touch.start()
        voice.prepare()
        refreshPermissions()
        applySettings()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
            self.terminateObserver = nil
        }
        PointerController.setRightCommand(false)
        frontmostCancellable?.cancel()
        profileCountCancellable?.cancel()
        bleBattery.stop()
        batteryInsights.stop()
        hid.stop()
        touch.stop()
        voice.shutdownForTermination()
    }

    func refreshPermissions() {
        let accessibility = PointerController.hasAccessibility
        let input = CGPreflightListenEventAccess()
        if accessibility != hasAccessibility || input != hasInputMonitoring {
            appendLog("permissions accessibility=\(accessibility) input=\(input)")
        }
        hasAccessibility = accessibility
        hasInputMonitoring = input
    }

    func requestAccessibility() {
        _ = PointerController.requestAccessibility()
        refreshPermissions()
    }

    func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        refreshPermissions()
    }

    func applySettings() {
        gestures.isPointerEnabled = settings.pointerEnabled
        gestures.isScrollEnabled = settings.scrollEnabled
        gestures.isTapEnabled = settings.tapToClick
        gestures.pressFreezeEnabled = settings.pressFreeze
        gestures.pointerSpeed = CGFloat(settings.pointerSpeed)
        gestures.scrollSpeed = CGFloat(settings.scrollSpeed)
    }

    func restartVoice() {
        guard !isRestartingVoice else { return }
        voiceRestartID += 1
        let restartID = voiceRestartID
        isRestartingVoice = true
        appendLog("voice restart requested")
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
            guard let self, self.voiceRestartID == restartID else { return }
            self.isRestartingVoice = false
        }
        voice.shutdown { [weak self] in
            guard let self, self.voiceRestartID == restartID else {
                return
            }
            self.voice.prepare()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                [weak self] in
                guard let self, self.voiceRestartID == restartID else {
                    return
                }
                self.isRestartingVoice = false
            }
        }
    }

    func clearHistory() {
        history.clear()
        voiceStats.clear()
    }

    func refreshDiagnostics() {
        hid.refreshDiagnostics()
        touch.refreshDiagnostics()
        voice.refreshDiagnostics()
        refreshPermissions()
        bleBattery.refresh()
        batteryInsights.recheck()
    }

    var logFileURL: URL {
        logURL
    }

    func noteDiagnostic(_ message: String) {
        appendLog(message)
    }

    private func handle(control: RemoteControl, down: Bool) {
        appendLog("button \(control.rawValue) \(down ? "down" : "up")")
        var isDoublePress = false
        if down {
            batteryInsights.markActivity()
            activeControls.insert(control)
            let now = ProcessInfo.processInfo.systemUptime
            isDoublePress = lastDownAt[control].map {
                now - $0 <= doublePressWindow
            } ?? false
            lastDownAt[control] = now
        } else {
            activeControls.remove(control)
        }
        if control == .siri {
            if down {
                if settings.siriRightCommand {
                    PointerController.setRightCommand(true)
                }
                voice.start()
            } else {
                voice.stop()
                PointerController.setRightCommand(false)
            }
            return
        }
        let app = effectiveFrontmost
        let scopeBundleID = app.bundleID

        if down {
            pendingHold?.work.cancel()
            pendingHold = nil
            let tapAction = mapping.action(for: control, bundleID: scopeBundleID)
            let holdAction = mapping.holdAction(
                for: control,
                bundleID: scopeBundleID
            )
            guard holdAction != .none else {
                fire(
                    control: control,
                    action: tapAction,
                    app: app,
                    scopeBundleID: scopeBundleID,
                    isHold: false,
                    doublePress: isDoublePress
                )
                return
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.pendingHold?.control == control else {
                    return
                }
                self.pendingHold = nil
                self.fire(
                    control: control,
                    action: holdAction,
                    app: app,
                    scopeBundleID: scopeBundleID,
                    isHold: true,
                    doublePress: false
                )
            }
            pendingHold = PendingHold(
                control: control,
                work: work,
                tapAction: tapAction,
                app: app,
                scopeBundleID: scopeBundleID,
                doublePress: isDoublePress
            )
            DispatchQueue.main.asyncAfter(
                deadline: .now() + holdThreshold,
                execute: work
            )
            return
        }

        guard let pending = pendingHold, pending.control == control else {
            return
        }
        pending.work.cancel()
        pendingHold = nil
        fire(
            control: control,
            action: pending.tapAction,
            app: pending.app,
            scopeBundleID: pending.scopeBundleID,
            isHold: false,
            doublePress: pending.doublePress
        )
    }

    private func fire(
        control: RemoteControl,
        action: ButtonAction,
        app: (bundleID: String?, name: String?),
        scopeBundleID: String?,
        isHold: Bool,
        doublePress: Bool
    ) {
        if action != .none {
            appendLog(
                "action \(control.rawValue)\(isHold ? " hold" : "") scope=\(scopeBundleID ?? "global") -> \(action.label)"
            )
            if settings.historyEnabled {
                history.record(ActivityEvent(
                    kind: .button,
                    control: control,
                    actionLabel: action.label,
                    appName: app.name,
                    bundleID: scopeBundleID,
                    scopeLabel: scopeLabel(for: scopeBundleID),
                    detail: isHold ? L10n.t("长按", "Hold") : nil
                ))
            }
            if let key = action.key {
                PointerController.press(key)
            }
        }
        if doublePress, control == .down {
            appendLog("double press down -> ，")
            PointerController.type("，")
        }
    }

    private func runGesture(_ control: RemoteControl) {
        let app = effectiveFrontmost
        let scopeBundleID = app.bundleID
        let action = mapping.action(for: control, bundleID: scopeBundleID)
        guard action != .none else {
            appendLog("gesture \(control.rawValue) unmapped")
            return
        }
        fire(
            control: control,
            action: action,
            app: app,
            scopeBundleID: scopeBundleID,
            isHold: false,
            doublePress: false
        )
    }

    private func gestureControl(
        for direction: TouchGestureController.SwipeDirection,
        fromRing: Bool
    ) -> RemoteControl {
        switch direction {
        case .up: return fromRing ? .ringUp : .swipeUp
        case .down: return fromRing ? .ringDown : .swipeDown
        case .left: return fromRing ? .ringLeft : .swipeLeft
        case .right: return fromRing ? .ringRight : .swipeRight
        }
    }

    private var effectiveFrontmost: (bundleID: String?, name: String?) {
        let isSelf = NSWorkspace.shared.frontmostApplication?
            .bundleIdentifier == Bundle.main.bundleIdentifier
        if isSelf {
            return (nil, nil)
        }
        return (frontmostBundleID, frontmostAppName)
    }

    private func publishBattery() {
        battery = bleBatteryLevel ?? hidBatteryLevel
    }

    private func scopeLabel(for bundleID: String?) -> String {
        if let bundleID, let profile = mapping.profile(for: bundleID) {
            return profile.displayName
        }
        return L10n.t("全局", "Global")
    }

    private func appendLog(_ message: String) {
        logger.info("\(message, privacy: .public)")
        let now = Date()
        logLines.append("\(logClockFormatter.string(from: now)) \(message)")
        if logLines.count > 80 {
            logLines.removeFirst(logLines.count - 80)
        }
        let line = "\(logFileFormatter.string(from: now)) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if logBytes < 0 {
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: logURL.path
            )
            logBytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        }
        if logBytes > logByteLimit {
            try? FileManager.default.removeItem(at: logURL)
            logBytes = 0
        }
        if !FileManager.default.fileExists(atPath: logURL.path) {
            try? data.write(to: logURL, options: .atomic)
            logBytes = data.count
            return
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        logBytes += data.count
    }
}
