import Combine
import Foundation

public enum BatteryChargeState: String, Codable, Sendable {
    case charging
    case externalPower
    case onBattery
    case unknown
}

public struct BatterySample: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var date: Date
    public var level: Int
    public var chargeState: BatteryChargeState?
    public var active: Bool
    public var connected: Bool

    public init(
        id: UUID = UUID(),
        date: Date,
        level: Int,
        chargeState: BatteryChargeState? = nil,
        active: Bool = false,
        connected: Bool = true
    ) {
        self.id = id
        self.date = date
        self.level = level
        self.chargeState = chargeState
        self.active = active
        self.connected = connected
    }
}

public struct BatterySession: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var startLevel: Int?
    public var endLevel: Int?

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        startLevel: Int? = nil,
        endLevel: Int? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.startLevel = startLevel
        self.endLevel = endLevel
    }
}

public struct BatteryChargeSession: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var startedAt: Date
    public var startLevel: Int?
    public var endLevel: Int?
    public var lastRiseAt: Date?
    public var endedAt: Date?

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        startLevel: Int? = nil,
        endLevel: Int? = nil,
        lastRiseAt: Date? = nil,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.startLevel = startLevel
        self.endLevel = endLevel
        self.lastRiseAt = lastRiseAt
        self.endedAt = endedAt
    }
}

public final class BatteryInsightsStore: ObservableObject {
    @Published public private(set) var samples: [BatterySample] = []
    @Published public private(set) var sessions: [BatterySession] = []
    @Published public private(set) var currentLevel: Int?
    @Published public private(set) var chargeState: BatteryChargeState = .unknown
    @Published public private(set) var connected = false
    @Published public private(set) var lastActivityAt: Date?
    @Published public private(set) var lastLevelIncreaseAt: Date?
    @Published public private(set) var lastLevelReadAt: Date?
    @Published public private(set) var batteryAvailable = false
    @Published public private(set) var activeChargeSession: BatteryChargeSession?
    @Published public private(set) var isCharging = false

    private var lastChargeStateAt: Date?
    private let readingFreshness: TimeInterval = 3 * 60
    private let chargeStateFreshness: TimeInterval = 3 * 60

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.bossremote.battery", qos: .utility)
    private var lastSampleAt: Date?
    private var lastSampleLevel: Int?
    private var heartbeatTimer: Timer?
    private var started = false
    private let sampleLimit = 2_000
    private let retention: TimeInterval = 7 * 24 * 60 * 60
    private let chargeIdleWindow: TimeInterval = 90
    private let chargeIdleWindowHigh: TimeInterval = 3 * 60
    private let chargeIdleWindowFull: TimeInterval = 5 * 60

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.fileURL = base
                .appendingPathComponent("BossRemote", isDirectory: true)
                .appendingPathComponent("battery.json", isDirectory: false)
        }
        load()
    }

    public func start() {
        guard !started else { return }
        started = true
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) {
            [weak self] _ in
            self?.heartbeat()
        }
    }

    public func stop() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        if connected {
            connected = false
            if sessions.indices.contains(0), sessions[0].endedAt == nil {
                sessions[0].endedAt = Date()
                sessions[0].endLevel = currentLevel
            }
        }
        isCharging = false
        started = false
        save()
    }

    public func setConnected(_ connected: Bool, level: Int?) {
        guard connected != self.connected else {
            if connected, let level {
                update(level: level, chargeState: nil)
            }
            return
        }
        let now = Date()
        if connected {
            self.connected = true
            if let level {
                currentLevel = clamp(level)
                lastLevelReadAt = now
                batteryAvailable = true
            } else if let lastRead = lastLevelReadAt,
                      now.timeIntervalSince(lastRead) <= readingFreshness {
                batteryAvailable = true
            } else {
                batteryAvailable = false
            }
            if level != nil,
               var charge = activeChargeSession,
               let currentLevel {
                if let end = charge.endLevel, currentLevel < end {
                    lastLevelIncreaseAt = nil
                    finishChargeSession(at: now, level: currentLevel)
                } else {
                    charge.endLevel = currentLevel
                    activeChargeSession = charge
                }
            }
            if let level {
                recordSample(level: level, force: true, active: false)
            }
            let session = BatterySession(
                startedAt: now,
                startLevel: batteryAvailable ? currentLevel : nil
            )
            sessions.insert(session, at: 0)
            trimSessions()
        } else {
            let canRecord = batteryAvailable
                || lastLevelReadAt.map {
                    now.timeIntervalSince($0) <= readingFreshness
                } ?? false
            self.connected = false
            batteryAvailable = false
            if let session = activeChargeSession {
                finishChargeSession(
                    at: session.lastRiseAt ?? now,
                    level: currentLevel
                )
            }
            chargeState = .unknown
            isCharging = false
            if sessions.indices.contains(0), sessions[0].endedAt == nil {
                sessions[0].endedAt = now
                sessions[0].endLevel = currentLevel
            }
            if canRecord {
                recordSample(
                    level: currentLevel,
                    force: true,
                    active: lastActivityAt != nil
                )
            }
        }
        refreshChargingState(now: now)
        save()
    }

    public func markBatteryUnavailable() {
        batteryAvailable = false
        isCharging = false
        if let session = activeChargeSession {
            finishChargeSession(
                at: session.lastRiseAt ?? Date(),
                level: currentLevel
            )
        }
        save()
    }

    public func update(
        level: Int?,
        chargeState newChargeState: BatteryChargeState?
    ) {
        let now = Date()
        var changed = false
        var rose = false
        let previousLevel = currentLevel

        if let level {
            let value = clamp(level)
            lastLevelReadAt = now
            batteryAvailable = true
            if currentLevel != value {
                currentLevel = value
                changed = true
            }
            if let previousLevel, value > previousLevel {
                lastLevelIncreaseAt = now
                rose = true
            }
            if sessions.indices.contains(0), sessions[0].endedAt == nil {
                if sessions[0].startLevel == nil {
                    sessions[0].startLevel = value
                }
                if sessions[0].endLevel != value {
                    sessions[0].endLevel = value
                }
            }
        }

        if let newChargeState {
            lastChargeStateAt = now
            if chargeState != newChargeState {
                chargeState = newChargeState
                changed = true
            }
        }

        if let previousLevel, let currentLevel,
           previousLevel - currentLevel >= 2,
           newChargeState != .charging,
           activeChargeSession != nil {
            lastLevelIncreaseAt = nil
            finishChargeSession(at: now, level: currentLevel)
        }

        trackCharging(
            level: currentLevel,
            rose: rose,
            newState: newChargeState,
            now: now
        )
        refreshChargingState(now: now)

        if batteryAvailable, let currentLevel {
            let due = lastSampleAt.map {
                now.timeIntervalSince($0) >= 300
            } ?? true
            if changed || due {
                recordSample(
                    level: currentLevel,
                    force: false,
                    active: activitySinceLastSample()
                )
            }
        }
        if changed {
            save()
        }
    }

    public func update(chargeState: BatteryChargeState) {
        update(level: nil, chargeState: chargeState)
    }

    public func markActivity() {
        lastActivityAt = Date()
    }

    public func recheck() {
        let now = Date()
        let hadCharge = activeChargeSession != nil
        expireChargeSessionIfNeeded(now: now, level: currentLevel)
        refreshChargingState(now: now)
        if hadCharge, activeChargeSession == nil {
            save()
        }
    }

    public func hasFreshChargeState(now: Date = Date()) -> Bool {
        lastChargeStateAt.map {
            now.timeIntervalSince($0) <= chargeStateFreshness
        } ?? false
    }

    private func heartbeat() {
        guard connected else { return }
        let now = Date()
        if let lastRead = lastLevelReadAt {
            if now.timeIntervalSince(lastRead) > readingFreshness {
                batteryAvailable = false
            }
        } else {
            batteryAvailable = false
        }
        guard batteryAvailable, let level = currentLevel else {
            if let session = activeChargeSession {
                finishChargeSession(
                    at: session.lastRiseAt ?? now,
                    level: currentLevel
                )
                save()
            }
            isCharging = false
            return
        }
        let hadCharge = activeChargeSession != nil
        expireChargeSessionIfNeeded(now: now, level: level)
        if hadCharge, activeChargeSession == nil {
            save()
        }
        refreshChargingState(now: now)
        if lastSampleAt.map({ now.timeIntervalSince($0) >= 300 }) ?? true {
            recordSample(
                level: level,
                force: false,
                active: activitySinceLastSample()
            )
        }
        if sessions.indices.contains(0), sessions[0].endedAt == nil,
           sessions[0].endLevel != level {
            sessions[0].endLevel = level
        }
    }

    public func chargeRate(now: Date = Date()) -> Double? {
        guard let session = activeChargeSession,
              let start = session.startLevel,
              let end = session.endLevel
        else { return nil }
        let seconds = now.timeIntervalSince(session.startedAt)
        guard seconds >= 120 else { return nil }
        let gained = end - start
        guard gained >= 1 else { return nil }
        return Double(gained) / (seconds / 3600)
    }

    public func chargeTimeRemaining(now: Date = Date()) -> TimeInterval? {
        guard isCharging,
              let level = currentLevel,
              level < 100,
              let rate = chargeRate(now: now),
              rate > 0
        else { return nil }
        return Double(100 - level) / rate * 3600
    }

    private func trackCharging(
        level: Int?,
        rose: Bool,
        newState: BatteryChargeState?,
        now: Date
    ) {
        if var session = activeChargeSession {
            if let level {
                session.endLevel = level
            }
            if rose {
                session.lastRiseAt = now
            }
            activeChargeSession = session

            if let newState {
                switch newState {
                case .charging:
                    break
                case .onBattery, .externalPower:
                    finishChargeSession(
                        at: session.lastRiseAt ?? now,
                        level: level
                    )
                case .unknown:
                    expireChargeSessionIfNeeded(now: now, level: level)
                }
            } else {
                expireChargeSessionIfNeeded(now: now, level: level)
            }
            return
        }

        guard rose || newState == .charging else { return }
        activeChargeSession = BatteryChargeSession(
            startedAt: chargeStartDate(now: now),
            startLevel: chargeStartLevel(now: now, fallback: level),
            endLevel: level,
            lastRiseAt: rose ? now : nil
        )
    }

    private func expireChargeSessionIfNeeded(now: Date, level: Int?) {
        if chargeState == .charging,
           let lastState = lastChargeStateAt,
           now.timeIntervalSince(lastState) <= chargeStateFreshness {
            return
        }
        guard let session = activeChargeSession else { return }
        let lastSignal = session.lastRiseAt
            ?? lastChargeStateAt
            ?? session.startedAt
        guard now.timeIntervalSince(lastSignal) >= chargeIdleWindow(for: level)
        else { return }
        finishChargeSession(at: lastSignal, level: level)
    }

    private func chargeIdleWindow(for level: Int?) -> TimeInterval {
        guard let level else { return chargeIdleWindow }
        if level >= 95 {
            return chargeIdleWindowFull
        }
        if level >= 90 {
            return chargeIdleWindowHigh
        }
        return chargeIdleWindow
    }

    private func finishChargeSession(at end: Date, level: Int?) {
        guard var session = activeChargeSession else { return }
        session.endedAt = max(end, session.startedAt)
        if let level {
            session.endLevel = level
        }
        activeChargeSession = nil
    }

    private func chargeStartDate(now: Date) -> Date {
        guard let lastSampleAt,
              now.timeIntervalSince(lastSampleAt) <= 30 * 60
        else { return now }
        return lastSampleAt
    }

    private func chargeStartLevel(now: Date, fallback: Int?) -> Int? {
        guard let lastSampleAt,
              now.timeIntervalSince(lastSampleAt) <= 30 * 60
        else { return fallback }
        return lastSampleLevel ?? fallback
    }

    private func refreshChargingState(now: Date) {
        guard connected, batteryAvailable else {
            isCharging = false
            return
        }
        let stateFresh = lastChargeStateAt.map {
            now.timeIntervalSince($0) <= chargeStateFreshness
        } ?? false
        if stateFresh {
            switch chargeState {
            case .charging:
                isCharging = true
                return
            case .onBattery, .externalPower:
                isCharging = false
                return
            case .unknown:
                break
            }
        }
        let window = chargeIdleWindow(for: currentLevel)
        let recentRise = lastLevelIncreaseAt.map {
            now.timeIntervalSince($0) < window
        } ?? false
        let sessionRecent: Bool
        if let session = activeChargeSession {
            let lastSignal = session.lastRiseAt ?? session.startedAt
            sessionRecent = now.timeIntervalSince(lastSignal) < window
        } else {
            sessionRecent = false
        }
        isCharging = sessionRecent || recentRise
    }

    private func activitySinceLastSample() -> Bool {
        guard let lastActivityAt else { return false }
        guard let lastSampleAt else { return true }
        return lastActivityAt > lastSampleAt
    }

    private func recordSample(
        level: Int?,
        force: Bool,
        active: Bool
    ) {
        guard let level else { return }
        let now = Date()
        if !force,
           let last = samples.last,
           last.level == level,
           now.timeIntervalSince(last.date) < 60 {
            return
        }
        samples.append(BatterySample(
            date: now,
            level: clamp(level),
            chargeState: chargeState,
            active: active,
            connected: connected
        ))
        lastSampleAt = now
        lastSampleLevel = level
        trimSamples()
        save()
    }

    private func trimSamples() {
        let cutoff = Date().addingTimeInterval(-retention)
        samples.removeAll { $0.date < cutoff }
        if samples.count > sampleLimit {
            samples.removeFirst(samples.count - sampleLimit)
        }
    }

    private func trimSessions() {
        if sessions.count > 30 {
            sessions.removeLast(sessions.count - 30)
        }
    }

    private func clamp(_ level: Int) -> Int {
        min(100, max(0, level))
    }

    private func save() {
        let archive = BatteryArchive(
            samples: samples,
            sessions: sessions,
            activeCharge: activeChargeSession,
            lastLevelIncreaseAt: lastLevelIncreaseAt
        )
        let url = fileURL
        queue.async {
            let directory = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            guard let data = try? JSONEncoder().encode(archive) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let archive = try? JSONDecoder().decode(BatteryArchive.self, from: data)
        else { return }
        samples = archive.samples.sorted { $0.date < $1.date }
        sessions = archive.sessions.sorted { $0.startedAt > $1.startedAt }
        currentLevel = samples.last?.level
        lastSampleAt = samples.last?.date
        lastSampleLevel = samples.last?.level
        lastLevelIncreaseAt = archive.lastLevelIncreaseAt
        lastLevelReadAt = nil
        let lastSample = samples.last
        if lastSample?.chargeState == .charging {
            chargeState = .charging
            lastChargeStateAt = lastSample?.date
        } else {
            chargeState = .unknown
            lastChargeStateAt = nil
        }
        batteryAvailable = false
        connected = false
        if sessions.indices.contains(0), sessions[0].endedAt == nil {
            sessions[0].endedAt = lastSample?.date
            sessions[0].endLevel = lastSample?.level
        }
        if let charge = archive.activeCharge,
           let lastSampleAt = lastSample?.date,
           Date().timeIntervalSince(lastSampleAt) <= 60 * 60 {
            var restored = charge
            if let rise = restored.lastRiseAt {
                if Date().timeIntervalSince(rise)
                    <= chargeIdleWindow(for: lastSample?.level) + 30 {
                    activeChargeSession = restored
                }
            } else if lastSample?.chargeState == .charging,
                      Date().timeIntervalSince(lastSampleAt) <= 30 * 60 {
                restored.lastRiseAt = lastSampleAt
                activeChargeSession = restored
            }
        }
        restoreChargeSessionFromSamples()
    }

    private func restoreChargeSessionFromSamples() {
        guard let run = trailingChargeRun() else {
            guard let last = samples.last,
                  last.chargeState == .charging,
                  Date().timeIntervalSince(last.date)
                      <= chargeIdleWindow(for: last.level)
            else { return }
            var startIndex = samples.count - 1
            while startIndex > 0,
                  samples[startIndex - 1].chargeState == .charging {
                startIndex -= 1
            }
            if activeChargeSession == nil {
                activeChargeSession = BatteryChargeSession(
                    startedAt: samples[startIndex].date,
                    startLevel: samples[startIndex].level,
                    endLevel: last.level,
                    lastRiseAt: last.date
                )
                if lastLevelIncreaseAt == nil {
                    lastLevelIncreaseAt = last.date
                }
            }
            return
        }
        let start = samples[run.start]
        let lastRise = samples[run.lastRise]
        guard Date().timeIntervalSince(lastRise.date)
            <= chargeIdleWindow(for: samples.last?.level)
        else { return }

        if var charge = activeChargeSession {
            guard start.date < charge.startedAt else { return }
            charge.startedAt = start.date
            charge.startLevel = min(charge.startLevel ?? start.level, start.level)
            activeChargeSession = charge
        } else {
            activeChargeSession = BatteryChargeSession(
                startedAt: start.date,
                startLevel: start.level,
                endLevel: samples.last?.level,
                lastRiseAt: lastRise.date
            )
            if lastLevelIncreaseAt == nil {
                lastLevelIncreaseAt = lastRise.date
            }
        }
    }

    private func trailingChargeRun() -> (start: Int, lastRise: Int)? {
        guard samples.count > 1 else { return nil }
        var lastRise = -1
        for index in stride(from: samples.count - 1, through: 1, by: -1) {
            if samples[index].level > samples[index - 1].level {
                lastRise = index
                break
            }
        }
        guard lastRise > 0 else { return nil }

        var runStart = lastRise - 1
        var index = runStart
        var flatEnd: Date?
        while index > 0 {
            let current = samples[index]
            let previous = samples[index - 1]
            if current.level < previous.level { break }
            if current.level == previous.level {
                if flatEnd == nil { flatEnd = current.date }
                if let flatEnd,
                   flatEnd.timeIntervalSince(current.date) > 15 * 60 {
                    break
                }
            } else {
                flatEnd = nil
            }
            index -= 1
            runStart = index
        }
        return (runStart, lastRise)
    }

    public func seedPreview(charging: Bool = false, available: Bool = true) {
        let now = Date()
        func ago(_ hours: Double) -> Date {
            now.addingTimeInterval(-hours * 3600)
        }
        func agoMinutes(_ minutes: Double) -> Date {
            now.addingTimeInterval(-minutes * 60)
        }
        var data: [BatterySample] = [
            BatterySample(date: ago(24), level: 62, chargeState: .onBattery, active: false),
            BatterySample(date: ago(22), level: 60, chargeState: .onBattery, active: true),
            BatterySample(date: ago(19), level: 57, chargeState: .onBattery, active: false),
            BatterySample(date: ago(16), level: 53, chargeState: .onBattery, active: true),
            BatterySample(date: ago(14), level: 50, chargeState: .onBattery, active: false),
            BatterySample(date: ago(12.5), level: 48, chargeState: .onBattery, active: true),
            BatterySample(date: ago(12), level: 47, chargeState: .charging, active: false),
            BatterySample(date: ago(11.5), level: 54, chargeState: .charging, active: false),
            BatterySample(date: ago(11), level: 61, chargeState: .charging, active: false),
            BatterySample(date: ago(10.5), level: 65, chargeState: .charging, active: false),
            BatterySample(date: ago(10), level: 65, chargeState: .onBattery, active: true),
            BatterySample(date: ago(7), level: 60, chargeState: .onBattery, active: false),
            BatterySample(date: ago(4), level: 55, chargeState: .onBattery, active: true),
            BatterySample(date: ago(2), level: 51, chargeState: .onBattery, active: true),
            BatterySample(date: ago(1), level: 49, chargeState: .onBattery, active: false),
            BatterySample(date: now, level: 47, chargeState: .onBattery, active: true),
        ]
        if charging {
            data.append(contentsOf: [
                BatterySample(date: agoMinutes(4), level: 47, chargeState: .charging, active: false),
                BatterySample(date: agoMinutes(3), level: 48, chargeState: .charging, active: false),
                BatterySample(date: agoMinutes(2), level: 51, chargeState: .charging, active: false),
                BatterySample(date: agoMinutes(1), level: 53, chargeState: .charging, active: false),
            ])
        }
        data = data.sorted { $0.date < $1.date }
        samples = data
        sessions = [
            BatterySession(
                startedAt: ago(2),
                endedAt: nil,
                startLevel: 51,
                endLevel: charging ? 53 : 47
            ),
            BatterySession(
                startedAt: ago(10),
                endedAt: ago(2),
                startLevel: 65,
                endLevel: 51
            ),
        ]
        connected = true
        batteryAvailable = available
        lastLevelReadAt = available
            ? (charging ? agoMinutes(1) : now)
            : nil
        lastChargeStateAt = available ? now : nil
        lastActivityAt = now.addingTimeInterval(-20)
        if charging {
            currentLevel = 53
            chargeState = .charging
            lastLevelIncreaseAt = agoMinutes(1)
            lastSampleAt = agoMinutes(1)
            lastSampleLevel = 53
            activeChargeSession = BatteryChargeSession(
                startedAt: agoMinutes(5),
                startLevel: 47,
                endLevel: 53,
                lastRiseAt: agoMinutes(1)
            )
            isCharging = true
        } else {
            currentLevel = 47
            chargeState = .onBattery
            lastLevelIncreaseAt = ago(10.5)
            lastSampleAt = now
            lastSampleLevel = 47
            activeChargeSession = nil
            isCharging = false
        }
    }
}

private struct BatteryArchive: Codable {
    var samples: [BatterySample]
    var sessions: [BatterySession]
    var activeCharge: BatteryChargeSession?
    var lastLevelIncreaseAt: Date?
}
