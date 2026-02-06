// Animated audio level visualizer using Core Animation
// Bars scroll continuously left; heights normalized to visible peak
import AppKit
import QuartzCore

final class AudioWaveView: NSView {
    private struct Bar {
        let layer: CAShapeLayer
        let level: Float
        let x: CGFloat
        let time: CFTimeInterval
    }

    private let barWidth: CGFloat = 3
    private let gap: CGFloat = 2                 // Spacing between bars
    private let speed: CGFloat = 25              // Scroll speed in pixels/sec
    private let scrollDistance: CGFloat = 10000  // Virtual container width
    private let minPeak: Float = 0.001
    private let minHeight: CGFloat = 2
    private let cornerRadius: CGFloat = 1.5

    private var container: CALayer?
    private var bars: [Bar] = []
    private var peak: Float = 0.001
    private var animationStart: CFTimeInterval = 0
    private var updateTimer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func layout() {
        super.layout()
        guard bounds.height > 0, container == nil else { return }

        // Gradient mask fades bars on the left edge
        let mask = CAGradientLayer()
        mask.frame = bounds
        mask.colors = [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 1)]
        mask.locations = [0, 0.4]
        mask.startPoint = CGPoint(x: 0, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.mask = mask

        // Static center line
        let line = CAShapeLayer()
        line.path = CGPath(rect: CGRect(x: 0, y: bounds.midY - 0.5, width: bounds.width, height: 1), transform: nil)
        line.fillColor = NSColor.secondaryLabelColor.withAlphaComponent(0.2).cgColor
        layer?.addSublayer(line)

        // Container layer scrolls infinitely via CABasicAnimation
        let c = CALayer()
        c.anchorPoint = .zero
        c.position = .zero
        c.bounds = CGRect(x: 0, y: 0, width: scrollDistance, height: bounds.height)
        layer?.masksToBounds = true
        layer?.addSublayer(c)
        container = c
        animationStart = CACurrentMediaTime()

        let anim = CABasicAnimation(keyPath: "position.x")
        anim.fromValue = 0
        anim.toValue = -scrollDistance
        anim.duration = scrollDistance / speed
        anim.repeatCount = .infinity
        c.add(anim, forKey: "scroll")

        // Timer updates bar heights as peak changes
        updateTimer = Timer(timeInterval: 1.0/30, repeats: true) { [weak self] _ in self?.updateBars() }
        RunLoop.main.add(updateTimer!, forMode: .common)
    }

    private func updateBars() {
        // Calculate current scroll position
        let elapsed = CACurrentMediaTime() - animationStart
        let scrollOffset = CGFloat(elapsed.truncatingRemainder(dividingBy: scrollDistance / speed)) * speed

        // Peak is max level of currently visible bars only
        var visiblePeak: Float = minPeak
        for bar in bars {
            let screenX = bar.x - scrollOffset
            if screenX > -barWidth && screenX < bounds.width {
                visiblePeak = max(visiblePeak, bar.level)
            }
        }
        peak = max(peak * 0.9, visiblePeak)  // Decay peak gradually

        for bar in bars {
            updateBarAppearance(bar)
        }

        // Remove bars that have scrolled off screen
        let cutoff = CACurrentMediaTime() - (bounds.width + 50) / speed
        while let first = bars.first, first.time < cutoff {
            first.layer.removeFromSuperlayer()
            bars.removeFirst()
        }
    }

    private func updateBarAppearance(_ bar: Bar) {
        let h = max(CGFloat(bar.level / peak) * bounds.height, minHeight)
        bar.layer.path = CGPath(roundedRect: CGRect(x: bar.x, y: (bounds.height - h) / 2, width: barWidth, height: h),
                                cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        bar.layer.fillColor = NSColor.controlAccentColor.cgColor
    }

    // Called by AudioRecorder with RMS level for each audio buffer
    func addLevel(_ level: Float) {
        guard let container, bounds.height > 0 else { return }

        peak = max(peak, level, minPeak)

        // Position bar at right edge of visible area (accounting for scroll)
        let elapsed = CACurrentMediaTime() - animationStart
        let scrolled = CGFloat(elapsed.truncatingRemainder(dividingBy: scrollDistance / speed)) * speed
        let x = bounds.width + scrolled

        // Skip if too close to previous bar
        if let last = bars.last, x - last.x < barWidth + gap { return }

        let layer = CAShapeLayer()
        container.addSublayer(layer)

        let bar = Bar(layer: layer, level: level, x: x, time: CACurrentMediaTime())
        bars.append(bar)
        updateBarAppearance(bar)
    }

    override func removeFromSuperview() {
        container?.removeAllAnimations()
        updateTimer?.invalidate()
        super.removeFromSuperview()
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 200, height: 28) }
}
