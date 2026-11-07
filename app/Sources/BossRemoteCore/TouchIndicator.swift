import Combine
import CoreGraphics
import Foundation

/// The clickpad sensor reports a narrower box than its physical circle, so raw
/// 0...1 coordinates compress toward the middle. These bounds were measured by
/// touching the centre and the four edges of a 3rd-generation Siri Remote.
public enum TouchGeometry {
    public static let xAtLeft: Double = 0.068
    public static let xAtRight: Double = 0.902
    /// The sensor counts up towards the top of the remote, the opposite of
    /// screen coordinates, so y is flipped when converting.
    public static let yAtBottom: Double = 0.025
    public static let yAtTop: Double = 0.892

    /// Distance from the centre, in calibrated units, where the outer ring
    /// begins. Calibrated coordinates span the pad's bounding square, so the
    /// rim itself sits at 0.5.
    public static let ringRadius: Double = 0.40
    /// Once a gesture is scrolling, it keeps scrolling until the finger comes
    /// this far in. Without the gap, a thumb circling the ring drifts inside
    /// the radius and the gesture flips to pointer control mid-turn.
    public static let ringExitRadius: Double = 0.28

    public static func normalize(
        x: Double,
        y: Double
    ) -> (x: Double, y: Double) {
        (
            min(max((x - xAtLeft) / (xAtRight - xAtLeft), 0), 1),
            min(max((yAtTop - y) / (yAtTop - yAtBottom), 0), 1)
        )
    }

    public static func radius(x: Double, y: Double) -> Double {
        let point = normalize(x: x, y: y)
        let dx = point.x - 0.5
        let dy = point.y - 0.5
        return (dx * dx + dy * dy).squareRoot()
    }

    public static func isOnRing(x: Double, y: Double) -> Bool {
        radius(x: x, y: y) >= ringRadius
    }
}

/// Live position of the finger on the clickpad, for the remote artwork.
/// Published separately from `AppModel` so only the small overlay redraws.
public final class TouchIndicatorModel: ObservableObject {
    public struct Point: Equatable, Sendable {
        /// Normalised 0...1 across the clickpad surface.
        public var x: Double
        public var y: Double
        /// True while the finger sits on the outer ring, where gestures scroll.
        public var onRing: Bool

        public init(x: Double, y: Double, onRing: Bool) {
            self.x = x
            self.y = y
            self.onRing = onRing
        }
    }

    @Published public private(set) var point: Point?

    private let minimumInterval: TimeInterval
    private var lastPublish: TimeInterval = 0

    public init(minimumInterval: TimeInterval = 1.0 / 45) {
        self.minimumInterval = minimumInterval
    }

    public func update(x: Double, y: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        let calibrated = TouchGeometry.normalize(x: x, y: y)
        let radius = (calibrated.x - 0.5) * (calibrated.x - 0.5)
            + (calibrated.y - 0.5) * (calibrated.y - 0.5)
        let next = Point(
            x: calibrated.x,
            y: calibrated.y,
            onRing: radius.squareRoot() >= TouchGeometry.ringRadius
        )
        if point == nil
            || now - lastPublish >= minimumInterval
            || next.onRing != point?.onRing {
            lastPublish = now
            point = next
        }
    }

    public func clear() {
        guard point != nil else { return }
        point = nil
    }

    /// Takes raw sensor coordinates so snapshots exercise the same calibration.
    public func setForPreview(x: Double?, y: Double?) {
        guard let x, let y else {
            point = nil
            return
        }
        let calibrated = TouchGeometry.normalize(x: x, y: y)
        let radius = (calibrated.x - 0.5) * (calibrated.x - 0.5)
            + (calibrated.y - 0.5) * (calibrated.y - 0.5)
        point = Point(
            x: calibrated.x,
            y: calibrated.y,
            onRing: radius.squareRoot() >= TouchGeometry.ringRadius
        )
    }
}
