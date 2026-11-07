import Combine
import Foundation

public struct ActivityEvent: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case button
        case voice
        case mapping
        case app
    }

    public let id: UUID
    public var date: Date
    public var kind: Kind
    public var control: RemoteControl?
    public var actionLabel: String?
    public var appName: String?
    public var bundleID: String?
    public var scopeLabel: String?
    public var duration: TimeInterval?
    public var frames: Int?
    public var count: Int
    public var detail: String?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: Kind,
        control: RemoteControl? = nil,
        actionLabel: String? = nil,
        appName: String? = nil,
        bundleID: String? = nil,
        scopeLabel: String? = nil,
        duration: TimeInterval? = nil,
        frames: Int? = nil,
        count: Int = 1,
        detail: String? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.control = control
        self.actionLabel = actionLabel
        self.appName = appName
        self.bundleID = bundleID
        self.scopeLabel = scopeLabel
        self.duration = duration
        self.frames = frames
        self.count = count
        self.detail = detail
    }
}

public final class HistoryStore: ObservableObject {
    @Published public private(set) var events: [ActivityEvent] = []

    private let fileURL: URL
    private let limit: Int
    private let queue = DispatchQueue(
        label: "com.bossremote.history",
        qos: .utility
    )

    public init(fileURL: URL? = nil, limit: Int = 300) {
        self.limit = max(20, limit)
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.fileURL = base
                .appendingPathComponent("BossRemote", isDirectory: true)
                .appendingPathComponent("history.json", isDirectory: false)
        }
        load()
    }

    public func record(_ event: ActivityEvent) {
        if let last = events.first,
           last.kind == .button,
           event.kind == .button,
           last.control == event.control,
           last.bundleID == event.bundleID,
           last.actionLabel == event.actionLabel,
           event.date.timeIntervalSince(last.date) < 0.7 {
            var merged = last
            merged.date = event.date
            merged.count += 1
            events[0] = merged
        } else {
            events.insert(event, at: 0)
        }
        if events.count > limit {
            events.removeLast(events.count - limit)
        }
        save()
    }

    public func clear() {
        guard !events.isEmpty else { return }
        events.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ActivityEvent].self, from: data)
        else { return }
        let sorted = decoded.sorted { $0.date > $1.date }
        events = Array(sorted.prefix(limit))
    }

    private func save() {
        let snapshot = Array(events.prefix(limit))
        let url = fileURL
        queue.async {
            let directory = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: [.atomic])
        }
    }
}
