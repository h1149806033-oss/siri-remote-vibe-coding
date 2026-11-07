import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

public final class VirtualMicOutput {
    public var onLog: ((String) -> Void)?
    public private(set) var isRunning = false

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 2,
        interleaved: true
    )!
    private var attached = false
    private var deviceID: AudioDeviceID?
    private var configurationObserver: NSObjectProtocol?
    private var restartWorkItem: DispatchWorkItem?
    private let stateLock = NSLock()
    private var isRestarting = false
    private var loggedFirstBuffer = false

    public init() {}

    deinit {
        stop()
    }

    @discardableResult
    public func start() -> Bool {
        if isRunning { return true }
        guard let device = findDevice() else {
            onLog?("MiRemoteV/SayAll output device not found")
            return false
        }
        deviceID = device
        loggedFirstBuffer = false
        guard configureOutput(device: device) else { return false }
        installConfigurationObserver()
        isRunning = true
        onLog?("virtual microphone output started")
        return true
    }

    public func enqueue(_ samples: [Int16]) {
        stateLock.lock()
        let canEnqueue = isRunning && !isRestarting
        stateLock.unlock()
        guard canEnqueue, !samples.isEmpty else { return }
        if !loggedFirstBuffer {
            loggedFirstBuffer = true
            onLog?("virtual microphone receiving audio")
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let data = buffer.int16ChannelData?[0] else { return }
        for (index, sample) in samples.enumerated() {
            data[index * 2] = sample
            data[index * 2 + 1] = sample
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    public func stop() {
        guard isRunning || attached else { return }
        restartWorkItem?.cancel()
        restartWorkItem = nil
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        stateLock.lock()
        isRunning = false
        isRestarting = false
        stateLock.unlock()
        player.stop()
        engine.stop()
        if attached {
            engine.disconnectNodeOutput(player)
            engine.detach(player)
            attached = false
        }
        engine.reset()
        onLog?("virtual microphone output stopped")
    }

    private func configureOutput(device: AudioDeviceID) -> Bool {
        if !attached {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            attached = true
        }
        guard let outputUnit = engine.outputNode.audioUnit else {
            onLog?("audio output unit unavailable")
            return false
        }
        var selectedDevice = device
        let result = AudioUnitSetProperty(
            outputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &selectedDevice,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard result == noErr else {
            onLog?("audio device select failed: \(result)")
            return false
        }
        var current: AudioDeviceID = 0
        var currentSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let currentStatus = AudioUnitGetProperty(
            outputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &current,
            &currentSize
        )
        onLog?(
            "virtual microphone output device=" +
                "\(deviceName(current)) status=\(currentStatus)"
        )
        engine.prepare()
        do {
            try engine.start()
        } catch {
            onLog?("audio engine start failed: \(error.localizedDescription)")
            return false
        }
        player.play()
        return true
    }

    private func installConfigurationObserver() {
        guard configurationObserver == nil else { return }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    private func handleConfigurationChange() {
        stateLock.lock()
        let shouldRestart = isRunning && !isRestarting
        if shouldRestart {
            isRestarting = true
        }
        stateLock.unlock()
        guard shouldRestart else { return }
        onLog?("audio route changed; restoring virtual microphone")
        restartWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.restartOutput()
        }
        restartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func restartOutput() {
        player.stop()
        engine.stop()
        guard let device = findDevice() else {
            stateLock.lock()
            isRunning = false
            isRestarting = false
            stateLock.unlock()
            onLog?("virtual microphone not found after route change")
            return
        }
        deviceID = device
        let restored = configureOutput(device: device)
        stateLock.lock()
        isRunning = restored
        isRestarting = false
        stateLock.unlock()
        onLog?(restored
            ? "virtual microphone output restored"
            : "virtual microphone restore failed")
    }

    private func deviceName(_ id: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        withUnsafeMutableBytes(of: &name) { bytes in
            guard let base = bytes.baseAddress else { return }
            _ = AudioObjectGetPropertyData(id, &address, 0, nil, &size, base)
        }
        return (name as String?) ?? "?"
    }

    private func findDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else { return nil }
        var ids = [AudioDeviceID](
            repeating: 0,
            count: Int(size) / MemoryLayout<AudioDeviceID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &ids
        ) == noErr else { return nil }

        for id in ids {
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: CFString?
            var nameSize = UInt32(MemoryLayout<CFString?>.size)
            let result = withUnsafeMutableBytes(of: &name) { bytes -> OSStatus in
                guard let base = bytes.baseAddress else { return -50 }
                return AudioObjectGetPropertyData(
                    id,
                    &nameAddress,
                    0,
                    nil,
                    &nameSize,
                    base
                )
            }
            guard result == noErr, let name else { continue }
            let lowered = (name as String).lowercased()
            if lowered.contains("miremotev") || lowered.contains("sayall") {
                return id
            }
        }
        return nil
    }
}
