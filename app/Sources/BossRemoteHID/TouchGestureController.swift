import BossRemoteCore
import CoreGraphics
import Foundation

public final class TouchGestureController {
    public enum SwipeDirection: String, Sendable {
        case up, down, left, right
    }

    public var onPointerMove: ((CGFloat, CGFloat) -> Void)?
    public var onScroll: ((Int32) -> Void)?
    public var onClick: (() -> Void)?
    public var onSwipe: ((SwipeDirection, Bool) -> Void)?
    public var onDoubleTap: (() -> Void)?
    public var doubleTapAvailable: (() -> Bool)?
    public var onLog: ((String) -> Void)?

    public var isPointerEnabled = true
    public var isScrollEnabled = true
    public var isTapEnabled = true
    public var pressFreezeEnabled = true
    public var pointerSpeed: CGFloat = 1
    public var scrollSpeed: CGFloat = 1

    private let pointerScale: CGFloat = 320
    private let motionThreshold: CGFloat = 0.0007
    private let velocityWindow: TimeInterval = 0.06
    private let tapMaximumDuration: TimeInterval = 0.24
    private let tapMaximumDistance: CGFloat = 0.03
    /// Rotation that must accumulate before the ring starts scrolling, so a
    /// touch that lands on the outer ring never jumps the page.
    private let scrollStartThreshold: CGFloat = 0.22
    /// Pixels per radian at a crawl and at a fast spin. A flat rate is what
    /// made slow rotation feel dead and fast rotation feel slow.
    private let scrollGainSlow: CGFloat = 130
    private let scrollGainFast: CGFloat = 520
    private let scrollSpeedLow: CGFloat = 0.8
    private let scrollSpeedHigh: CGFloat = 9
    /// Higher than the pointer ease: scrolling that lags behind the thumb
    /// reads as sticky rather than smooth.
    private let scrollEase: CGFloat = 0.55
    /// Relative contact-pressure rise that counts as a press.
    private let clickRiseRatio: CGFloat = 0.35
    /// Finger travel that cancels a press-freeze so the cursor never sticks.
    private let pressMoveMax: CGFloat = 0.025
    private let swipeMinimumDistance: CGFloat = 0.12
    private let swipeMinimumSpeed: CGFloat = 1.2
    private let doubleTapWindow: TimeInterval = 0.28

    private var isTouching = false
    private var startedAt: TimeInterval = 0
    private var lastFrameAt: TimeInterval = 0
    private var lastPoint: CGPoint?
    private var startPoint: CGPoint?
    private var lastAngle: CGFloat?
    private var tapCandidate = false
    private var tapTravel: CGFloat = 0
    private var didMoveOrScroll = false
    private var isCircular = false
    private var liftWatch: DispatchSourceTimer?

    private var velocitySamples: [(time: TimeInterval, distance: CGFloat)] = []
    private var smoothedX: CGFloat = 0
    private var smoothedY: CGFloat = 0
    private var hasMotionState = false
    private var residualX: CGFloat = 0
    private var residualY: CGFloat = 0
    private var scrollStarted = false
    private var scrollArmed: CGFloat = 0
    private var scrollTarget: CGFloat = 0
    private var scrollSmoothed: CGFloat = 0
    private var scrollVelocity: CGFloat = 0
    private var inertiaVelocity: CGFloat = 0
    private var inertiaTimer: DispatchSourceTimer?

    private var baselineSize: CGFloat = 0
    private var baselineFrames = 0
    private var peakSize: CGFloat = 0
    private var pressFrozen = false
    private var freezeOrigin: CGPoint?
    private var startedOnRing = false
    private var lastTapEndedAt: TimeInterval = 0

    public init() {}

    public func handle(contacts: [TouchSurface.Contact]) {
        let now = ProcessInfo.processInfo.systemUptime

        guard !contacts.isEmpty else {
            finishIfNeeded(at: now)
            return
        }
        guard let point = averagePoint(contacts) else { return }
        let size = averageSize(contacts)
        if !isTouching {
            begin(at: point, size: size, contactCount: contacts.count, now: now)
            return
        }
        update(to: point, size: size, at: now)
    }

    private func begin(
        at point: CGPoint,
        size: CGFloat,
        contactCount: Int,
        now: TimeInterval
    ) {
        isTouching = true
        startedAt = now
        lastFrameAt = now
        lastPoint = point
        startPoint = point
        lastAngle = atan2(point.y - 0.5, point.x - 0.5)
        tapCandidate = contactCount == 1
        tapTravel = 0
        didMoveOrScroll = false
        isCircular = false
        startedOnRing = TouchGeometry.isOnRing(
            x: Double(point.x),
            y: Double(point.y)
        )
        velocitySamples.removeAll(keepingCapacity: true)
        smoothedX = 0
        smoothedY = 0
        hasMotionState = false
        residualX = 0
        residualY = 0
        scrollStarted = false
        scrollArmed = 0
        scrollTarget = 0
        scrollSmoothed = 0
        scrollVelocity = 0
        baselineSize = size
        baselineFrames = 0
        peakSize = size
        pressFrozen = false
        freezeOrigin = nil
        stopInertia()
        startLiftWatch()
        onLog?(String(
            format: "touch start x=%.3f y=%.3f r=%.3f size=%.3f",
            point.x,
            point.y,
            hypot(point.x - 0.5, point.y - 0.5),
            size
        ))
    }

    private func update(to point: CGPoint, size: CGFloat, at now: TimeInterval) {
        guard let previous = lastPoint else { return }
        defer {
            lastPoint = point
            lastFrameAt = now
        }
        let dx = point.x - previous.x
        let dy = point.y - previous.y
        let dt = lastFrameAt > 0
            ? clamp(now - lastFrameAt, 1.0 / 240, 1.0 / 30)
            : 1.0 / 60

        updatePressFreeze(size: size, point: point)

        let onRing = TouchGeometry.isOnRing(
            x: Double(point.x),
            y: Double(point.y)
        )
        if onRing != isCircular {
            isCircular = onRing
            lastAngle = atan2(point.y - 0.5, point.x - 0.5)
            scrollStarted = false
            scrollArmed = 0
            scrollVelocity = 0
            scrollTarget = 0
            scrollSmoothed = 0
            return
        }

        if isCircular {
            updateCircular(point: point, dt: dt)
            return
        }

        let elapsed = now - startedAt
        let distance = startPoint.map {
            hypot(point.x - $0.x, point.y - $0.y)
        } ?? .infinity
        if tapCandidate,
           elapsed > tapMaximumDuration || distance > tapMaximumDistance {
            tapCandidate = false
        }

        let moved = hypot(dx, dy)
        guard moved >= motionThreshold else { return }
        tapTravel += moved
        if tapCandidate {
            if tapTravel > tapMaximumDistance {
                tapCandidate = false
                didMoveOrScroll = true
            }
        } else {
            didMoveOrScroll = true
        }
        guard isPointerEnabled, !pressFrozen else { return }

        let velocity = updateVelocity(distance: moved, at: now)
        let gain = pointerGain(velocity: velocity)
        let outX = dx * pointerScale * gain * pointerSpeed
        let outY = -dy * pointerScale * gain * pointerSpeed

        // Low-speed EMA removes sensor quantisation jitter; it fades out as soon
        // as the finger cruises so fast movement keeps zero added latency.
        let speedT = clamp((velocity - 0.15) / 1.35, 0, 1)
        // Normalise the per-frame blend to a 60 Hz reference so the same finger
        // speed feels identical when the remote reports at a different frame rate.
        let referenceAlpha = 0.60 + 0.40 * speedT
        let alpha = 1 - CGFloat(
            pow(Double(1 - referenceAlpha), Double(dt * 60))
        )
        if hasMotionState {
            smoothedX = alpha * outX + (1 - alpha) * smoothedX
            smoothedY = alpha * outY + (1 - alpha) * smoothedY
        } else {
            smoothedX = outX
            smoothedY = outY
            hasMotionState = true
        }

        emitPointer(smoothedX, smoothedY)
    }

    private func updateCircular(point: CGPoint, dt: CGFloat) {
        let angle = atan2(point.y - 0.5, point.x - 0.5)
        guard let lastAngle else {
            self.lastAngle = angle
            return
        }
        self.lastAngle = angle
        var delta = angle - lastAngle
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        guard abs(delta) < .pi else { return }

        tapCandidate = false
        didMoveOrScroll = true
        guard isScrollEnabled else { return }

        let step = max(dt, 1.0 / 120)
        // Speed comes from this frame only: the armed rotation below is a
        // backlog, and treating it as one frame of motion would spike the gain.
        let speed = abs(delta) / step

        if !scrollStarted {
            scrollArmed += delta
            guard abs(scrollArmed) >= scrollStartThreshold else { return }
            // Spend the rotation that armed the gesture instead of dropping it,
            // otherwise every ring gesture starts with a dead 20 degrees.
            delta = scrollArmed
            scrollArmed = 0
            scrollStarted = true
        }

        let pixels = -delta * scrollGain(for: speed) * scrollSpeed
        scrollTarget += pixels
        scrollVelocity = scrollVelocity * 0.7 + (pixels / step) * 0.3
        emitScroll(dt: dt)
    }

    /// Crawling around the ring stays precise, a quick spin covers a page.
    private func scrollGain(for speed: CGFloat) -> CGFloat {
        let t = min(
            max((speed - scrollSpeedLow) / (scrollSpeedHigh - scrollSpeedLow), 0),
            1
        )
        let smooth = t * t * (3 - 2 * t)
        return scrollGainSlow + (scrollGainFast - scrollGainSlow) * smooth
    }

    private func emitScroll(dt: CGFloat) {
        // Normalised to 60 Hz so an irregular frame rate cannot change the feel.
        let eased = 1 - pow(1 - Double(scrollEase), Double(dt) * 60)
        scrollSmoothed += (scrollTarget - scrollSmoothed)
            * CGFloat(min(1, max(0.05, eased)))
        let whole = scrollSmoothed.rounded(.towardZero)
        guard whole != 0 else { return }
        scrollSmoothed -= whole
        scrollTarget -= whole
        onScroll?(Int32(whole))
    }

    /// A wheel keeps turning when you let go; without this the page stops dead
    /// against the thumb and every scroll reads as scratchy.
    private func startInertia() {
        guard abs(scrollVelocity) > 320 else { return }
        inertiaVelocity = min(max(scrollVelocity, -2400), 2400)
        guard inertiaTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0 / 60.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if abs(self.inertiaVelocity) < 45 {
                self.stopInertia()
                return
            }
            self.scrollTarget += self.inertiaVelocity / 60
            self.inertiaVelocity *= 0.88
            self.emitScroll(dt: 1.0 / 60.0)
        }
        timer.resume()
        inertiaTimer = timer
    }

    private func stopInertia() {
        inertiaTimer?.cancel()
        inertiaTimer = nil
        inertiaVelocity = 0
    }

    /// A press raises contact pressure without moving the finger; freezing the
    /// pointer there keeps a click from drifting. Any real travel releases it.
    private func updatePressFreeze(size: CGFloat, point: CGPoint) {
        peakSize = max(peakSize, size)
        if baselineFrames < 3 {
            baselineSize = max(baselineSize, size)
            baselineFrames += 1
            return
        }
        if pressFrozen {
            guard let origin = freezeOrigin else {
                pressFrozen = false
                return
            }
            if hypot(point.x - origin.x, point.y - origin.y) > pressMoveMax {
                pressFrozen = false
                onLog?("press freeze released")
            }
            return
        }
        guard pressFreezeEnabled else { return }
        let base = max(baselineSize, 0.02)
        guard peakSize > baselineSize else { return }
        if (peakSize - baselineSize) / base >= clickRiseRatio {
            pressFrozen = true
            freezeOrigin = point
            onLog?(
                "press freeze base=\(String(format: "%.3f", baselineSize)) peak=\(String(format: "%.3f", peakSize))"
            )
        }
    }

    private func updateVelocity(distance: CGFloat, at now: TimeInterval) -> CGFloat {
        velocitySamples.append((now, distance))
        while velocitySamples.count > 2,
              let first = velocitySamples.first,
              now - first.time > velocityWindow {
            velocitySamples.removeFirst()
        }
        guard let first = velocitySamples.first,
              let last = velocitySamples.last,
              velocitySamples.count > 1
        else { return distance * 60 }
        let span = max(0.008, last.time - first.time)
        let travelled = velocitySamples.dropFirst().reduce(0) { $0 + $1.distance }
        return travelled / CGFloat(span)
    }

    /// Three-stage macOS-style curve, modelled on the Windows trackpad
    /// reimplementations (Mac-touchpad `compute_dynamic_gain`, t650d `_pointer`):
    /// slow precision floor, smooth mid-speed ramp, logarithmic high-speed boost.
    private func pointerGain(velocity: CGFloat) -> CGFloat {
        let minGain: CGFloat = 0.58
        let cruiseGain: CGFloat = 0.95
        let fastGain: CGFloat = 2.25
        let cruiseSpeed: CGFloat = 0.45
        let fastSpeed: CGFloat = 5.5

        if velocity <= cruiseSpeed {
            let t = clamp(velocity / cruiseSpeed, 0, 1)
            return minGain + (cruiseGain - minGain) * t
        }

        let t = clamp((velocity - cruiseSpeed) / (fastSpeed - cruiseSpeed), 0, 1)
        let smooth = t * t * (3 - 2 * t)
        var gain = cruiseGain + (fastGain - cruiseGain) * smooth
        if velocity > 2.5 {
            gain += 0.30 * log(1 + (velocity - 2.5) * 1.2)
        }
        return min(2.9, gain)
    }

    private func emitPointer(_ x: CGFloat, _ y: CGFloat) {
        residualX += x
        residualY += y
        let wholeX = residualX.rounded(.towardZero)
        let wholeY = residualY.rounded(.towardZero)
        guard wholeX != 0 || wholeY != 0 else { return }
        residualX -= wholeX
        residualY -= wholeY
        onPointerMove?(wholeX, wholeY)
    }

    private func finishIfNeeded(at now: TimeInterval) {
        guard isTouching else { return }
        let elapsed = now - startedAt
        if scrollStarted { startInertia() }
        if let direction = swipeDirection(elapsed: elapsed) {
            onSwipe?(direction, startedOnRing)
            reset()
            return
        }
        if isTapEnabled, tapCandidate, !didMoveOrScroll, elapsed <= tapMaximumDuration {
            let wantsDouble = doubleTapAvailable?() ?? false
            if wantsDouble,
               lastTapEndedAt > 0,
               now - lastTapEndedAt <= doubleTapWindow {
                lastTapEndedAt = 0
                onDoubleTap?()
            } else {
                lastTapEndedAt = now
                onClick?()
            }
        }
        reset()
    }

    private func swipeDirection(elapsed: TimeInterval) -> SwipeDirection? {
        guard !scrollStarted,
              let start = startPoint,
              let end = lastPoint
        else { return nil }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        guard distance >= swipeMinimumDistance else { return nil }
        let duration = max(0.02, elapsed)
        guard distance / CGFloat(duration) >= swipeMinimumSpeed else {
            return nil
        }
        if abs(dx) >= abs(dy) {
            return dx > 0 ? .right : .left
        }
        return dy > 0 ? .down : .up
    }

    /// Some remotes stop sending frames without a final empty one. A single
    /// low-frequency watch is far cheaper than re-arming a timer every frame,
    /// which at 90 Hz was allocating on the main queue continuously.
    private func startLiftWatch() {
        guard liftWatch == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.35, repeating: 0.1)
        timer.setEventHandler { [weak self] in
            guard let self, self.isTouching else { return }
            let idle = ProcessInfo.processInfo.systemUptime - self.lastFrameAt
            guard idle > 0.3 else { return }
            self.finishIfNeeded(at: self.lastFrameAt)
        }
        timer.resume()
        liftWatch = timer
    }

    private func stopLiftWatch() {
        liftWatch?.cancel()
        liftWatch = nil
    }

    private func averagePoint(_ contacts: [TouchSurface.Contact]) -> CGPoint? {
        guard !contacts.isEmpty else { return nil }
        let sum = contacts.reduce(into: CGPoint.zero) { result, contact in
            result.x += contact.x
            result.y += contact.y
        }
        return CGPoint(
            x: sum.x / CGFloat(contacts.count),
            y: sum.y / CGFloat(contacts.count)
        )
    }

    private func averageSize(_ contacts: [TouchSurface.Contact]) -> CGFloat {
        guard !contacts.isEmpty else { return 0 }
        let total = contacts.reduce(0) { $0 + CGFloat($1.size) }
        return total / CGFloat(contacts.count)
    }

    private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(upper, max(lower, value))
    }

    private func reset() {
        isTouching = false
        lastPoint = nil
        startPoint = nil
        lastAngle = nil
        tapCandidate = false
        tapTravel = 0
        didMoveOrScroll = false
        isCircular = false
        velocitySamples.removeAll(keepingCapacity: true)
        smoothedX = 0
        smoothedY = 0
        hasMotionState = false
        residualX = 0
        residualY = 0
        scrollStarted = false
        scrollArmed = 0
        scrollTarget = 0
        scrollSmoothed = 0
        scrollVelocity = 0
        pressFrozen = false
        freezeOrigin = nil
        baselineFrames = 0
        peakSize = 0
        stopLiftWatch()
    }
}
