import AppKit
import SwiftUI

public enum BossTheme {
    private static func rgba(
        _ red: CGFloat,
        _ green: CGFloat,
        _ blue: CGFloat,
        _ alpha: CGFloat = 1
    ) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    private static func dynamicNSColor(
        light: NSColor,
        dark: NSColor
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua])
                == .darkAqua
            return isDark ? dark : light
        }
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: dynamicNSColor(light: light, dark: dark))
    }

    public static let backgroundNS = dynamicNSColor(
        light: rgba(0.957, 0.945, 0.925),
        dark: rgba(0.042, 0.049, 0.060)
    )
    public static let background = dynamic(
        light: rgba(0.957, 0.945, 0.925),
        dark: rgba(0.042, 0.049, 0.060)
    )
    public static let backgroundLift = dynamic(
        light: rgba(0.984, 0.973, 0.953),
        dark: rgba(0.060, 0.069, 0.083)
    )
    public static let surface = dynamic(
        light: rgba(0.992, 0.986, 0.975),
        dark: rgba(0.075, 0.085, 0.101)
    )
    public static let surfaceRaised = dynamic(
        light: rgba(1.0, 1.0, 1.0),
        dark: rgba(0.105, 0.116, 0.136)
    )
    public static let hairline = dynamic(
        light: NSColor.black.withAlphaComponent(0.10),
        dark: NSColor.white.withAlphaComponent(0.075)
    )
    public static let text = dynamic(
        light: rgba(0.12, 0.11, 0.10, 0.92),
        dark: NSColor.white.withAlphaComponent(0.93)
    )
    public static let secondary = dynamic(
        light: rgba(0.12, 0.11, 0.10, 0.56),
        dark: NSColor.white.withAlphaComponent(0.53)
    )
    public static let tertiary = dynamic(
        light: rgba(0.12, 0.11, 0.10, 0.34),
        dark: NSColor.white.withAlphaComponent(0.30)
    )
    public static let accent = dynamic(
        light: rgba(0.70, 0.40, 0.17),
        dark: rgba(0.94, 0.63, 0.35)
    )
    public static let accentBright = dynamic(
        light: rgba(0.62, 0.34, 0.13),
        dark: rgba(1.0, 0.76, 0.50)
    )
    public static let success = dynamic(
        light: rgba(0.16, 0.52, 0.35),
        dark: rgba(0.48, 0.80, 0.65)
    )
    public static let danger = dynamic(
        light: rgba(0.70, 0.16, 0.14),
        dark: rgba(0.95, 0.36, 0.33)
    )
    public static let controlFill = dynamic(
        light: NSColor.black.withAlphaComponent(0.045),
        dark: NSColor.white.withAlphaComponent(0.045)
    )
    public static let controlFillHover = dynamic(
        light: NSColor.black.withAlphaComponent(0.075),
        dark: NSColor.white.withAlphaComponent(0.075)
    )
    public static let rowHover = dynamic(
        light: NSColor.black.withAlphaComponent(0.04),
        dark: NSColor.white.withAlphaComponent(0.04)
    )
    public static let keycapFill = dynamic(
        light: NSColor.black.withAlphaComponent(0.045),
        dark: NSColor.white.withAlphaComponent(0.055)
    )
    public static let keycapStroke = dynamic(
        light: NSColor.black.withAlphaComponent(0.10),
        dark: NSColor.white.withAlphaComponent(0.10)
    )
    public static let separator = dynamic(
        light: NSColor.black.withAlphaComponent(0.14),
        dark: NSColor.white.withAlphaComponent(0.14)
    )
    public static let switchTrack = dynamic(
        light: NSColor.black.withAlphaComponent(0.12),
        dark: NSColor.white.withAlphaComponent(0.09)
    )
    public static let switchTrackStroke = dynamic(
        light: NSColor.black.withAlphaComponent(0.08),
        dark: NSColor.white.withAlphaComponent(0.08)
    )
    public static let sliderTrack = dynamic(
        light: NSColor.black.withAlphaComponent(0.10),
        dark: NSColor.white.withAlphaComponent(0.07)
    )
    public static let accentWash = dynamic(
        light: rgba(0.70, 0.40, 0.17, 0.06),
        dark: rgba(0.94, 0.63, 0.35, 0.075)
    )
    public static let coolWash = dynamic(
        light: rgba(0.30, 0.42, 0.55, 0.045),
        dark: rgba(0.25, 0.36, 0.50, 0.07)
    )
    public static let bottomShade = dynamic(
        light: NSColor.black.withAlphaComponent(0.035),
        dark: NSColor.black.withAlphaComponent(0.22)
    )
    public static let sidebarWash = dynamic(
        light: rgba(0.70, 0.40, 0.17, 0.035),
        dark: rgba(0.94, 0.63, 0.35, 0.055)
    )
    public static let objectShadow = dynamic(
        light: NSColor.black.withAlphaComponent(0.28),
        dark: NSColor.black.withAlphaComponent(0.55)
    )
    public static let objectShadowSoft = dynamic(
        light: NSColor.black.withAlphaComponent(0.12),
        dark: NSColor.black.withAlphaComponent(0.28)
    )

    public static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    public static func label(
        _ size: CGFloat = 10.5,
        weight: Font.Weight = .medium
    ) -> Font {
        .system(size: size, weight: weight)
    }

    public static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

public struct BossPressButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

public struct BossPillButton<Content: View>: View {
    private let isEnabled: Bool
    private let action: () -> Void
    private let content: Content
    @State private var hovering = false
    @FocusState private var focused: Bool

    public init(
        isEnabled: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isEnabled = isEnabled
        self.action = action
        self.content = content()
    }

    public var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(minHeight: 24)
                .background(
                    Capsule().fill(
                        hovering && isEnabled
                            ? BossTheme.controlFillHover
                            : BossTheme.controlFill
                    )
                )
                .overlay(Capsule().stroke(BossTheme.hairline, lineWidth: 1))
                .overlay(
                    Capsule().stroke(
                        BossTheme.accent.opacity(focused ? 0.75 : 0),
                        lineWidth: 1
                    )
                )
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.42)
        }
        .buttonStyle(BossPressButtonStyle())
        .disabled(!isEnabled)
        .onHover { hovering = $0 }
        .focused($focused)
        .focusable()
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

public struct BossSwitch: View {
    @Binding private var isOn: Bool

    public init(isOn: Binding<Bool>) {
        self._isOn = isOn
    }

    public var body: some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.76)) {
                isOn.toggle()
            }
        } label: {
            Capsule()
                .fill(
                    isOn
                        ? BossTheme.accent.opacity(0.88)
                        : BossTheme.switchTrack
                )
                .frame(width: 34, height: 19)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 15, height: 15)
                        .padding(.horizontal, 2)
                        .shadow(
                            color: BossTheme.objectShadowSoft,
                            radius: 1.5,
                            y: 1
                        )
                }
                .overlay(
                    Capsule().stroke(
                        isOn
                            ? BossTheme.accentBright.opacity(0.35)
                            : BossTheme.switchTrackStroke,
                        lineWidth: 0.8
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

public struct BossSlider: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double

    public init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double
    ) {
        self._value = value
        self.range = range
        self.step = step
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let fraction = min(
                max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0),
                1
            )
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(BossTheme.sliderTrack)
                    .frame(height: 4)
                Capsule()
                    .fill(BossTheme.accent.opacity(0.72))
                    .frame(width: max(4, width * fraction), height: 4)
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(BossTheme.background, lineWidth: 2))
                    .shadow(
                        color: BossTheme.objectShadowSoft,
                        radius: 2,
                        y: 1
                    )
                    .offset(x: (width - 12) * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let fraction = min(max(gesture.location.x / width, 0), 1)
                        let raw = range.lowerBound
                            + fraction * (range.upperBound - range.lowerBound)
                        let snapped = (raw / step).rounded() * step
                        value = min(max(snapped, range.lowerBound), range.upperBound)
                    }
            )
        }
        .frame(height: 18)
    }
}

public struct BossMark: View {
    private let size: CGFloat

    public init(size: CGFloat = 42) {
        self.size = size
    }

    public var body: some View {
        Group {
            if let icon = Self.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .shadow(
                        color: BossTheme.objectShadowSoft,
                        radius: 5,
                        y: 2
                    )
            } else {
                vectorMark
            }
        }
        .frame(width: size, height: size)
    }

    private static let appIcon: NSImage? = {
        if let url = Bundle.main.url(
            forResource: "AppIcon",
            withExtension: "icns"
        ) {
            return NSImage(contentsOf: url)
        }
        return NSImage(named: NSImage.applicationIconName)
    }()

    private var vectorMark: some View {
        let scale = size / 42
        return ZStack {
            RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.150, green: 0.164, blue: 0.190),
                            Color(red: 0.058, green: 0.066, blue: 0.080),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.03),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)

            ZStack {
                RoundedRectangle(cornerRadius: 4.5 * scale, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.960, green: 0.966, blue: 0.974),
                                Color(red: 0.706, green: 0.722, blue: 0.742),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 13 * scale, height: 27 * scale)
                Circle()
                    .fill(Color(red: 0.055, green: 0.060, blue: 0.070))
                    .frame(width: 8 * scale, height: 8 * scale)
                    .offset(y: -5 * scale)
                Capsule()
                    .fill(BossTheme.accent)
                    .frame(width: 4 * scale, height: 1.4 * scale)
                    .offset(y: 8 * scale)
            }
            .shadow(color: .black.opacity(0.28), radius: 2, x: 0, y: 1)
        }
        .frame(width: size, height: size)
    }
}

public struct BossBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            BossTheme.background
            RadialGradient(
                colors: [
                    BossTheme.accentWash,
                    .clear,
                ],
                center: .init(x: 0.30, y: 0.06),
                startRadius: 10,
                endRadius: 560
            )
            RadialGradient(
                colors: [
                    BossTheme.coolWash,
                    .clear,
                ],
                center: .init(x: 0.92, y: 0.92),
                startRadius: 10,
                endRadius: 620
            )
            LinearGradient(
                colors: [
                    .clear,
                    BossTheme.bottomShade,
                ],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}
