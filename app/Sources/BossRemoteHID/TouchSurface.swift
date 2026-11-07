import CoreFoundation
import Darwin
import Foundation

private struct MTPoint {
    var x: Float
    var y: Float
}

private struct MTVector {
    var position: MTPoint
    var velocity: MTPoint
}

private struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var pathIndex: Int32
    var state: Int32
    var fingerID: Int32
    var handID: Int32
    var normalizedVector: MTVector
    var zTotal: Float
    var field9: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absoluteVector: MTVector
    var field14: Int32
    var field15: Int32
    var zDensity: Float
}

private typealias MTFrameCallback = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafeRawPointer?,
    Int,
    Double,
    Int,
    UnsafeMutableRawPointer?
) -> Void

private typealias MTDeviceCreateList = @convention(c) () -> CFArray?
private typealias MTDeviceIsBuiltIn = @convention(c) (UnsafeMutableRawPointer?) -> Bool
private typealias MTDeviceGetDimensions = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafeMutablePointer<Int32>,
    UnsafeMutablePointer<Int32>
) -> Int32
private typealias MTDeviceStart = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
private typealias MTDeviceStop = @convention(c) (UnsafeMutableRawPointer?) -> Int32
private typealias MTDeviceGetDeviceID = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafeMutablePointer<UInt64>
) -> Int32
private typealias MTRegisterCallback = @convention(c) (
    UnsafeMutableRawPointer?,
    MTFrameCallback?,
    UnsafeMutableRawPointer?
) -> Void
private typealias MTUnregisterCallback = @convention(c) (
    UnsafeMutableRawPointer?,
    MTFrameCallback?
) -> Void

public final class TouchSurface {
    public struct Contact: Equatable, Sendable {
        public let id: Int
        public let x: Double
        public let y: Double
        public let size: Double

        public init(id: Int, x: Double, y: Double, size: Double) {
            self.id = id
            self.x = x
            self.y = y
            self.size = size
        }
    }

    public struct Diagnostics: Equatable, Sendable {
        public let isRunning: Bool
        public let deviceCount: Int

        public init(isRunning: Bool, deviceCount: Int) {
            self.isRunning = isRunning
            self.deviceCount = deviceCount
        }
    }

    public var onFrame: (([Contact], TimeInterval) -> Void)?
    public var onLog: ((String) -> Void)?
    public var onDiagnostics: ((Diagnostics) -> Void)?
    public private(set) var isRunning = false

    private struct AttachedDevice {
        let id: UInt64
        let pointer: UnsafeMutableRawPointer
    }

    private var framework: UnsafeMutableRawPointer?
    private var deviceList: CFArray?
    private var devices: [AttachedDevice] = []
    private var createList: MTDeviceCreateList?
    private var isBuiltIn: MTDeviceIsBuiltIn?
    private var getDimensions: MTDeviceGetDimensions?
    private var getDeviceID: MTDeviceGetDeviceID?
    private var startDevice: MTDeviceStart?
    private var stopDevice: MTDeviceStop?
    private var registerCallback: MTRegisterCallback?
    private var unregisterCallback: MTUnregisterCallback?
    private var rescanTimer: Timer?

    public init() {}

    deinit {
        stop()
    }

    public func start() {
        guard framework == nil else {
            rescan()
            return
        }
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let framework = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else {
            onLog?("MultitouchSupport unavailable")
            return
        }
        self.framework = framework
        guard resolveSymbols() else {
            onLog?("MultitouchSupport symbols unavailable")
            closeFramework()
            return
        }
        scan()
        if !isRunning {
            onLog?("touch surface waiting for device")
            emitDiagnostics()
        }
        startRescanTimer()
    }

    public func stop() {
        guard framework != nil else { return }
        rescanTimer?.invalidate()
        rescanTimer = nil
        isRunning = false
        for device in devices {
            unregisterCallback?(device.pointer, touchFrameCallback)
            _ = stopDevice?(device.pointer)
        }
        devices.removeAll()
        deviceList = nil
        onLog?("touch surface stopped")
        emitDiagnostics()
    }

    public func refreshDiagnostics() {
        if framework == nil {
            start()
            return
        }
        rescan()
    }

    private func rescan() {
        scan()
        emitDiagnostics()
    }

    private func startRescanTimer() {
        guard rescanTimer == nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.scan()
        }
        RunLoop.main.add(timer, forMode: .common)
        rescanTimer = timer
    }

    private func scan() {
        guard let createList, let list = createList() else { return }
        deviceList = list
        let count = CFArrayGetCount(list)

        var presentIDs = Set<UInt64>()
        var candidates: [(device: UnsafeMutableRawPointer, id: UInt64, width: Int32, height: Int32)] = []
        for index in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            if let isBuiltIn, isBuiltIn(device) { continue }
            var width: Int32 = 0
            var height: Int32 = 0
            guard let getDimensions,
                  getDimensions(device, &width, &height) == 0
            else { continue }
            let maximum = max(width, height)
            guard maximum > 0, maximum < 6000 else { continue }
            let identifier = deviceIdentifier(device)
            presentIDs.insert(identifier)
            candidates.append((device, identifier, width, height))
        }

        let vanished = Set(devices.map(\.id)).subtracting(presentIDs)
        if !vanished.isEmpty {
            devices.removeAll { vanished.contains($0.id) }
            onLog?("touch device lost ids=\(vanished.sorted())")
        }

        let attachedIDs = Set(devices.map(\.id))
        for candidate in candidates where !attachedIDs.contains(candidate.id) {
            registerCallback?(
                candidate.device,
                touchFrameCallback,
                Unmanaged.passUnretained(self).toOpaque()
            )
            guard let startDevice, startDevice(candidate.device, 0) == 0 else {
                unregisterCallback?(candidate.device, touchFrameCallback)
                continue
            }
            devices.append(AttachedDevice(id: candidate.id, pointer: candidate.device))
            onLog?(
                "touch device attached id=\(candidate.id) " +
                    "\(candidate.width)x\(candidate.height)"
            )
        }

        let wasRunning = isRunning
        isRunning = !devices.isEmpty
        if isRunning, !wasRunning {
            onLog?("touch surface started devices=\(devices.count)")
        }
        if isRunning != wasRunning {
            emitDiagnostics()
        }
    }

    private func deviceIdentifier(_ device: UnsafeMutableRawPointer?) -> UInt64 {
        if let getDeviceID {
            var identifier: UInt64 = 0
            if getDeviceID(device, &identifier) == 0, identifier != 0 {
                return identifier
            }
        }
        return UInt64(UInt(bitPattern: device))
    }

    private func emitDiagnostics() {
        onDiagnostics?(Diagnostics(
            isRunning: isRunning,
            deviceCount: devices.count
        ))
    }

    fileprivate func receive(
        touches: UnsafePointer<MTTouch>?,
        count: Int,
        timestamp: Double
    ) {
        guard isRunning else { return }
        guard let touches, count > 0 else {
            DispatchQueue.main.async { [weak self] in
                self?.onFrame?([], timestamp)
            }
            return
        }
        var contacts: [Contact] = []
        contacts.reserveCapacity(count)
        for index in 0..<count {
            let touch = touches[index]
            guard touch.state == 3 || touch.state == 4 else { continue }
            contacts.append(Contact(
                id: Int(touch.fingerID),
                x: Double(touch.normalizedVector.position.x),
                y: Double(touch.normalizedVector.position.y),
                size: Double(touch.zTotal)
            ))
        }
        DispatchQueue.main.async { [weak self] in
            self?.onFrame?(contacts, timestamp)
        }
    }

    private func resolveSymbols() -> Bool {
        createList = symbol("MTDeviceCreateList", as: MTDeviceCreateList.self)
        isBuiltIn = symbol("MTDeviceIsBuiltIn", as: MTDeviceIsBuiltIn.self)
        getDimensions = symbol(
            "MTDeviceGetSensorSurfaceDimensions",
            as: MTDeviceGetDimensions.self
        )
        getDeviceID = symbol("MTDeviceGetDeviceID", as: MTDeviceGetDeviceID.self)
        startDevice = symbol("MTDeviceStart", as: MTDeviceStart.self)
        stopDevice = symbol("MTDeviceStop", as: MTDeviceStop.self)
        registerCallback = symbol(
            "MTRegisterContactFrameCallbackWithRefcon",
            as: MTRegisterCallback.self
        )
        unregisterCallback = symbol(
            "MTUnregisterContactFrameCallback",
            as: MTUnregisterCallback.self
        )
        return createList != nil
            && getDimensions != nil
            && startDevice != nil
            && stopDevice != nil
            && registerCallback != nil
            && unregisterCallback != nil
    }

    private func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let framework, let pointer = dlsym(framework, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    private func closeFramework() {
        guard let framework else { return }
        dlclose(framework)
        self.framework = nil
    }
}

private let touchFrameCallback: MTFrameCallback = { device, rawTouches, count, timestamp, _, context in
    _ = device
    guard let context else { return }
    let surface = Unmanaged<TouchSurface>.fromOpaque(context).takeUnretainedValue()
    let touches = rawTouches?.assumingMemoryBound(to: MTTouch.self)
    surface.receive(touches: touches, count: count, timestamp: timestamp)
}
