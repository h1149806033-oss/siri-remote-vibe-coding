import AppKit
import BossRemoteCore
import BossRemoteUI
import SwiftUI
import UniformTypeIdentifiers

private struct RunningApp: Identifiable {
    let bundleID: String
    let name: String

    var id: String { bundleID }
}

struct AppAdaptationView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var mapping: MappingStore
    private let preview: Bool
    let onOpenMapping: (String?) -> Void

    @State private var addPickerOpen = false
    @State private var pendingRemoval: AppProfile?
    @State private var hoveredProfile: String?
    @Environment(\.bossCompact) private var compact

    init(
        model: AppModel,
        preview: Bool = false,
        onOpenMapping: @escaping (String?) -> Void
    ) {
        self._model = ObservedObject(wrappedValue: model)
        self._mapping = ObservedObject(wrappedValue: model.mapping)
        self.preview = preview
        self.onOpenMapping = onOpenMapping
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if preview {
                columns
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    columns
                }
            }
        }
        .padding(.horizontal, BossMetrics.pageHorizontal)
        .padding(.top, BossMetrics.pageTop)
        .padding(.bottom, BossMetrics.pageBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert(
            L10n.t("移除 App 适配？", "Remove app mapping?"),
            isPresented: preview
                ? .constant(false)
                : Binding(
                    get: { pendingRemoval != nil },
                    set: { if !$0 { pendingRemoval = nil } }
                )
        ) {
            Button(L10n.t("移除", "Remove"), role: .destructive) {
                if let profile = pendingRemoval {
                    mapping.removeProfile(bundleID: profile.bundleID)
                }
                pendingRemoval = nil
            }
            Button(L10n.t("取消", "Cancel"), role: .cancel) {
                pendingRemoval = nil
            }
        } message: {
            Text(L10n.t(
                "\(pendingRemoval?.displayName ?? "") 将回落到全局映射。",
                "\(pendingRemoval?.displayName ?? "") will fall back to the global mapping."
            ))
        }
    }

    private var columns: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 30) {
                    activeAppSection
                    profilesSection
                    globalSection
                    rulesSection
                }
            } else {
                HStack(alignment: .top, spacing: 36) {
                    VStack(alignment: .leading, spacing: 30) {
                        activeAppSection
                        profilesSection
                    }
                    VStack(alignment: .leading, spacing: 30) {
                        globalSection
                        rulesSection
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        BossPageHeader(
            title: L10n.t("APP 适配", "App Mappings"),
            subtitle: L10n.t(
                "前台 App 自动切换；未覆盖的按键回落到全局",
                "Switch automatically by frontmost app; unset keys fall back to global"
            )
        ) {
            BossPillButton(action: {
                withAnimation(.snappy(duration: 0.20)) {
                    addPickerOpen.toggle()
                }
            }) {
                Label(L10n.t("添加 App", "Add app"), systemImage: "plus")
                    .font(BossTheme.label(9.5, weight: .medium))
                    .foregroundStyle(BossTheme.secondary)
            }
            .popover(isPresented: $addPickerOpen, arrowEdge: .top) {
                addPicker
            }
        }
    }

    private var activeAppSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            BossSectionHeader(
                icon: "scope",
                title: L10n.t("最近前台 App", "Recent front app")
            ) {
                if let bundleID = model.frontmostBundleID {
                    Text(
                        mapping.profile(for: bundleID) == nil
                            ? L10n.t("全局映射", "Global")
                            : L10n.t("专属映射", "App mapping")
                    )
                    .font(BossTheme.label(9.5, weight: .semibold))
                    .foregroundStyle(
                        mapping.profile(for: bundleID) == nil
                            ? BossTheme.tertiary
                            : BossTheme.accent
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(
                            mapping.profile(for: bundleID) == nil
                                ? BossTheme.controlFill
                                : BossTheme.accent.opacity(0.10)
                        )
                    )
                }
            }

            if let bundleID = model.frontmostBundleID {
                HStack(spacing: 13) {
                    appIcon(bundleID, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.frontmostAppName ?? bundleID)
                            .font(BossTheme.label(15, weight: .semibold))
                            .foregroundStyle(BossTheme.text)
                            .lineLimit(1)
                        Text(bundleID)
                            .font(BossTheme.mono(9.5))
                            .foregroundStyle(BossTheme.tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if let profile = mapping.profile(for: bundleID) {
                        actionButton(L10n.t("编辑映射", "Edit"), accent: true) {
                            onOpenMapping(profile.bundleID)
                        }
                    } else {
                        actionButton(L10n.t("创建专属映射", "Create mapping"), accent: true) {
                            addApp(
                                bundleID: bundleID,
                                name: model.frontmostAppName ?? bundleID
                            )
                        }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(BossTheme.tertiary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("还没有检测到前台 App", "No front app detected"))
                            .font(BossTheme.label(12.5, weight: .medium))
                            .foregroundStyle(BossTheme.text)
                        Text(L10n.t(
                            "切换到其他 App 后这里会自动更新。",
                            "Switch to another app and this updates automatically."
                        ))
                        .font(BossTheme.label(10.5))
                        .foregroundStyle(BossTheme.tertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BossSectionHeader(
                icon: "square.grid.2x2",
                title: L10n.t("App 专属映射", "App mappings")
            ) {
                Text("\(mapping.profileList.count)")
                    .font(BossTheme.mono(9.5, weight: .medium))
                    .foregroundStyle(BossTheme.tertiary)
            }

            if mapping.profileList.isEmpty {
                emptyProfiles
            } else {
                VStack(spacing: 0) {
                    ForEach(mapping.profileList) { profile in
                        profileRow(profile)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyProfiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("还没有 App 专属映射", "No app mappings yet"))
                .font(BossTheme.label(12, weight: .medium))
                .foregroundStyle(BossTheme.secondary)
            Text(L10n.t(
                "添加一个 App，只为它覆盖需要变化的按键；其他按键继续使用全局。",
                "Add an app and override only the keys that should differ; the rest stay global."
            ))
            .font(BossTheme.label(10.5))
            .foregroundStyle(BossTheme.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            Button {
                addPickerOpen = true
            } label: {
                Label(L10n.t("添加 App", "Add app"), systemImage: "plus")
                    .font(BossTheme.label(10, weight: .medium))
                    .foregroundStyle(BossTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(BossTheme.accent.opacity(0.10)))
                    .overlay(Capsule().stroke(BossTheme.accent.opacity(0.22), lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func profileRow(_ profile: AppProfile) -> some View {
        let isActive = profile.bundleID == model.frontmostBundleID
        let isHovered = hoveredProfile == profile.bundleID
        return HStack(spacing: 8) {
            Button {
                onOpenMapping(profile.bundleID)
            } label: {
                HStack(spacing: 11) {
                    appIcon(profile.bundleID, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(profile.displayName)
                                .font(BossTheme.label(12.5, weight: .medium))
                                .foregroundStyle(BossTheme.text)
                                .lineLimit(1)
                            if isActive {
                                Circle()
                                    .fill(BossTheme.success)
                                    .frame(width: 4.5, height: 4.5)
                                    .shadow(color: BossTheme.success.opacity(0.6), radius: 3)
                            }
                        }
                        Text(L10n.t(
                            "\(profile.overrideCount) 个覆盖",
                            profile.overrideCount == 1
                                ? "1 override"
                                : "\(profile.overrideCount) overrides"
                        ))
                        .font(BossTheme.label(9.5))
                        .foregroundStyle(BossTheme.tertiary)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(BossTheme.tertiary.opacity(0.6))
                }
                .padding(.horizontal, 10)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isHovered ? BossTheme.controlFill : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    if hovering {
                        hoveredProfile = profile.bundleID
                    } else if hoveredProfile == profile.bundleID {
                        hoveredProfile = nil
                    }
                }
            }

            Button {
                pendingRemoval = profile
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BossTheme.tertiary)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(L10n.t("移除 App 适配", "Remove app mapping"))
            .accessibilityLabel(L10n.t("移除 App 适配", "Remove app mapping"))
        }
        .overlay(alignment: .bottom) {
            BossRule(opacity: 0.6)
                .padding(.leading, 48)
        }
    }

    private var globalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BossSectionHeader(
                icon: "globe",
                title: L10n.t("全局映射", "Global mapping")
            )
            Text(L10n.t(
                "所有没有单独配置按键的 App 都使用这一套。",
                "Every key not overridden by an app uses this set."
            ))
            .font(BossTheme.label(10.5))
            .foregroundStyle(BossTheme.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(L10n.t(
                    "\(globalCustomCount) 个自定义",
                    "\(globalCustomCount) custom"
                ))
                .font(BossTheme.label(10))
                .foregroundStyle(BossTheme.tertiary)
                Spacer()
                actionButton(L10n.t("编辑全局", "Edit global"), accent: false) {
                    onOpenMapping(nil)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            BossSectionHeader(
                icon: "arrow.triangle.branch",
                title: L10n.t("自动切换规则", "Switching rules")
            )
            VStack(alignment: .leading, spacing: 14) {
                ruleRow(
                    index: "1",
                    text: L10n.t(
                        "前台 App 有专属配置时，优先使用它的覆盖。",
                        "If the front app has a mapping, use its overrides first."
                    )
                )
                ruleRow(
                    index: "2",
                    text: L10n.t(
                        "没有覆盖的按键自动回落到全局映射。",
                        "Keys without an override fall back to global."
                    )
                )
                ruleRow(
                    index: "3",
                    text: L10n.t(
                        "切换 App 时自动生效，不需要手动切换。",
                        "It applies automatically when you switch apps."
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ruleRow(index: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(index)
                .font(BossTheme.mono(9, weight: .semibold))
                .foregroundStyle(BossTheme.accent)
                .frame(width: 17, height: 17)
                .background(Circle().fill(BossTheme.accent.opacity(0.10)))
            Text(text)
                .font(BossTheme.label(10.5))
                .foregroundStyle(BossTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var addPicker: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.t("添加 App", "Add app"))
                .font(BossTheme.label(9.5, weight: .semibold))
                .foregroundStyle(BossTheme.tertiary)
                .padding(.horizontal, 9)
                .padding(.top, 4)

            if runnableApps.isEmpty {
                Text(L10n.t(
                    "没有可添加的运行中 App",
                    "No running apps to add"
                ))
                .font(BossTheme.label(10))
                .foregroundStyle(BossTheme.tertiary)
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(runnableApps) { app in
                            Button {
                                addApp(bundleID: app.bundleID, name: app.name)
                            } label: {
                                HStack(spacing: 9) {
                                    appIcon(app.bundleID, size: 22)
                                    Text(app.name)
                                        .font(BossTheme.label(10.5, weight: .medium))
                                        .foregroundStyle(BossTheme.text)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }

            Rectangle()
                .fill(BossTheme.hairline)
                .frame(height: 1)
                .padding(.vertical, 3)

            Button {
                addPickerOpen = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    chooseApp()
                }
            } label: {
                Label(L10n.t("选择 App…", "Choose app…"), systemImage: "folder")
                    .font(BossTheme.label(10, weight: .medium))
                    .foregroundStyle(BossTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .frame(width: 320)
        .background(BossTheme.background)
    }

    private var runnableApps: [RunningApp] {
        var seen = Set<String>()
        var result: [RunningApp] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier,
                  mapping.profile(for: bundleID) == nil,
                  seen.insert(bundleID).inserted
            else { continue }
            result.append(RunningApp(
                bundleID: bundleID,
                name: app.localizedName ?? bundleID
            ))
        }
        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var globalCustomCount: Int {
        RemoteControl.allCases.filter {
            mapping.action(for: $0) != $0.defaultAction
        }.count
    }

    private func addApp(bundleID: String, name: String) {
        mapping.ensureProfile(bundleID: bundleID, displayName: name)
        addPickerOpen = false
        onOpenMapping(bundleID)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L10n.t("选择", "Choose")
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier
        else { return }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        addApp(bundleID: bundleID, name: name)
    }

    private func actionButton(
        _ title: String,
        accent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(BossTheme.label(10, weight: .medium))
                .foregroundStyle(accent ? BossTheme.accent : BossTheme.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        accent
                            ? BossTheme.accent.opacity(0.10)
                            : BossTheme.controlFill
                    )
                )
                .overlay(
                    Capsule().stroke(
                        accent
                            ? BossTheme.accent.opacity(0.22)
                            : BossTheme.hairline,
                        lineWidth: 1
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func appIcon(_ bundleID: String, size: CGFloat) -> some View {
        Group {
            if let image = AppIconRenderer.shared.image(for: bundleID) {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(BossTheme.tertiary)
                    .padding(3)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

@MainActor
private final class AppIconRenderer {
    static let shared = AppIconRenderer()

    private var cache: [String: CGImage] = [:]

    func image(for bundleID: String) -> CGImage? {
        if let cached = cache[bundleID] {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleID
        ) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 96,
            pixelsHigh: 96,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: 48, height: 48)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        icon.draw(in: NSRect(x: 0, y: 0, width: 48, height: 48))
        NSGraphicsContext.restoreGraphicsState()
        guard let cgImage = rep.cgImage else { return nil }
        cache[bundleID] = cgImage
        return cgImage
    }
}
