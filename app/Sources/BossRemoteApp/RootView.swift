import AppKit
import BossRemoteCore
import BossRemoteUI
import Combine
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettings

    @State private var section: AppSection = .mapping
    @State private var mappingBundleID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("bossRemote.sidebarCollapsed") private var sidebarCollapsed =
        false
    @State private var contentWidth: CGFloat = 1280

    init(model: AppModel) {
        self._model = ObservedObject(wrappedValue: model)
        self._settings = ObservedObject(wrappedValue: model.settings)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarBackdrop()
                    .frame(width: sidebarCollapsed ? 68 : 204)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(BossTheme.hairline)
                            .frame(width: 1)
                    }
                BossBackground()
            }
            .ignoresSafeArea()

            HStack(spacing: 0) {
                SidebarView(
                    selection: $section,
                    connected: model.connected,
                    deviceName: model.deviceName,
                    voiceStatus: model.voiceStatus,
                    appVersion: appVersion,
                    profileCount: model.appProfileCount,
                    collapsed: sidebarCollapsed,
                    onToggle: {
                        withAnimation(
                            reduceMotion
                                ? nil
                                : .spring(response: 0.38, dampingFraction: 0.86)
                        ) {
                            sidebarCollapsed.toggle()
                        }
                    }
                )

                VStack(spacing: 0) {
                    if !model.hasAccessibility || !model.hasInputMonitoring {
                        permissionBanner
                    }
                    page
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { contentWidth = proxy.size.width }
                            .onChange(of: proxy.size.width) { _, width in
                                contentWidth = width
                            }
                    }
                }
                .environment(\.bossCompact, contentWidth < 1000)
            }
            .frame(minWidth: 820, minHeight: 540)
        }
        .frame(minWidth: 820, minHeight: 540)
        .background(WindowAccessor())
        .preferredColorScheme(
            AppAppearance.colorScheme(for: settings.appearance)
        )
        .onAppear {
            AppAppearance.apply(settings.appearance)
        }
        .onChange(of: settings.appearance) { _, preference in
            AppAppearance.apply(preference)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            model.refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.willTerminateNotification
        )) { _ in
            model.stop()
        }
    }

    @ViewBuilder
    private var page: some View {
        switch section {
        case .mapping:
            MappingContentView(
                store: model.mapping,
                selected: $model.selectedControl,
                active: model.activeControls,
                connected: model.connected,
                battery: model.battery,
                batteryAvailable: model.batteryInsights.batteryAvailable,
                charging: model.isCharging,
                status: model.status,
                voiceStatus: model.voiceStatus,
                scopeBundleID: mappingScope,
                onManageApps: { section = .apps },
                touchIndicator: model.touchIndicator
            )
        case .apps:
            AppAdaptationView(model: model) { bundleID in
                mappingBundleID = bundleID
                section = .mapping
            }
        case .connection:
            ConnectionView(model: model)
        case .history:
            HistoryView(
                model: model,
                history: model.history,
                settings: model.settings
            )
        case .settings:
            SettingsView(model: model, settings: model.settings)
        }
    }

    private var mappingScope: Binding<String?> {
        Binding(
            get: {
                guard let bundleID = mappingBundleID,
                      model.mapping.profile(for: bundleID) != nil
                else {
                    return nil
                }
                return bundleID
            },
            set: { mappingBundleID = $0 }
        )
    }

    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BossTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("还需要系统权限", "System permission required"))
                    .font(BossTheme.label(11.5, weight: .semibold))
                    .foregroundStyle(BossTheme.text)
                Text(L10n.t(
                    "辅助功能用于移动鼠标和发送按键；输入监控用于读取遥控器。",
                    "Accessibility moves the pointer and sends keys; Input Monitoring reads the remote."
                ))
                .font(BossTheme.label(10.5))
                .foregroundStyle(BossTheme.tertiary)
            }
            Spacer(minLength: 12)
            if !model.hasAccessibility {
                permissionButton(
                    L10n.t("授予辅助功能", "Grant Accessibility"),
                    action: model.requestAccessibility
                )
            }
            if !model.hasInputMonitoring {
                permissionButton(
                    L10n.t("授予输入监控", "Grant Input Monitoring"),
                    action: model.requestInputMonitoring
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(BossTheme.accent.opacity(0.07))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BossTheme.hairline)
                .frame(height: 1)
        }
    }

    private func permissionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(BossTheme.label(10.5, weight: .medium))
                .foregroundStyle(BossTheme.text)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(BossTheme.controlFillHover))
                .overlay(Capsule().stroke(BossTheme.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

