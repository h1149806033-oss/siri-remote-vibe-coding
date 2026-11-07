import SwiftUI

public enum BossMetrics {
    public static let pageHorizontal: CGFloat = 32
    public static let pageTop: CGFloat = 24
    public static let pageBottom: CGFloat = 28
    public static let sectionSpacing: CGFloat = 28
}

public struct BossPageHeader<Trailing: View>: View {
    private let title: String
    private let subtitle: String
    private let trailing: Trailing

    public init(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(BossTheme.display(22, weight: .bold))
                    .foregroundStyle(BossTheme.text)
                Text(subtitle)
                    .font(BossTheme.label(11))
                    .foregroundStyle(BossTheme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 16)
            trailing
        }
    }
}

public extension BossPageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

public struct BossSectionHeader<Trailing: View>: View {
    private let icon: String
    private let title: String
    private let detail: String?
    private let trailing: Trailing

    public init(
        icon: String,
        title: String,
        detail: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BossTheme.accent)
                .frame(width: 14)
            Text(title)
                .font(BossTheme.display(14.5, weight: .semibold))
                .foregroundStyle(BossTheme.text)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(BossTheme.label(9.5))
                    .foregroundStyle(BossTheme.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

public extension BossSectionHeader where Trailing == EmptyView {
    init(icon: String, title: String, detail: String? = nil) {
        self.init(icon: icon, title: title, detail: detail) {
            EmptyView()
        }
    }
}

public struct BossRule: View {
    private let opacity: Double

    public init(opacity: Double = 1) {
        self.opacity = opacity
    }

    public var body: some View {
        Rectangle()
            .fill(BossTheme.hairline.opacity(opacity))
            .frame(height: 1)
    }
}

public struct BossSeparator: View {
    public init() {}

    public var body: some View {
        RoundedRectangle(cornerRadius: 0.5, style: .continuous)
            .fill(BossTheme.separator)
            .frame(width: 1, height: 10)
    }
}

private struct BossCompactKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var bossCompact: Bool {
        get { self[BossCompactKey.self] }
        set { self[BossCompactKey.self] = newValue }
    }
}
