import AppKit
import SwiftUI

// Looping animations that Core Animation plays in the window server. A SwiftUI animation or a
// TimelineView runs SwiftUI's update of the window's layers, and sends the whole layer tree to the
// window server, on every frame: 9 to 17% CPU in the open dashboard for a pinging dot and moving
// dashes. These layers cost the app nothing per frame. Like the clock-driven versions they run
// at 30 frames a second and stand still while the window is hidden or another app is in front,
// so the window server does no more than before.

/// A ring that pings outwards from a status dot every 2.4 seconds. All rings on screen ping
/// together.
struct PingRing: NSViewRepresentable {
    let color: Color
    @Environment(\.isOnScreen) private var isOnScreen
    @Environment(\.appearsActive) private var appearsActive

    func makeNSView(context: Context) -> PingRingView { PingRingView() }

    func updateNSView(_ view: PingRingView, context: Context) {
        view.color = NSColor(color)
        view.isRunning = isOnScreen && appearsActive
    }
}

final class PingRingView: LoopingLayerView {
    private static let period = 2.4
    private let ring = CAShapeLayer()

    var color = NSColor.controlAccentColor {
        didSet { updateColors() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        ring.fillColor = nil
        ring.lineWidth = 1.5
        // Hidden between runs: the ring shows only while it pings.
        ring.opacity = 0
        layer?.addSublayer(ring)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        withoutImplicitAnimations {
            ring.frame = bounds
            ring.path = CGPath(ellipseIn: bounds.insetBy(dx: 0.75, dy: 0.75), transform: nil)
        }
    }

    override func updateColors() {
        withoutImplicitAnimations { ring.strokeColor = resolved(color) }
    }

    override func startAnimating() {
        guard ring.animation(forKey: "ping") == nil else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.6
        scale.toValue = 1.6
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.5
        fade.toValue = 0
        let ping = CAAnimationGroup()
        ping.animations = [scale, fade]
        ping.duration = Self.period
        // Ease out, like a cubic: fast at first, settling as it fades.
        ping.timingFunction = CAMediaTimingFunction(controlPoints: 0.33, 1, 0.68, 1)
        loop(ping, period: Self.period)
        ring.add(ping, forKey: "ping")
    }

    override func stopAnimating() {
        ring.removeAnimation(forKey: "ping")
    }
}

/// Dashes moving along a wire, 18 points every 1.2 seconds.
struct FlowingDashes: NSViewRepresentable {
    let path: Path
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isOnScreen) private var isOnScreen
    @Environment(\.appearsActive) private var appearsActive

    func makeNSView(context: Context) -> FlowingDashesView { FlowingDashesView() }

    func updateNSView(_ view: FlowingDashesView, context: Context) {
        view.path = path.cgPath
        view.color = NSColor(color)
        view.isRunning = !reduceMotion && isOnScreen && appearsActive
    }
}

final class FlowingDashesView: LoopingLayerView {
    private static let period = 1.2
    /// One dash and its gap.
    private static let length: CGFloat = 18
    private let line = CAShapeLayer()

    var path: CGPath? {
        didSet {
            if path != oldValue { withoutImplicitAnimations { line.path = path } }
        }
    }
    var color = NSColor.secondaryLabelColor {
        didSet { updateColors() }
    }

    // The wire's path is in SwiftUI's coordinates, top left first.
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        line.fillColor = nil
        line.lineWidth = 2
        line.lineCap = .round
        line.lineDashPattern = [6, 12]
        layer?.addSublayer(line)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        withoutImplicitAnimations { line.frame = bounds }
    }

    override func updateColors() {
        withoutImplicitAnimations { line.strokeColor = resolved(color) }
    }

    override func startAnimating() {
        guard line.animation(forKey: "flow") == nil else { return }
        let flow = CABasicAnimation(keyPath: "lineDashPhase")
        flow.fromValue = 0
        flow.toValue = -Self.length
        flow.duration = Self.period
        loop(flow, period: Self.period)
        line.add(flow, forKey: "flow")
    }

    override func stopAnimating() {
        line.removeAnimation(forKey: "flow")
    }
}

/// A layer-backed view for a looping animation. It never takes the mouse, runs while
/// `isRunning`, and starts again when put back in a window: AppKit drops a layer's animations
/// when its view leaves one.
class LoopingLayerView: NSView {
    var isRunning = false {
        didSet {
            guard isRunning != oldValue else { return }
            if isRunning, window != nil { startAnimating() } else { stopAnimating() }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        updateColors()
        if isRunning { startAnimating() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    func updateColors() {}
    func startAnimating() {}
    func stopAnimating() {}

    /// Repeats the animation forever at 30 frames a second, placed where it would be had it
    /// started at the reference date, so every copy on screen runs in step.
    func loop(_ animation: CAAnimation, period: TimeInterval) {
        animation.repeatCount = .infinity
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        animation.beginTime =
            CACurrentMediaTime() - Date.now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
    }

    /// A system color resolved for this view's light or dark appearance.
    func resolved(_ color: NSColor) -> CGColor {
        var resolved = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { resolved = color.cgColor }
        return resolved
    }

    func withoutImplicitAnimations(_ change: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        change()
        CATransaction.commit()
    }
}
