import BossRemoteCore
import CoreGraphics
import Foundation
import IOKit.hid

public final class HIDRemoteMonitor {
    public struct Diagnostics: Equatable, Sendable {
        public let isRunning: Bool
        public let isConnected: Bool
        public let usagePages: [Int]

        public init(isRunning: Bool, isConnected: Bool, usagePages: [Int]) {
            self.isRunning = isRunning
            self.isConnected = isConnected
            self.usagePages = usagePages
        }
    }

    public var onConnection: ((Bool, String?) -> Void)?
    public var onBattery: ((Int) -> Void)?
    public var onButton: ((RemoteControl, Bool) -> Void)?
    public var onLog: ((String) -> Void)?
    public var onDiagnostics: ((Diagnostics) -> Void)?

    private struct Interface {
        let device: IOHIDDevice
        let usagePage: Int
    }

    private var manager: IOHIDManager?
    private var interfaces: [UInt: Interface] = [:]
    private var pressed: Set<RemoteControl> = []
    private var lastBattery: Int?
    private var isConnected = false

    public init() {}

    deinit {
        stop()
    }

    public func start() {
        guard manager == nil else { return }
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }

        let manager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey as String: HIDUsageMap.vendorID,
            kIOHIDProductIDKey as String: HIDUsageMap.productID,
        ] as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatchedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemovedCallback, context)
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            onLog?("HID manager open failed: \(result)")
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            return
        }
        self.manager = manager
        onLog?("HID monitor started")
        emitDiagnostics()
    }

    public func stop() {
        guard manager != nil else { return }
        for interface in interfaces.values {
            IOHIDDeviceRegisterInputValueCallback(interface.device, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(
                interface.device,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            IOHIDDeviceClose(interface.device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        interfaces.removeAll()
        pressed.removeAll()
        lastBattery = nil
        if isConnected {
            isConnected = false
            onConnection?(false, nil)
        }
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        onLog?("HID monitor stopped")
        emitDiagnostics()
    }

    fileprivate func deviceDidMatch(_ result: IOReturn, device: IOHIDDevice) {
        guard result == kIOReturnSuccess else {
            onLog?("HID match error: \(result)")
            return
        }
        let vendor = integerProperty(kIOHIDVendorIDKey, device: device)
        let product = integerProperty(kIOHIDProductIDKey, device: device)
        let usagePage = integerProperty(kIOHIDPrimaryUsagePageKey, device: device) ?? 0
        guard vendor == HIDUsageMap.vendorID,
              product == HIDUsageMap.productID,
              HIDUsageMap.acceptedPrimaryUsagePages.contains(usagePage)
        else {
            return
        }
        let key = interfaceKey(device)
        guard interfaces[key] == nil else { return }

        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            onLog?("HID interface open failed page=\(hex(usagePage)) code=\(openResult)")
            return
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputValueCallback(device, inputValueCallback, context)
        IOHIDDeviceScheduleWithRunLoop(
            device,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )
        interfaces[key] = Interface(device: device, usagePage: usagePage)

        if !isConnected {
            isConnected = true
            let name = stringProperty(kIOHIDProductKey, device: device)
            onConnection?(true, name)
        }
        onLog?("HID interface ready page=\(hex(usagePage))")
        emitDiagnostics()
    }

    fileprivate func deviceDidRemove(_ device: IOHIDDevice) {
        let key = interfaceKey(device)
        guard interfaces.removeValue(forKey: key) != nil else { return }
        IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(
            device,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if interfaces.isEmpty {
            releasePressedControls()
            if isConnected {
                isConnected = false
                onConnection?(false, nil)
            }
        }
        emitDiagnostics()
    }

    fileprivate func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let integerValue = IOHIDValueGetIntegerValue(value)

        if usagePage == 0x06, usage == 0x20 {
            let raw = Int(integerValue)
            let level = raw > 100
                ? Int((Double(raw) / 255.0 * 100.0).rounded())
                : raw
            let clamped = max(0, min(100, level))
            guard clamped != lastBattery else { return }
            lastBattery = clamped
            onLog?("HID battery raw=\(raw) level=\(clamped)")
            onBattery?(clamped)
            return
        }

        guard let control = HIDUsageMap.control(usagePage: usagePage, usage: usage) else {
            return
        }
        let isDown = integerValue != 0
        if isDown {
            guard pressed.insert(control).inserted else { return }
            onButton?(control, true)
        } else {
            guard pressed.remove(control) != nil else { return }
            onButton?(control, false)
        }
    }

    public func refreshDiagnostics() {
        emitDiagnostics()
    }

    private func emitDiagnostics() {
        onDiagnostics?(Diagnostics(
            isRunning: manager != nil,
            isConnected: isConnected,
            usagePages: Set(interfaces.values.map(\.usagePage)).sorted()
        ))
    }

    private func releasePressedControls() {
        let active = pressed
        pressed.removeAll()
        for control in active {
            onButton?(control, false)
        }
    }

    private func integerProperty(_ key: String, device: IOHIDDevice) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }

    private func stringProperty(_ key: String, device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private func interfaceKey(_ device: IOHIDDevice) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
    }

    private func hex(_ value: Int) -> String {
        String(format: "0x%04x", value)
    }
}

private let deviceMatchedCallback: IOHIDDeviceCallback = { context, result, _, device in
    guard let context else { return }
    let monitor = Unmanaged<HIDRemoteMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.deviceDidMatch(result, device: device)
}

private let deviceRemovedCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    let monitor = Unmanaged<HIDRemoteMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.deviceDidRemove(device)
}

private let inputValueCallback: IOHIDValueCallback = { context, result, _, value in
    guard result == kIOReturnSuccess, let context else { return }
    let monitor = Unmanaged<HIDRemoteMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.handle(value: value)
}
