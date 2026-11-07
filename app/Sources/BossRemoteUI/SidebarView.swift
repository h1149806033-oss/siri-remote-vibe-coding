import BossRemoteCore
import SwiftUI

public struct SidebarBackdrop: View {
    public init() {}

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    BossTheme.backgroundLift,
                    BossTheme.background,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [
                    BossTheme.sidebarWash,
                    .clear,
                ],
                center: .init(x: 0.5, y: 0.0),
                startRadius: 10,
                endRadius: 260
            )
        }
    }
}

public struct SidebarView: View {
    @Binding private var selection: AppSection
    private let connected: Bool
    private let deviceName: String?
    private let voiceStatus: String
    private let appVersion: String
    private let profileCount: Int
    private let collapsed: Bool
    private let onToggle: () -> Void

    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var collapseHovered = false

    public init(
        selection: Binding<AppSection>,
        connected: Bool,
        deviceName: String?,
        voiceStatus: String,
        appVersion: String,
        profileCount: Int = 0,
        collapsed: Bool = false,
        onToggle: @escaping () -> Void = {}
    ) {
        self._selection = selection
        self.connected = connected
        self.deviceName = deviceName
        self.voiceStatus = voiceStatus
        self.appVersion = appVersion
        self.profileCount = profileCount
        self.collapsed = collapsed
        self.onToggle = onToggle
    }

    public var body: some View {
        VStack(alignment: collapsed ? .center : .leading, spacing: 0) {
            brand
            navigation
            Spacer(minLength: 16)
            statusCard
        }
        .padding(.horizontal, collapsed ? 8 : 12)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(width: collapsed ? 68 : 204)
        .frame(maxHeight: .infinity)
        .animation(
            reduceMotion
                ? nil
                : .spring(response: 0.38, dampingFraction: 0.86),
            value: collapsed
        )
    }

    private var brand: some View {
        Group {
            if collapsed {
                VStack(spacing: 8) {
                    collapseButton
                    BossMark(size: 34)
                        .accessibilityLabel("Boss Remote")
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 10) {
                    BossMark(size: 42)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Boss Remote")
                            .font(BossTheme.display(16, weight: .bold))
                            .foregroundStyle(BossTheme.text)
                            .lineLimit(1)
                        Text("v\(appVersion)")
                            .font(BossTheme.mono(9, weight: .medium))
                            .foregroundStyle(BossTheme.tertiary)
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                    collapseButton
                }
                .padding(.horizontal, 6)
            }
        }
        .transition(.opacity)
    }

    private var collapseButton: some View {
        Button(action: onToggle) {
            Image(systemName: "chevron.left")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(
                    collapseHovered ? BossTheme.accent : BossTheme.secondary
                )
                .rotationEffect(.degrees(collapsed ? 180 : 0))
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(
                        collapseHovered
                            ? BossTheme.surfaceRaised
                            : BossTheme.surface
                    )
                )
                .overlay(Circle().stroke(BossTheme.hairline, lineWidth: 1))
                .shadow(color: BossTheme.objectShadowSoft, radius: 3, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(BossPressButtonStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                collapseHovered = hovering
            }
        }
        .help(collapsed
            ? L10n.t("展开侧栏", "Expand sidebar")
            : L10n.t("收起侧栏", "Collapse sidebar"))
        .accessibilityLabel(collapsed
            ? L10n.t("展开侧栏", "Expand sidebar")
            : L10n.t("收起侧栏", "Collapse sidebar"))
    }

    private var navigation: some View {
        VStack(spacing: collapsed ? 6 : 4) {
            ForEach(AppSection.allCases) { section in
                SidebarRow(
                    section: section,
                    selected: selection == section,
                    count: section == .apps ? profileCount : nil,
                    collapsed: collapsed,
                    namespace: selectionNamespace
                ) {
                    withAnimation(
                        reduceMotion
                            ? nil
                            : .spring(response: 0.34, dampingFraction: 0.86)
                    ) {
                        selection = section
                    }
                }
            }
        }
        .padding(.top, collapsed ? 20 : 24)
    }

    @ViewBuilder
    private var statusCard: some View {
        if collapsed {
            VStack(spacing: 11) {
                Circle()
                    .fill(connected ? BossTheme.success : BossTheme.tertiary)
                    .frame(width: 6, height: 6)
                    .shadow(
                        color: connected
                            ? BossTheme.success.opacity(0.6)
                            : .clear,
                        radius: 4
                    )
                    .help(connected
                        ? (deviceName ?? "Siri Remote")
                        : L10n.t("等待遥控器", "Waiting for remote"))
                    .accessibilityLabel(connected
                        ? (deviceName ?? "Siri Remote")
                        : L10n.t("等待遥控器", "Waiting for remote"))
                Image(systemName: "waveform")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(BossTheme.accent)
                    .help(voiceStatus)
                    .accessibilityLabel(voiceStatus)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(statusBackground)
            .overlay(statusBorder)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(connected ? BossTheme.success : BossTheme.tertiary)
                        .frame(width: 6, height: 6)
                        .shadow(
                            color: connected
                                ? BossTheme.success.opacity(0.6)
                                : .clear,
                            radius: 4
                        )
                    Text(
                        connected
                            ? (deviceName ?? L10n.t("Siri Remote", "Siri Remote"))
                            : L10n.t("等待遥控器", "Waiting for remote")
                    )
                    .font(BossTheme.label(11, weight: .medium))
                    .foregroundStyle(BossTheme.secondary)
                    .lineLimit(1)
                    Spacer(minLength: 4)
                }

                HStack(spacing: 7) {
                    Image(systemName: "waveform")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(BossTheme.accent)
                    Text(voiceStatus)
                        .font(BossTheme.label(10))
                        .foregroundStyle(BossTheme.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(voiceStatus)
                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            .background(statusBackground)
            .overlay(statusBorder)
        }
    }

    private var statusBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(BossTheme.surface.opacity(0.68))
    }

    private var statusBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(BossTheme.hairline, lineWidth: 1)
    }
}

private struct SidebarRow: View {
    let section: AppSection
    let selected: Bool
    let count: Int?
    let collapsed: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            content
                .frame(height: collapsed ? 40 : 36)
                .background {
                    if selected {
                        selectionBackground
                            .matchedGeometryEffect(
                                id: "sidebar.selection",
                                in: namespace
                            )
                    } else {
                        RoundedRectangle(
                            cornerRadius: collapsed ? 11 : 9,
                            style: .continuous
                        )
                        .fill(
                            hovered
                                ? BossTheme.controlFill
                                : Color.clear
                        )
                    }
                }
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: collapsed ? 11 : 9,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(BossPressButtonStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hovered = hovering
            }
        }
        .help(section.title)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var content: some View {
        HStack(spacing: 10) {
            Image(systemName: section.symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 18)
                .foregroundStyle(
                    selected
                        ? BossTheme.accentBright
                        : BossTheme.secondary
                )
                .overlay(alignment: .topTrailing) {
                    if collapsed, let count, count > 0 {
                        Circle()
                            .fill(BossTheme.accent)
                            .frame(width: 4, height: 4)
                            .offset(x: 3, y: -3)
                    }
                }
            if !collapsed {
                Text(section.title)
                    .font(BossTheme.label(
                        12.5,
                        weight: selected ? .semibold : .medium
                    ))
                    .foregroundStyle(
                        selected
                            ? BossTheme.text
                            : BossTheme.text.opacity(0.68)
                    )
                Spacer(minLength: 4)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(BossTheme.mono(8.5, weight: .semibold))
                        .foregroundStyle(
                            selected
                                ? BossTheme.accent
                                : BossTheme.tertiary
                        )
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                selected
                                    ? BossTheme.accent.opacity(0.10)
                                    : BossTheme.controlFill
                            )
                        )
                }
            }
        }
        .padding(.horizontal, collapsed ? 0 : 10)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: collapsed ? .center : .leading
        )
    }

    private var selectionBackground: some View {
        RoundedRectangle(
            cornerRadius: collapsed ? 11 : 9,
            style: .continuous
        )
        .fill(BossTheme.accent.opacity(0.11))
        .overlay(
            RoundedRectangle(
                cornerRadius: collapsed ? 11 : 9,
                style: .continuous
            )
            .stroke(
                BossTheme.accent.opacity(0.18),
                lineWidth: 0.8
            )
        )
    }
}
