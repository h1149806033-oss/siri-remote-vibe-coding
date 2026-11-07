import Combine
import Foundation

public struct VoiceDay: Codable, Identifiable, Equatable, Sendable {
    public var day: Date
    public var duration: TimeInterval
    public var sessions: Int

    public var id: Date { day }

    public init(
        day: Date,
        duration: TimeInterval = 0,
        sessions: Int = 0
    ) {
        self.day = day
        self.duration = duration
        self.sessions = sessions
    }
}

public final class VoiceStatsStore: ObservableObject {
    @Published public private(set) var days: [VoiceDay] = []

    private let fileURL: URL
    private let queue = DispatchQueue(
        label: "com.bossremote.voicestats",
        qos: .utility
    )
    private let retention: TimeInterval = 90 * 24 * 60 * 60

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL(
                fileURLWithPath: NSTemporaryDirectory(),
                isDirectory: true
            )
            self.fileURL = base
                .appendingPathComponent("BossRemote", isDirectory: true)
                .appendingPathComponent("voice-stats.json", isDirectory: false)
        }
        load()
    }

    public func record(duration: TimeInterval, at date: Date = Date()) {
        guard duration > 0 else { return }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        if let index = days.firstIndex(where: {
            calendar.isDate($0.day, inSameDayAs: day)
        }) {
            days[index].duration += duration
            days[index].sessions += 1
        } else {
            days.append(VoiceDay(day: day, duration: duration, sessions: 1))
            days.sort { $0.day < $1.day }
        }
        trim()
        save()
    }

    public func total(on date: Date = Date()) -> TimeInterval {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        return days.first(where: {
            calendar.isDate($0.day, inSameDayAs: day)
        })?.duration ?? 0
    }

    public func sessions(on date: Date = Date()) -> Int {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        return days.first(where: {
            calendar.isDate($0.day, inSameDayAs: day)
        })?.sessions ?? 0
    }

    public func recentDays(
        _ count: Int,
        endingAt date: Date = Date()
    ) -> [VoiceDay] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: date)
        return (0..<max(1, count)).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: end)
                ?? end
            return days.first(where: {
                calendar.isDate($0.day, inSameDayAs: day)
            }) ?? VoiceDay(day: day)
        }
    }

    public func total(days count: Int, endingAt date: Date = Date()) -> TimeInterval {
        recentDays(count, endingAt: date).reduce(0) { $0 + $1.duration }
    }

    public func backfillIfNeeded(from events: [ActivityEvent]) {
        guard days.isEmpty else { return }
        let calendar = Calendar.current
        for event in events where event.kind == .voice {
            guard let duration = event.duration, duration > 0 else {
                continue
            }
            let day = calendar.startOfDay(for: event.date)
            if let index = days.firstIndex(where: {
                calendar.isDate($0.day, inSameDayAs: day)
            }) {
                days[index].duration += duration
                days[index].sessions += 1
            } else {
                days.append(VoiceDay(
                    day: day,
                    duration: duration,
                    sessions: 1
                ))
            }
        }
        guard !days.isEmpty else { return }
        days.sort { $0.day < $1.day }
        trim()
        save()
    }

    public func clear() {
        guard !days.isEmpty else { return }
        days = []
        save()
    }

    public func seedPreview() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let samples: [(offset: Int, duration: TimeInterval, sessions: Int)] = [
            (-6, 249, 61),
            (-5, 344, 78),
            (-4, 229, 54),
            (-3, 379, 86),
            (-2, 326, 74),
            (-1, 319, 82),
            (0, 449, 110),
        ]
        days = samples.compactMap { sample in
            guard let day = calendar.date(
                byAdding: .day,
                value: sample.offset,
                to: today
            ) else { return nil }
            return VoiceDay(
                day: day,
                duration: sample.duration,
                sessions: sample.sessions
            )
        }
        save()
    }

    private func trim() {
        let calendar = Calendar.current
        let cutoff = calendar.startOfDay(
            for: Date().addingTimeInterval(-retention)
        )
        days.removeAll { $0.day < cutoff }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(
                  [VoiceDay].self,
                  from: data
              )
        else { return }
        days = decoded.sorted { $0.day < $1.day }
        trim()
    }

    private func save() {
        let snapshot = days
        let url = fileURL
        queue.async {
            let directory = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            guard let data = try? JSONEncoder().encode(snapshot) else {
                return
            }
            try? data.write(to: url, options: .atomic)
        }
    }
}
