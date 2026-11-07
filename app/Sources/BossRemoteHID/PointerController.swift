import AppKit
import ApplicationServices
import BossRemoteCore
import CoreGraphics

public enum PointerController {
    private static let marker: Int64 = 0x4252_4D54
    /// One shared source: creating a fresh `CGEventSource` per frame showed up
    /// as jitter at the 90 Hz the remote reports.
    private static let hidSource = CGEventSource(stateID: .hidSystemState)

    private static var cursorLocation: CGPoint {
        CGEvent(source: hidSource)?.location ?? .zero
    }

    public static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public static func requestAccessibility() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func move(dx: CGFloat, dy: CGFloat) {
        guard hasAccessibility, let source = hidSource else { return }
        let current = cursorLocation
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: current.x + dx, y: current.y + dy),
            mouseButton: .left
        ) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cghidEventTap)
    }

    public static func scroll(pixels: Int32) {
        guard hasAccessibility,
              pixels != 0,
              let source = hidSource,
              let event = CGEvent(
                  scrollWheelEvent2Source: source,
                  units: .pixel,
                  wheelCount: 1,
                  wheel1: pixels,
                  wheel2: 0,
                  wheel3: 0
              )
        else { return }
        event.location = cursorLocation
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cghidEventTap)
    }

    public static func type(_ text: String) {
        guard hasAccessibility,
              !text.isEmpty,
              let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: 0,
                  keyDown: true
              ),
              let up = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: 0,
                  keyDown: false
              )
        else { return }
        let units = Array(text.utf16)
        units.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            down.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: base
            )
            up.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: base
            )
        }
        for event in [down, up] {
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cghidEventTap)
        }
    }

    public static func click() {
        guard hasAccessibility, let source = hidSource else { return }
        let location = cursorLocation
        guard let down = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: location,
            mouseButton: .left
        ), let up = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: location,
            mouseButton: .left
        ) else { return }
        for event in [down, up] {
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cghidEventTap)
        }
    }

    public static func setRightCommand(_ down: Bool) {
        guard hasAccessibility,
              let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: 54,
                  keyDown: down
              )
        else { return }
        var flags: CGEventFlags = []
        if down {
            flags.insert(.maskCommand)
            flags.insert(CGEventFlags(rawValue: 0x10))
        }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cghidEventTap)
    }

    public static func press(_ key: KeyBinding) {
        guard hasAccessibility else { return }
        let systemKeyType: Int32?
        switch key {
        case .mediaPlayPause: systemKeyType = 16
        case .mediaNext: systemKeyType = 17
        case .mediaPrevious: systemKeyType = 18
        case .brightnessUp: systemKeyType = 2
        case .brightnessDown: systemKeyType = 3
        default: systemKeyType = nil
        }
        if let type = systemKeyType {
            postSystemKey(type)
            return
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }
        for isDown in [true, false] {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: key.keyCode,
                keyDown: isDown
            ) else { continue }
            event.flags = key.flags
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cghidEventTap)
        }
    }

    private static func postSystemKey(_ keyType: Int32) {
        for isDown in [true, false] {
            let flags = NSEvent.ModifierFlags(
                rawValue: isDown ? 0xa00 : 0xb00
            )
            let data1 = Int((keyType << 16) | ((isDown ? 0xa : 0xb) << 8))
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: Int16(8),
                data1: data1,
                data2: -1
            ) else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
