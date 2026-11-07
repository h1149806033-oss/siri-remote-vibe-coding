import AppKit
import Combine
import Foundation

@MainActor
final class FrontmostAppMonitor: ObservableObject {
    @Published private(set) var bundleID: String?
    @Published private(set) var name: String?

    private var token: NSObjectProtocol?

    init() {
        update(NSWorkspace.shared.frontmostApplication)
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor [weak self] in
                self?.update(app)
            }
        }
    }

    deinit {
        if let token {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }

    func refresh() {
        update(NSWorkspace.shared.frontmostApplication)
    }

    private func update(_ app: NSRunningApplication?) {
        guard let app,
              let id = app.bundleIdentifier,
              id != Bundle.main.bundleIdentifier
        else { return }
        if bundleID != id {
            name = app.localizedName
            bundleID = id
        }
    }
}
