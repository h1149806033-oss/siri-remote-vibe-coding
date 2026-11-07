import AppKit
import BossRemoteCore
import SwiftUI

/// A studio stage for the official Siri Remote front view. The remote is drawn
/// in SwiftUI at a 251 x 960 design size so every edge stays sharp at any scale.
/// Hit targets are authored in that same space and scale with the artwork.
public struct RemoteCanvas: View {
    @Binding private var selected: RemoteControl
    private let active: Set<RemoteControl>
    private let stageWidth: CGFloat
    private let stageHeight: CGFloat
    private let touchIndicator: TouchIndicatorModel?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredControl: RemoteControl?
    @State private var stageHovered = false

    private static let designSize = CGSize(width: 256, height: 960)

    public init(
        selected: Binding<RemoteControl>,
        active: Set<RemoteControl>,
        stageWidth: CGFloat = 292,
        stageHeight: CGFloat = 620,
        touchIndicator: TouchIndicatorModel? = nil
    ) {
        self._selected = selected
        self.active = active
        self.stageWidth = stageWidth
        self.stageHeight = stageHeight
        self.touchIndicator = touchIndicator
    }

    public var body: some View {
        GeometryReader { proxy in
            let scale = min(
                proxy.size.width / Self.designSize.width,
                proxy.size.height / Self.designSize.height
            )
            let stageSize = CGSize(
                width: Self.designSize.width * scale,
                height: Self.designSize.height * scale
            )
            ZStack(alignment: .topLeading) {
                RemoteArtwork(
                    active: active,
                    hovered: hoveredControl
                )
                .scaleEffect(scale, anchor: .topLeading)
                .frame(
                    width: stageSize.width,
                    height: stageSize.height,
                    alignment: .topLeading
                )
                if let touchIndicator {
                    TouchOverlay(model: touchIndicator)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(
                            width: stageSize.width,
                            height: stageSize.height,
                            alignment: .topLeading
                        )
                        .allowsHitTesting(false)
                }
                hotspotLayer(scale: scale)
            }
            .frame(width: stageSize.width, height: stageSize.height)
            .scaleEffect(stageHovered ? 1.004 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.22),
                value: stageHovered
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: stageWidth, height: stageHeight)
        .onHover { hovering in
            stageHovered = hovering
        }
    }

    // MARK: - Hit targets

    private struct Hotspot: Identifiable {
        let control: RemoteControl
        let center: CGPoint
        let size: CGSize

        var id: RemoteControl { control }
    }

    private var hotspots: [Hotspot] {
        [
            Hotspot(control: .power, center: CGPoint(x: 197, y: 49),
                    size: CGSize(width: 48, height: 48)),
            Hotspot(control: .up, center: CGPoint(x: 123, y: 119),
                    size: CGSize(width: 48, height: 48)),
            Hotspot(control: .down, center: CGPoint(x: 123, y: 281),
                    size: CGSize(width: 48, height: 48)),
            Hotspot(control: .left, center: CGPoint(x: 42, y: 200),
                    size: CGSize(width: 48, height: 48)),
            Hotspot(control: .right, center: CGPoint(x: 204, y: 200),
                    size: CGSize(width: 48, height: 48)),
            Hotspot(control: .select, center: CGPoint(x: 123, y: 200),
                    size: CGSize(width: 132, height: 132)),
            Hotspot(control: .back, center: CGPoint(x: 70, y: 362),
                    size: CGSize(width: 87, height: 87)),
            Hotspot(control: .tv, center: CGPoint(x: 176, y: 362),
                    size: CGSize(width: 87, height: 87)),
            Hotspot(control: .playPause, center: CGPoint(x: 70, y: 466),
                    size: CGSize(width: 87, height: 87)),
            Hotspot(control: .mute, center: CGPoint(x: 70, y: 570),
                    size: CGSize(width: 87, height: 87)),
            Hotspot(control: .volumeUp, center: CGPoint(x: 176, y: 466),
                    size: CGSize(width: 78, height: 74)),
            Hotspot(control: .volumeDown, center: CGPoint(x: 176, y: 570),
                    size: CGSize(width: 78, height: 74)),
            Hotspot(control: .siri, center: CGPoint(x: 248, y: 200),
                    size: CGSize(width: 18, height: 110)),
        ]
    }

    private func hotspotLayer(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(hotspots) { spot in
                hotspot(spot, scale: scale)
            }
        }
    }

    private func hotspot(_ spot: Hotspot, scale: CGFloat) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.26)) {
                selected = spot.control
            }
        } label: {
            Color.clear
                .frame(
                    width: spot.size.width * scale,
                    height: spot.size.height * scale
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(
            x: spot.center.x * scale,
            y: spot.center.y * scale
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                if hovering {
                    hoveredControl = spot.control
                } else if hoveredControl == spot.control {
                    hoveredControl = nil
                }
            }
        }
        .accessibilityLabel(spot.control.title)
        .help(spot.control.officialFunction)
    }
}

// MARK: - Vector remote

private struct RemoteArtwork: View {
    let active: Set<RemoteControl>
    let hovered: RemoteControl?

    private enum Palette {
        static let aluHi = Color(red: 0.955, green: 0.960, blue: 0.967)
        static let alu = Color(red: 0.884, green: 0.892, blue: 0.905)
        static let aluMid = Color(red: 0.785, green: 0.797, blue: 0.814)
        static let aluLo = Color(red: 0.688, green: 0.702, blue: 0.720)
        static let edge = Color(red: 0.596, green: 0.612, blue: 0.635)
        static let btnHi = Color(red: 0.243, green: 0.251, blue: 0.267)
        static let btn = Color(red: 0.145, green: 0.153, blue: 0.169)
        static let btnLo = Color(red: 0.071, green: 0.078, blue: 0.090)
        static let glyph = Color(red: 0.745, green: 0.761, blue: 0.788)
        static let padHi = Color(red: 0.196, green: 0.204, blue: 0.220)
        static let pad = Color(red: 0.071, green: 0.078, blue: 0.090)
        static let padLo = Color(red: 0.027, green: 0.031, blue: 0.039)
        static let powerInk = Color(red: 0.400, green: 0.427, blue: 0.463)
    }

    private var bodyShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 56, style: .continuous)
    }

    var body: some View {
        ZStack {
            sideRail
            bodyShell
            topDetails
            clickpad
            faceButtons
            volumePill
        }
        .frame(width: 251, height: 960)
        .compositingGroup()
        .accessibilityHidden(true)
    }

    // MARK: Body

    private var bodyShell: some View {
        bodyShape
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Palette.aluHi, location: 0),
                        .init(color: Palette.alu, location: 0.20),
                        .init(color: Palette.alu, location: 0.54),
                        .init(color: Palette.aluMid, location: 0.80),
                        .init(color: Palette.aluLo, location: 1),
                    ],
                    startPoint: .topLeading,
                    endPoint: UnitPoint(x: 0.66, y: 1)
                )
            )
            .overlay(
                bodyShape.fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            Color(red: 0.360, green: 0.390, blue: 0.430).opacity(0.22),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            .overlay(
                bodyShape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.20),
                            .clear,
                            .clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: UnitPoint(x: 0.72, y: 0.40)
                    )
                )
            )
            .overlay(
                bodyShape.stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Palette.edge.opacity(0.92),
                            Palette.edge.opacity(0.55),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
            )
            .overlay(
                bodyShape
                    .inset(by: 1.6)
                    .stroke(Color.white.opacity(0.40), lineWidth: 0.6)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
            )
            .overlay(
                bodyShape.stroke(
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.16)],
                        startPoint: .center,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.4
                )
            )
            .shadow(color: BossTheme.objectShadow, radius: 26, x: 0, y: 20)
            .frame(width: 251, height: 960)
    }

    private var topDetails: some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.345, green: 0.365, blue: 0.396),
                            Color(red: 0.196, green: 0.208, blue: 0.228),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.5)
                )
                .frame(width: 15, height: 6)
                .position(x: 123, y: 48.5)

            powerButton
        }
    }

    private var powerButton: some View {
        let lit = isLit(.power)
        let pressed = active.contains(.power)
        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.927, green: 0.934, blue: 0.943),
                            Color(red: 0.792, green: 0.804, blue: 0.822),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Circle().stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.90),
                                Palette.edge.opacity(0.80),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
                )
                .shadow(color: BossTheme.objectShadowSoft, radius: 2.5, x: 0, y: 1.5)
            Image(systemName: "power")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(lit ? BossTheme.accent : Palette.powerInk)
        }
        .frame(width: 43, height: 43)
        .overlay(focusOutline(Circle(), control: .power, inset: -4))
        .scaleEffect(pressed ? 0.95 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.70), value: pressed)
        .position(x: 197, y: 48.5)
    }

    private var sideRail: some View {
        let pressed = active.contains(.siri)
        let hoveredState = hovered == .siri
        let glow: Double = pressed ? 1 : (hoveredState ? 0.34 : 0)
        let rail = UnevenRoundedRectangle(
            topLeadingRadius: 6.5,
            bottomLeadingRadius: 6.5,
            bottomTrailingRadius: 2,
            topTrailingRadius: 2,
            style: .continuous
        )

        return ZStack {
            rail.fill(
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.643, green: 0.655, blue: 0.675), location: 0),
                        .init(color: Color(red: 0.737, green: 0.749, blue: 0.769), location: 0.55),
                        .init(color: Color(red: 0.836, green: 0.845, blue: 0.860), location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            rail.stroke(Color.black.opacity(0.20), lineWidth: 0.7)
            Rectangle()
                .fill(Color.black.opacity(0.30))
                .frame(width: 0.9)
                .padding(.vertical, 2)
                .padding(.leading, 0.8)
            Rectangle()
                .fill(Color.white.opacity(0.34))
                .frame(width: 0.7)
                .padding(.vertical, 3)
                .padding(.trailing, 0.8)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: 13, height: 100)
        .clipShape(rail)
        .shadow(color: Color.black.opacity(0.26), radius: 2.4, x: -1.6, y: 0)
        .overlay {
            if glow > 0 {
                rail.stroke(
                    BossTheme.accent.opacity(pressed ? 0.95 : 0.34 * glow),
                    lineWidth: pressed ? 1.4 : 0.7
                )
                .blur(radius: pressed ? 1.5 : 2.5)
                .padding(-1.5)
            }
        }
        .shadow(
            color: BossTheme.accent.opacity(pressed ? 0.62 : 0.16 * glow),
            radius: pressed ? 8 : 4
        )
        .scaleEffect(pressed ? 0.97 : 1)
        .animation(.spring(response: 0.20, dampingFraction: 0.72), value: pressed)
        .position(x: 248, y: 200)
    }

    // MARK: Clickpad

    private var clickpad: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Palette.padHi, Palette.pad, Palette.padLo],
                        center: UnitPoint(x: 0.42, y: 0.30),
                        startRadius: 2,
                        endRadius: 132
                    )
                )
                .overlay(Circle().stroke(Color.black.opacity(0.92), lineWidth: 1.4))
                .overlay(
                    Circle().stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                .clear,
                                Color.black.opacity(0.28),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
                .shadow(color: BossTheme.objectShadow, radius: 8, x: 0, y: 5)
                .frame(width: 219, height: 219)

            edgeDot(.up, x: 0, y: -97)
            edgeDot(.down, x: 0, y: 97)
            edgeDot(.left, x: -97, y: 0)
            edgeDot(.right, x: 97, y: 0)

            selectDisc
        }
        .frame(width: 219, height: 219)
        .position(x: 123, y: 200.5)
    }

    private func edgeDot(_ control: RemoteControl, x: CGFloat, y: CGFloat) -> some View {
        let lit = isLit(control)
        return Circle()
            .fill(lit ? BossTheme.accentBright : Color.white.opacity(0.55))
            .frame(width: 4, height: 4)
            .shadow(color: lit ? BossTheme.accent.opacity(0.85) : .clear, radius: 4)
            .offset(x: x, y: y)
    }

    private var selectDisc: some View {
        let lit = isLit(.select)
        let pressed = active.contains(.select)
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.133, green: 0.141, blue: 0.157),
                            Color(red: 0.063, green: 0.071, blue: 0.082),
                        ],
                        center: UnitPoint(x: 0.5, y: 0.38),
                        startRadius: 2,
                        endRadius: 84
                    )
                )
                .overlay(
                    Circle().stroke(Color.white.opacity(0.055), lineWidth: 1)
                )
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(lit ? 0.16 : 0.07),
                            .clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .center
                    ),
                    lineWidth: 1
                )
        }
        .frame(width: 132, height: 132)
        .overlay(focusOutline(Circle(), control: .select, inset: -5))
        .scaleEffect(pressed ? 0.97 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: pressed)
        .shadow(color: BossTheme.objectShadowSoft, radius: 4, x: 0, y: 2)
    }

    // MARK: Face buttons

    private var faceButtons: some View {
        ZStack {
            faceButton(.back, "chevron.backward", iconSize: 23, weight: .semibold,
                       x: 70, y: 362)
            faceButton(.tv, "tv", iconSize: 23, weight: .medium,
                       x: 176, y: 362)
            faceButton(.playPause, "playpause", iconSize: 19.5, weight: .regular,
                       x: 70, y: 466)
            faceButton(.mute, "speaker.slash", iconSize: 20, weight: .regular,
                       x: 70, y: 570)
        }
    }

    private func faceButton(
        _ control: RemoteControl,
        _ symbol: String,
        iconSize: CGFloat,
        weight: Font.Weight,
        x: CGFloat,
        y: CGFloat
    ) -> some View {
        let lit = isLit(control)
        let pressed = active.contains(control)
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Palette.btnHi, Palette.btn, Palette.btnLo],
                        center: UnitPoint(x: 0.5, y: 0.32),
                        startRadius: 1,
                        endRadius: 42
                    )
                )
                .overlay(Circle().stroke(Color.black.opacity(0.90), lineWidth: 1))
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.7)
                        .mask(
                            LinearGradient(
                                colors: [.white, .clear],
                                startPoint: .topLeading,
                                endPoint: .center
                            )
                        )
                )
                .shadow(color: BossTheme.objectShadowSoft, radius: 4, x: 0, y: 3)

            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: weight))
                .foregroundStyle(lit ? BossTheme.accentBright : Palette.glyph)
                .shadow(color: lit ? BossTheme.accent.opacity(0.45) : .clear, radius: 5)
        }
        .frame(width: 87, height: 87)
        .overlay(focusOutline(Circle(), control: control, inset: -5))
        .scaleEffect(pressed ? 0.95 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.68), value: pressed)
        .position(x: x, y: y)
    }

    // MARK: Volume

    private var volumePill: some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Palette.btnHi, Palette.btn, Palette.btnLo],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(Capsule().stroke(Color.black.opacity(0.88), lineWidth: 1))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
                        .mask(
                            LinearGradient(
                                colors: [.white, .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                )
                .shadow(color: BossTheme.objectShadowSoft, radius: 4, x: 0, y: 3)

            ZStack {
                volumeGlow(.volumeUp, upper: true)
                    .frame(width: 84, height: 95.5)
                    .offset(y: -47.75)
                volumeGlow(.volumeDown, upper: false)
                    .frame(width: 84, height: 95.5)
                    .offset(y: 47.75)
            }
            .frame(width: 84, height: 191)
            .clipShape(Capsule())

            Rectangle()
                .fill(Color.white.opacity(0.055))
                .frame(width: 54, height: 1)

            volumeGlyph(.volumeUp, "plus", offsetY: -52)
            volumeGlyph(.volumeDown, "minus", offsetY: 52)
        }
        .frame(width: 84, height: 191)
        .position(x: 175.5, y: 518)
    }

    private func volumeGlow(_ control: RemoteControl, upper: Bool) -> some View {
        let pressed = active.contains(control)
        let hovered = hovered == control
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: upper ? 42 : 0,
            bottomLeadingRadius: upper ? 0 : 42,
            bottomTrailingRadius: upper ? 0 : 42,
            topTrailingRadius: upper ? 42 : 0,
            style: .continuous
        )
        return shape
            .fill(
                RadialGradient(
                    colors: [
                        BossTheme.accent.opacity(pressed ? 0.22 : (hovered ? 0.08 : 0)),
                        BossTheme.accent.opacity(pressed ? 0.05 : 0),
                        .clear,
                    ],
                    center: UnitPoint(x: 0.5, y: upper ? 0.40 : 0.60),
                    startRadius: 2,
                    endRadius: 55
                )
            )
            .shadow(
                color: BossTheme.accent.opacity(pressed ? 0.26 : 0),
                radius: pressed ? 8 : 0
            )
            .animation(.easeOut(duration: 0.16), value: pressed)
            .animation(.easeOut(duration: 0.14), value: hovered)
    }

    private func volumeGlyph(
        _ control: RemoteControl,
        _ symbol: String,
        offsetY: CGFloat
    ) -> some View {
        let pressed = active.contains(control)
        let hovered = hovered == control
        return Image(systemName: symbol)
            .font(.system(size: 18, weight: pressed ? .semibold : .medium))
            .foregroundStyle(
                pressed
                    ? BossTheme.accentBright
                    : (hovered ? BossTheme.accent : Palette.glyph)
            )
            .shadow(
                color: pressed ? BossTheme.accent.opacity(0.55) : .clear,
                radius: 5
            )
            .scaleEffect(pressed ? 0.94 : 1)
            .animation(.spring(response: 0.20, dampingFraction: 0.70), value: pressed)
            .offset(y: offsetY)
    }

    // MARK: State

    private func isLit(_ control: RemoteControl) -> Bool {
        hovered == control || active.contains(control)
    }

    private func focusOutline<S: Shape>(
        _ shape: S,
        control: RemoteControl,
        inset: CGFloat
    ) -> some View {
        let style = ringStyle(control)
        return shape
            .stroke(style.color, lineWidth: style.width)
            .padding(inset)
            .shadow(
                color: style.color.opacity(style.glow),
                radius: style.glow > 0.3 ? 8 : 4
            )
    }

    private func ringStyle(
        _ control: RemoteControl
    ) -> (color: Color, width: CGFloat, glow: Double) {
        if active.contains(control) {
            return (BossTheme.accent.opacity(0.96), 2.4, 0.58)
        }
        if hovered == control {
            return (BossTheme.accent.opacity(0.34), 1.0, 0.12)
        }
        return (.clear, 0, 0)
    }
}

private struct TouchOverlay: View {
    @ObservedObject var model: TouchIndicatorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let padCenter = CGPoint(x: 123, y: 200.5)
    private let padDiameter: CGFloat = 219

    var body: some View {
        let point = model.point
        let visible = point != nil
        let x = padCenter.x + CGFloat((point?.x ?? 0.5) - 0.5) * padDiameter
        let y = padCenter.y + CGFloat((point?.y ?? 0.5) - 0.5) * padDiameter

        ZStack {
            if point?.onRing == true, let point {
                rimGlow(point)
            }

            contact
                .opacity(visible ? (point?.onRing == true ? 0.86 : 1) : 0)
                .scaleEffect(visible || reduceMotion ? 1 : 0.72)
                .position(x: x, y: y)
                .animation(
                    reduceMotion
                        ? nil
                        : .spring(response: 0.26, dampingFraction: 0.72),
                    value: visible
                )
        }
        .frame(width: 251, height: 960)
        .animation(.easeOut(duration: 0.14), value: point?.onRing)
    }

    /// Light bleeding from the pad edge under the thumb, so ring mode reads as
    /// a lit rim instead of a painted line.
    private func rimGlow(_ point: TouchIndicatorModel.Point) -> some View {
        let dx = point.x - 0.5
        let dy = point.y - 0.5
        let length = max((dx * dx + dy * dy).squareRoot(), 0.0001)
        let radius = padDiameter / 2 - 4
        let x = padDiameter / 2 + dx / length * radius
        let y = padDiameter / 2 + dy / length * radius

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: BossTheme.accentBright.opacity(0.50), location: 0),
                            .init(color: BossTheme.accent.opacity(0.30), location: 0.26),
                            .init(color: BossTheme.accent.opacity(0.12), location: 0.55),
                            .init(color: BossTheme.accent.opacity(0), location: 1),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 40
                    )
                )
                .frame(width: 80, height: 80)
                .position(x: x, y: y)
        }
        .frame(width: padDiameter, height: padDiameter)
        .clipShape(Circle())
        .position(x: padCenter.x, y: padCenter.y)
        .allowsHitTesting(false)
    }

    /// A point of light under the fingertip: ambient bloom, a soft rim, a warm
    /// body and a white-hot core. No hard strokes, so it sits inside the
    /// photoreal artwork instead of on top of it.
    private var contact: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: BossTheme.accent.opacity(0.30), location: 0),
                            .init(color: BossTheme.accent.opacity(0.19), location: 0.22),
                            .init(color: BossTheme.accent.opacity(0.08), location: 0.48),
                            .init(color: BossTheme.accent.opacity(0.02), location: 0.74),
                            .init(color: BossTheme.accent.opacity(0), location: 1),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 36
                    )
                )
                .frame(width: 72, height: 72)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            BossTheme.accentBright.opacity(0.50),
                            BossTheme.accent.opacity(0.16),
                            BossTheme.accent.opacity(0),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 11
                    )
                )
                .frame(width: 22, height: 22)

            Circle()
                .strokeBorder(BossTheme.accent.opacity(0.34), lineWidth: 1)
                .frame(width: 21, height: 21)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white,
                            Color.white.opacity(0.62),
                        ],
                        center: UnitPoint(x: 0.45, y: 0.40),
                        startRadius: 0,
                        endRadius: 4
                    )
                )
                .frame(width: 6, height: 6)
                .shadow(color: BossTheme.accent.opacity(0.85), radius: 4)
        }
        .frame(width: 68, height: 68)
    }
}

/// A cropped head of the remote artwork, for list rows and device headers.
public struct RemoteThumbnail: View {
    private let size: CGFloat
    /// Design-space height to show: just past the bottom of the clickpad.
    private let shownHeight: CGFloat = 320

    public init(size: CGFloat = 44) {
        self.size = size
    }

    public var body: some View {
        RemoteArtwork(active: [], hovered: nil)
            .frame(width: 251, height: 960)
            .scaleEffect(size / shownHeight, anchor: .top)
            .frame(width: size, height: size, alignment: .top)
            .clipShape(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}
