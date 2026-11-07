import Foundation
import IOKit.hid

public final class RemoteMicControl {
    public var onLog: ((String) -> Void)?

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var retryTimer: Timer?

    public init() {}

    deinit {
        stop()
    }

    public func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey as String: 0x004C,
            kIOHIDProductIDKey as String: 0x0315,
        ] as CFDictionary)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            onLog?("microphone HID manager failed: \(result)")
            return
        }
        self.manager = manager
        locateDevice()
    }

    public func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        if device != nil {
            _ = setActive(false)
        }
        device = nil
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
    }

    private func locateDevice() {
        guard let manager else { return }
        if let device = findManagementInterface(manager) {
            self.device = device
            onLog?("microphone management interface ready")
            return
        }
        onLog?("microphone management interface unavailable; retrying")
        scheduleRetry()
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self,
                  self.device == nil,
                  let manager = self.manager,
                  let device = self.findManagementInterface(manager)
            else { return }
            self.device = device
            self.retryTimer?.invalidate()
            self.retryTimer = nil
            self.onLog?("microphone management interface ready")
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    @discardableResult
    public func setActive(_ active: Bool) -> Bool {
        guard let manager else { return false }
        if device == nil {
            device = findManagementInterface(manager)
        }
        guard let device else { return false }
        if sendReport(device, active: active) {
            onLog?("microphone \(active ? "started" : "stopped")")
            return true
        }
        // Bluetooth re-enumerates the management interface when the audio
        // route changes (for example AirPods connect). Re-discover and retry.
        self.device = findManagementInterface(manager)
        guard let refreshed = self.device else {
            onLog?("microphone interface unavailable after route change")
            return false
        }
        onLog?("microphone interface refreshed after route change")
        if sendReport(refreshed, active: active) {
            onLog?("microphone \(active ? "started" : "stopped")")
            return true
        }
        return false
    }

    private func sendReport(_ device: IOHIDDevice, active: Bool) -> Bool {
        var report: [UInt8] = [0x98, active ? 0x01 : 0x00]
        let result = report.withUnsafeMutableBufferPointer { buffer -> IOReturn in
            guard let base = buffer.baseAddress else {
                return kIOReturnBadArgument
            }
            return IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeFeature,
                0x98,
                base,
                buffer.count
            )
        }
        if result != kIOReturnSuccess {
            onLog?("microphone report \(active ? "start" : "stop") failed: \(result)")
            return false
        }
        return true
    }

    private func findManagementInterface(_ manager: IOHIDManager) -> IOHIDDevice? {
        guard let devices = IOHIDManagerCopyDevices(manager) else { return nil }
        let count = CFSetGetCount(devices)
        var values = [UnsafeRawPointer?](repeating: nil, count: count)
        CFSetGetValues(devices, &values)
        for value in values {
            guard let value else { continue }
            let device = Unmanaged<IOHIDDevice>
                .fromOpaque(value)
                .takeUnretainedValue()
            let page = (IOHIDDeviceGetProperty(
                device,
                kIOHIDPrimaryUsagePageKey as CFString
            ) as? NSNumber)?.intValue
            let usage = (IOHIDDeviceGetProperty(
                device,
                kIOHIDPrimaryUsageKey as CFString
            ) as? NSNumber)?.intValue
            if page == 0xFF00, usage == 0x000B {
                return device
            }
        }
        return nil
    }
}
