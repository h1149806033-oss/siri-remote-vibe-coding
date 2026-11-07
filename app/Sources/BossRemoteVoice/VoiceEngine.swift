import BossRemoteCore
import Foundation

public final class VoiceEngine {
    public struct SessionSummary: Sendable {
        public let startedAt: Date
        public let endedAt: Date
        public let duration: TimeInterval
        public let frames: Int

        public init(
            startedAt: Date,
            endedAt: Date,
            duration: TimeInterval,
            frames: Int
        ) {
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.duration = duration
            self.frames = frames
        }
    }

    public struct Diagnostics: Equatable, Sendable {
        public let prepared: Bool
        public let capturing: Bool
        public let virtualMicRunning: Bool
        public let decodedFrames: Int
        public let loggerState: String
        public let lastStatus: String

        public init(
            prepared: Bool = false,
            capturing: Bool = false,
            virtualMicRunning: Bool = false,
            decodedFrames: Int = 0,
            loggerState: String = L10n.t("未启动", "Not started"),
            lastStatus: String = ""
        ) {
            self.prepared = prepared
            self.capturing = capturing
            self.virtualMicRunning = virtualMicRunning
            self.decodedFrames = decodedFrames
            self.loggerState = loggerState
            self.lastStatus = lastStatus
        }
    }

    public var onStatus: ((String) -> Void)?
    public var onLog: ((String) -> Void)?
    public var onSessionEnded: ((SessionSummary) -> Void)?
    public var onDiagnostics: ((Diagnostics) -> Void)?

    private let hci = HCIClient()
    private let logger = BTPacketLoggerClient()
    private let mic = RemoteMicControl()
    private let audio = VirtualMicOutput()
    private let decoder = OpusDecoder()
    private let queue = DispatchQueue(label: "com.bossremote.voice")
    private let micQueue = DispatchQueue(label: "com.bossremote.mic")
    private let audioQueue = DispatchQueue(label: "com.bossremote.audio")
    private let lifecycleQueue = DispatchQueue(
        label: "com.bossremote.voice.lifecycle"
    )
    private var parser = VoicePacketParser()
    private var prepared = false
    private var preparing = false
    private var prepareGeneration = 0
    private var loggerStarted = false
    private var capturing = false
    private var stopWorkItem: DispatchWorkItem?
    private var pendingSummary: SessionSummary?
    private var decodedFrameCount = 0
    private var sessionPeak: Int = 0
    private var sessionStartedAt: Date?
    private var lastStatusText = ""
    private var lastLoggerState = L10n.t("未启动", "Not started")

    public init() {}

    public func prepare() {
        guard !preparing, !prepared else { return }
        preparing = true
        prepareGeneration += 1
        let generation = prepareGeneration

        hci.onLog = { [weak self] message in self?.log(message) }
        logger.onLog = { [weak self] message in self?.log(message) }
        mic.onLog = { [weak self] message in self?.log(message) }
        audio.onLog = { [weak self] message in self?.log(message) }

        guard decoder != nil else {
            preparing = false
            report(L10n.t("Opus 解码器缺失", "Opus decoder unavailable"))
            return
        }
        logger.onPacket = { [weak self] data in
            self?.handlePacket(data)
        }
        logger.onStatus = { [weak self] status in
            self?.handleLogger(status)
        }
        hci.prepare { [weak self] ok, status in
            guard let self else { return }
            guard generation == self.prepareGeneration else { return }
            self.preparing = false
            self.prepared = ok
            DispatchQueue.main.async {
                self.report(ok
                    ? L10n.t("语音组件就绪", "Voice ready")
                    : L10n.t(
                        "语音组件不可用：\(status)",
                        "Voice unavailable: \(status)"
                    ))
            }
            guard ok else { return }
            self.lifecycleQueue.async { [weak self] in
                guard let self, generation == self.prepareGeneration else {
                    return
                }
                self.micQueue.sync { self.mic.start() }
                guard generation == self.prepareGeneration else { return }
                self.startLoggerIfNeeded()
                self.audioQueue.sync {
                    if !self.audio.start() {
                        DispatchQueue.main.async { [weak self] in
                            guard let self,
                                  generation == self.prepareGeneration
                            else { return }
                            self.report(L10n.t(
                                "虚拟麦克风不可用",
                                "Virtual microphone unavailable"
                            ))
                        }
                    }
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          generation == self.prepareGeneration
                    else { return }
                    self.emitDiagnostics()
                }
            }
        }
    }

    public func start() {
        guard prepared, decoder != nil else {
            report(L10n.t("语音组件不可用", "Voice unavailable"))
            return
        }
        guard !capturing else { return }
        flushPendingSummary()
        stopWorkItem?.cancel()
        stopWorkItem = nil
        capturing = true
        decodedFrameCount = 0
        sessionPeak = 0
        sessionStartedAt = Date()
        queue.sync {
            parser.reset()
        }
        micQueue.sync { _ = mic.setActive(true) }
        let audioIsRunning = audioQueue.sync { audio.isRunning }
        if !audioIsRunning {
            audioQueue.sync { _ = audio.start() }
        }
        report(L10n.t("正在采集遥控器麦克风", "Capturing the remote microphone"))
    }

    public func stop() {
        guard capturing else { return }
        capturing = false
        micQueue.sync { _ = mic.setActive(false) }
        report(L10n.t("正在结束语音", "Finishing voice capture"))
        if let summary = buildSummary() {
            pendingSummary = summary
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.flushPendingSummary()
            self.report(self.prepared
                ? L10n.t("语音组件就绪", "Voice ready")
                : L10n.t("语音已停止", "Voice stopped"))
            self.emitDiagnostics()
        }
        stopWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// Synchronous teardown for application termination. The HCI restore
    /// request is sent without waiting for a reply; the helper finishes it
    /// after the app process exits.
    public func shutdownForTermination() {
        prepareGeneration += 1
        preparing = false
        capturing = false
        stopWorkItem?.cancel()
        stopWorkItem = nil
        micQueue.sync { mic.stop() }
        audioQueue.sync { audio.stop() }
        logger.stop()
        hci.releaseForTermination()
    }

    public func shutdown(completion: (() -> Void)? = nil) {
        prepareGeneration += 1
        preparing = false
        capturing = false
        if let summary = buildSummary() {
            pendingSummary = summary
        }
        stopWorkItem?.cancel()
        stopWorkItem = nil
        flushPendingSummary()

        let teardown = { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion?() }
                return
            }
            self.micQueue.sync { self.mic.stop() }
            self.audioQueue.sync { self.audio.stop() }
            self.logger.stop()
            self.hci.release()
            DispatchQueue.main.async {
                self.prepared = false
                self.loggerStarted = false
                self.lastLoggerState = L10n.t("已停止", "Stopped")
                self.emitDiagnostics()
                completion?()
            }
        }
        lifecycleQueue.async(execute: teardown)
    }

    private func buildSummary() -> SessionSummary? {
        guard let startedAt = sessionStartedAt else { return nil }
        let endedAt = Date()
        let frames = queue.sync { decodedFrameCount }
        sessionStartedAt = nil
        return SessionSummary(
            startedAt: startedAt,
            endedAt: endedAt,
            duration: max(0, endedAt.timeIntervalSince(startedAt)),
            frames: frames
        )
    }

    private func flushPendingSummary() {
        guard let summary = pendingSummary else { return }
        pendingSummary = nil
        onSessionEnded?(summary)
    }

    public func refreshDiagnostics() {
        DispatchQueue.main.async { [weak self] in
            self?.emitDiagnostics()
        }
    }

    private func emitDiagnostics() {
        let audioRunning = audioQueue.sync { audio.isRunning }
        let frames = queue.sync { decodedFrameCount }
        onDiagnostics?(Diagnostics(
            prepared: prepared,
            capturing: capturing,
            virtualMicRunning: audioRunning,
            decodedFrames: frames,
            loggerState: lastLoggerState,
            lastStatus: lastStatusText
        ))
    }

    private func startLoggerIfNeeded() {
        guard !loggerStarted else { return }
        loggerStarted = true
        logger.start()
    }

    private func report(_ status: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastStatusText = status
            self.onStatus?(status)
            self.emitDiagnostics()
        }
    }

    private func log(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onLog?(message)
        }
    }

    private func handleLogger(_ status: BTPacketLoggerClient.Status) {
        let state: String
        switch status {
        case .connecting:
            state = L10n.t("连接中", "Connecting")
        case .requiresAuthorization:
            state = L10n.t("等待授权", "Waiting for authorization")
        case .authorized:
            state = L10n.t("已授权", "Authorized")
        case .failed(let reason):
            state = L10n.t("失败：\(reason)", "Failed: \(reason)")
        case .stopped:
            state = L10n.t("已停止", "Stopped")
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastLoggerState = state
            self.emitDiagnostics()
        }
        switch status {
        case .connecting:
            report(L10n.t(
                "正在连接蓝牙音频通道",
                "Connecting the Bluetooth audio channel"
            ))
        case .requiresAuthorization:
            report(L10n.t(
                "等待蓝牙音频授权",
                "Waiting for Bluetooth audio authorization"
            ))
        case .authorized:
            report(L10n.t("语音组件就绪", "Voice ready"))
        case .failed(let reason):
            report(L10n.t(
                "蓝牙音频通道不可用：\(reason)",
                "Bluetooth audio channel unavailable: \(reason)"
            ))
        case .stopped:
            break
        }
    }

    private func handlePacket(_ data: Data) {
        queue.async { [weak self] in
            guard let self, self.capturing else { return }
            let packets = self.parser.ingest(data)
            for packet in packets {
                guard let samples = self.decoder?.decode(packet), !samples.isEmpty else {
                    continue
                }
                self.decodedFrameCount += 1
                let peak = samples.reduce(0) { max($0, abs(Int($1))) }
                self.sessionPeak = max(self.sessionPeak, peak)
                if self.decodedFrameCount == 1 || self.decodedFrameCount.isMultiple(of: 20) {
                    self.log(
                        "voice decoded frames=\(self.decodedFrameCount) " +
                            "samples=\(samples.count) peak=\(self.sessionPeak)"
                    )
                    DispatchQueue.main.async {
                        self.emitDiagnostics()
                    }
                }
                self.audioQueue.async {
                    self.audio.enqueue(samples)
                }
            }
        }
    }
}
