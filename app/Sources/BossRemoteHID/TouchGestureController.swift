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
    /// Fires after a double tap in the top or bottom band scrolled the page.
    public var onJump: ((Bool) -> Void)?
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
    private let scrollGainSlow: CGFloat = 110
    private let scrollGainFast: CGFloat = 460
    private let scrollSpeedLow: CGFloat = 0.8
    private let scrollSpeedHigh: CGFloat = 9
    /// Higher than the pointer ease: scrolling that lags behind the thumb
    /// reads as sticky rather than smooth.
    private let scrollEase: CGFloat = 0.55
    /// Relative contact-pressure rise that counts as a press.
    private let clickRiseRatio: CGFloat = 0.60
    /// How far the finger may drift while a pressure rise is measured.
    private let pressMaxTravel: CGFloat = 0.02
    private let pressWindow: TimeInterval = 0.12
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
    private var angularSpeed: CGFloat = 0
    private var inertiaVelocity: CGFloat = 0
    private var inertiaTimer: DispatchSourceTimer?

    private struct PressSample {
        var time: TimeInterval
        var size: CGFloat
        var point: CGPoint
    }

    private var pressSamples: [PressSample] = []
    private var pressFrozen = false
    private var freezeOrigin: CGPoint?
    private var startedOnRing = false
    private var pendingTap: PendingTap?

    private enum TapZone {
        case top
        case bottom
    }

    private enum TapAction {
        case doubleTap
        case jump(toTop: Bool)
    }

    private struct PendingTap {
        var at: TimeInterval
        var action: TapAction
        var work: DispatchWorkItem
    }

    /// Fraction of the clickpad, measured from the top and bottom, that turns
    /// a double tap into a jump instead of a click.
    private let jumpBand: Double = 0.26
    private let jumpPixels: Int32 = 24_000

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
        angularSpeed = 0
        pressSamples.removeAll(keepingCapacity: true)
        pressFrozen = false
        freezeOrigin = nil
        cancelDeferredClick()
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

        updatePressFreeze(size: size, point: point, now: now)

        let radius = TouchGeometry.radius(
            x: Double(point.x),
            y: Double(point.y)
        )
        // Hysteresis: entering needs the ring, staying only needs to avoid the
        // middle, so a circling thumb does not drop out of scroll mode.
        let onRing = isCircular
            ? radius >= TouchGeometry.ringExitRadius
            : radius >= TouchGeometry.ringRadius
        if onRing != isCircular {
            isCircular = onRing
            lastAngle = atan2(point.y - 0.5, point.x - 0.5)
            scrollStarted = false
            scrollArmed = 0
            scrollVelocity = 0
            angularSpeed = 0
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
        // Rotate about the pad's measured centre with both axes normalised.
        // The raw sensor frame is offset by (0.015, 0.042) and its axes differ
        // in scale by 4%, which made the angular rate pulse once per turn.
        // The y sign is kept in sensor orientation so the scroll direction
        // stays as it is.
        let calibrated = TouchGeometry.normalize(
            x: Double(point.x),
            y: Double(point.y)
        )
        let angle = atan2(
            CGFloat(0.5 - calibrated.y),
            CGFloat(calibrated.x - 0.5)
        )
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
        let frameDelta = delta
        let frameSpeed = abs(frameDelta) / step
        // Gain follows a smoothed angular rate. Per-frame speed swings with
        // sensor frame jitter, and driving the curve with it made the scroll
        // accelerate and brake on its own.
        angularSpeed = angularSpeed == 0
            ? frameSpeed
            : angularSpeed * 0.72 + frameSpeed * 0.28
        let gain = scrollGain(for: angularSpeed)

        if !scrollStarted {
            scrollArmed += frameDelta
            guard abs(scrollArmed) >= scrollStartThreshold else {
                scrollVelocity *= 0.8
                return
            }
            // Spend the rotation that armed the gesture instead of dropping it,
            // otherwise every ring gesture starts with a dead 20 degrees.
            delta = scrollArmed
            scrollArmed = 0
            scrollStarted = true
        }

        let pixels = -delta * gain * scrollSpeed
        scrollTarget += pixels
        // The tail is fed by this frame's motion only; the armed backlog would
        // otherwise kick the inertia to a speed the hand never reached.
        scrollVelocity = scrollVelocity * 0.7
            + (-frameDelta * gain * scrollSpeed / step) * 0.3
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

    /// A press raises contact pressure while the finger stays put. Contact
    /// size also grows as the finger moves towards the middle of the pad, so
    /// the rise is only accepted together with near-zero travel — otherwise a
    /// drag towards the centre froze the pointer mid-motion.
    private func updatePressFreeze(
        size: CGFloat,
        point: CGPoint,
        now: TimeInterval
    ) {
        pressSamples.append(
            PressSample(time: now, size: size, point: point)
        )
        while let first = pressSamples.first,
              now - first.time > pressWindow {
            pressSamples.removeFirst()
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
        guard pressFreezeEnabled,
              pressSamples.count >= 3,
              let oldest = pressSamples.first
        else { return }
        let travel = hypot(
            point.x - oldest.point.x,
            point.y - oldest.point.y
        )
        guard travel <= pressMaxTravel else { return }
        let rise = (size - oldest.size) / max(oldest.size, 0.02)
        guard rise >= clickRiseRatio else { return }
        pressFrozen = true
        freezeOrigin = point
        onLog?(String(
            format: "press freeze base=%.3f now=%.3f travel=%.3f",
            oldest.size,
            size,
            travel
        ))
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
            // A second tap within the window consumes the deferred click and
            // runs the reserved action instead.
            if let pending = pendingTap {
                pendingTap = nil
                pending.work.cancel()
                if now - pending.at <= doubleTapWindow {
                    switch pending.action {
                    case .doubleTap:
                        onDoubleTap?()
                    case .jump(let toTop):
                        jump(toTop: toTop)
                    }
                    reset()
                    return
                }
            }

            let zone = tapZone(startPoint)
            let action: TapAction?
            if doubleTapAvailable?() ?? false {
                action = .doubleTap
            } else if let zone, isScrollEnabled {
                action = .jump(toTop: zone == .top)
            } else {
                action = nil
            }

            if let action {
                // Hold the click just long enough to see whether a second tap
                // is coming; inside the bands only, so normal clicking in the
                // middle of the pad never waits.
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.pendingTap = nil
                    self.onClick?()
                }
                pendingTap = PendingTap(at: now, action: action, work: work)
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + doubleTapWindow,
                    execute: work
                )
            } else {
                onClick?()
            }
        }
        reset()
    }

    private func tapZone(_ point: CGPoint?) -> TapZone? {
        guard let point else { return nil }
        let y = TouchGeometry.normalize(
            x: Double(point.x),
            y: Double(point.y)
        ).y
        if y <= jumpBand { return .top }
        if y >= 1 - jumpBand { return .bottom }
        return nil
    }

    private func jump(toTop: Bool) {
        stopInertia()
        scrollTarget = 0
        scrollSmoothed = 0
        scrollVelocity = 0
        onScroll?(toTop ? -jumpPixels : jumpPixels)
        // Some views clamp how far a single event may move; a second, smaller
        // event makes sure the end of the document is reached.
        onScroll?(toTop ? -jumpPixels / 4 : jumpPixels / 4)
        onJump?(toTop)
    }

    /// A new touch abandons the deferred click but keeps the record, so the
    /// second tap of a double tap can still claim the action.
    private func cancelDeferredClick() {
        pendingTap?.work.cancel()
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
        // Raw y grows towards the top of the remote, so a positive delta is
        // an upward flick.
        return dy > 0 ? .up : .down
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
        pressSamples.removeAll(keepingCapacity: true)
        stopLiftWatch()
    }
}
