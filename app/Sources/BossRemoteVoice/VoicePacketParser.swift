import Foundation

public struct VoicePacketParser {
    public struct Statistics: Equatable, Sendable {
        public var records = 0
        public var aclPackets = 0
        public var attValues = 0
        public var voiceFrames = 0
        public var opusFrames = 0

        public init() {}
    }

    private struct Source: Hashable {
        let connection: UInt16
        let attribute: UInt16
    }

    private struct Pending {
        var lastSequence: UInt16
        var packets: [Data]
    }

    private var recordBuffer: [UInt8] = []
    private var fragments: [UInt16: (expected: Int, bytes: [UInt8])] = [:]
    private var pending: [Source: Pending] = [:]
    private var locked: Set<Source> = []
    public private(set) var statistics = Statistics()

    public init() {}

    public mutating func reset() {
        recordBuffer.removeAll(keepingCapacity: true)
        fragments.removeAll(keepingCapacity: true)
        pending.removeAll(keepingCapacity: true)
        locked.removeAll(keepingCapacity: true)
        statistics = Statistics()
    }

    public mutating func ingest(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        if isCompleteRecord(bytes) {
            return process(record: bytes)
        }
        if let acl = normalizeACL(bytes) {
            return process(acl: acl)
        }

        recordBuffer.append(contentsOf: bytes)
        var output: [Data] = []
        while recordBuffer.count >= 4 {
            let length = Int(recordBuffer[0]) << 24
                | Int(recordBuffer[1]) << 16
                | Int(recordBuffer[2]) << 8
                | Int(recordBuffer[3])
            guard length >= 9, length <= 1_048_576 else {
                recordBuffer.removeAll(keepingCapacity: true)
                fragments.removeAll(keepingCapacity: true)
                return output
            }
            let total = length + 4
            guard recordBuffer.count >= total else { break }
            let record = Array(recordBuffer[0..<total])
            recordBuffer.removeFirst(total)
            output.append(contentsOf: process(record: record))
        }
        return output
    }

    private mutating func process(record: [UInt8]) -> [Data] {
        guard record.count >= 13 else { return [] }
        statistics.records += 1
        guard record[12] == 0x03 else { return [] }
        statistics.aclPackets += 1
        return process(acl: Array(record[13...]))
    }

    private mutating func process(acl bytes: [UInt8]) -> [Data] {
        guard bytes.count >= 4 else { return [] }
        let handleField = little(bytes, 0)
        let handle = handleField & 0x0FFF
        let boundary = UInt8((handleField >> 12) & 0x03)
        let declared = Int(little(bytes, 2))
        guard declared == bytes.count - 4 else {
            fragments.removeValue(forKey: handle)
            return []
        }
        let payload = Array(bytes[4...])

        switch boundary {
        case 0, 2, 3:
            guard payload.count >= 4 else { return [] }
            let l2capLength = Int(little(payload, 0))
            let cid = little(payload, 2)
            guard cid == 0x0004, l2capLength <= 512 else {
                fragments.removeValue(forKey: handle)
                return []
            }
            let initial = Array(payload[4...])
            guard initial.count <= l2capLength else { return [] }
            if initial.count == l2capLength {
                return completeATT(handle: handle, pdu: initial)
            }
            fragments[handle] = (l2capLength, initial)
            return []
        case 1:
            guard var fragment = fragments.removeValue(forKey: handle),
                  fragment.bytes.count + payload.count <= fragment.expected
            else { return [] }
            fragment.bytes.append(contentsOf: payload)
            if fragment.bytes.count == fragment.expected {
                return completeATT(handle: handle, pdu: fragment.bytes)
            }
            fragments[handle] = fragment
            return []
        default:
            return []
        }
    }

    private mutating func completeATT(handle: UInt16, pdu: [UInt8]) -> [Data] {
        guard pdu.count >= 3, pdu[0] == 0x1B || pdu[0] == 0x1D else { return [] }
        statistics.attValues += 1
        let attribute = little(pdu, 1)
        let value = Array(pdu[3...])
        return classify(value, source: Source(connection: handle, attribute: attribute))
    }

    private mutating func classify(_ value: [UInt8], source: Source) -> [Data] {
        guard let voice = decodeVoice(value) else {
            pending.removeValue(forKey: source)
            return []
        }
        statistics.voiceFrames += 1

        if locked.contains(source) {
            guard let existing = pending[source] else {
                pending[source] = Pending(lastSequence: voice.sequence, packets: [voice.opus])
                return []
            }
            let distance = voice.sequence &- existing.lastSequence
            guard distance > 0, distance < 0x8000 else {
                pending[source] = Pending(lastSequence: voice.sequence, packets: [voice.opus])
                return []
            }
            pending[source] = Pending(lastSequence: voice.sequence, packets: [voice.opus])
            statistics.opusFrames += 1
            return [voice.opus]
        }

        if var candidate = pending[source],
           voice.sequence == candidate.lastSequence &+ 1 {
            candidate.lastSequence = voice.sequence
            candidate.packets.append(voice.opus)
            if candidate.packets.count >= 3 {
                locked.insert(source)
                pending[source] = Pending(
                    lastSequence: candidate.lastSequence,
                    packets: []
                )
                statistics.opusFrames += candidate.packets.count
                return candidate.packets
            }
            pending[source] = candidate
            return []
        }
        pending[source] = Pending(lastSequence: voice.sequence, packets: [voice.opus])
        return []
    }

    private func decodeVoice(_ value: [UInt8]) -> (sequence: UInt16, opus: Data)? {
        var offsets: [Int] = []
        if (99...100).contains(value.count) { offsets.append(0) }
        if value.starts(with: [0xFA]), (99...100).contains(value.count - 1) {
            offsets.append(1)
        }
        if value.starts(with: [0xA1, 0xFA]), (99...100).contains(value.count - 2) {
            offsets.append(2)
        }
        for offset in offsets {
            guard value.count - offset >= 5 else { continue }
            let length = Int(value[offset + 4])
            let start = offset + 5
            let end = start + length
            guard length > 0, end <= value.count,
                  (value[start] & 0xFC) == 0xB8,
                  value[end...].allSatisfy({ $0 == 0 })
            else { continue }
            let sequence = UInt16(value[offset + 2])
                | UInt16(value[offset + 3]) << 8
            return (sequence, Data(value[start..<end]))
        }
        return nil
    }

    private func isCompleteRecord(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 13 else { return false }
        let length = Int(bytes[0]) << 24
            | Int(bytes[1]) << 16
            | Int(bytes[2]) << 8
            | Int(bytes[3])
        return length >= 9 && length + 4 == bytes.count
    }

    private func normalizeACL(_ bytes: [UInt8]) -> [UInt8]? {
        if bytes.first == 0x03 {
            let acl = Array(bytes.dropFirst())
            if isACL(acl) { return acl }
        }
        if bytes.count >= 9, bytes[8] == 0x03 {
            let acl = Array(bytes.dropFirst(9))
            if isACL(acl) { return acl }
        }
        if bytes.first == 0x02 {
            let acl = Array(bytes.dropFirst())
            if isACL(acl) { return acl }
        }
        if isACL(bytes) { return bytes }
        return nil
    }

    private func isACL(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 4 else { return false }
        return Int(little(bytes, 2)) == bytes.count - 4
    }

    private func little(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }
}
