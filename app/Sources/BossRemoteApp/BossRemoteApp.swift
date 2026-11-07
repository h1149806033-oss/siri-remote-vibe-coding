import AppKit
import BossRemoteCore
import BossRemoteUI
import SwiftUI

@main
struct BossRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Boss Remote", id: "main") {
            RootView(model: model)
                .task {
                    model.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 860)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarMenu(model: model)
        } label: {
            Image(
                systemName: model.connected
                    ? "appletvremote.gen3.fill"
                    : "appletvremote.gen3"
            )
            .onAppear {
                model.noteDiagnostic("menu bar extra ready")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
private struct MenuBarMenu: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusLine)
        if let battery = model.battery {
            Text(L10n.t("电量 \(battery)%", "Battery \(battery)%"))
        }
        Divider()
        Button(L10n.t("打开 Boss Remote", "Open Boss Remote")) {
            openWindow(id: "main")
            NSApp.activate()
        }
        Button(L10n.t("重新检测", "Recheck")) {
            model.refreshDiagnostics()
        }
        Divider()
        Button(L10n.t("退出 Boss Remote", "Quit Boss Remote")) {
            NSApp.terminate(nil)
        }
    }

    private var statusLine: String {
        if model.connected {
            let name = model.deviceName ?? "Siri Remote"
            return L10n.t("已连接，\(name)", "Connected, \(name)")
        }
        return L10n.t("等待 Siri Remote", "Waiting for Siri Remote")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let snapshotAppearance = ProcessInfo.processInfo.environment[
            "BOSS_REMOTE_SNAPSHOT_APPEARANCE"
        ].flatMap(AppearancePreference.init(rawValue:))
        AppAppearance.apply(
            snapshotAppearance ?? AppSettings.storedAppearance()
        )
        if SnapshotRenderer.renderIfRequested() {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        configureWindows()
        DispatchQueue.main.async { [weak self] in
            self?.configureWindows()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    private func configureWindows() {
        for window in NSApp.windows {
            AppWindowStyler.configure(window)
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        AppWindowStyler.configure(window)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            sender.windows.first { $0.title == "Boss Remote" }?
                .makeKeyAndOrderFront(nil)
        }
        return true
    }
}

@MainActor
enum AppAppearance {
    static func apply(_ preference: AppearancePreference) {
        let appearance: NSAppearance?
        switch preference {
        case .system:
            appearance = nil
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }
        NSApp.appearance = appearance
        for window in NSApp.windows {
            window.appearance = appearance
        }
    }

    static func colorScheme(
        for preference: AppearancePreference
    ) -> ColorScheme? {
        switch preference {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
enum AppWindowStyler {
    static func configure(_ window: NSWindow) {
        guard window.styleMask.contains(.titled),
              !window.isSheet,
              !(window is NSPanel),
              window.title == "Boss Remote"
        else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = BossTheme.backgroundNS
        window.isMovableByWindowBackground = true
    }
}

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            AppWindowStyler.configure(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            AppWindowStyler.configure(window)
        }
    }
}
