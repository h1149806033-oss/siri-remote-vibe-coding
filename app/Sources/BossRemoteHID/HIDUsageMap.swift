import BossRemoteCore

enum HIDUsageMap {
    static let vendorID = 0x004C
    static let productID = 0x0315
    static let acceptedPrimaryUsagePages: Set<Int> = [0x01, 0x06, 0x0C, 0x0D, 0xFF00]

    static func control(usagePage: UInt32, usage: UInt32) -> RemoteControl? {
        switch (usagePage, usage) {
        case (0x01, 0x86), (0x01, 0x40), (0x0C, 0x40), (0x0C, 0x224):
            return .back
        case (0x0C, 0x42):
            return .up
        case (0x0C, 0x43):
            return .down
        case (0x0C, 0x44):
            return .left
        case (0x0C, 0x45):
            return .right
        case (0x0C, 0x04), (0xFF00, 0x01), (0xFF00, 0x02), (0xFF00, 0x03),
             (0x0B, 0x21), (0x0B, 0x2F):
            return .siri
        case (0x0C, 0x60), (0x0C, 0x223):
            return .tv
        case (0x0C, 0x80), (0x0C, 0x41), (0x09, 0x01):
            return .select
        case (0x0C, 0xCD):
            return .playPause
        case (0x0C, 0xE9):
            return .volumeUp
        case (0x0C, 0xEA):
            return .volumeDown
        case (0x0C, 0xE2), (0x0C, 0x20):
            return .mute
        case (0x0C, 0x30):
            return .power
        default:
            return nil
        }
    }
}
