import AppKit

final class AudioWaveView: NSView {
    private var levels: [Float] = Array(repeating: 0, count: 41)
    private var display: [CGFloat] = Array(repeating: 0, count: 41) // animated normalized heights
    private var scrollOffset: CGFloat = 0
    private var timer: Timer?
    private let barWidth: CGFloat = 3, gap: CGFloat = 2

    func addLevel(_ level: Float) { levels.append(level); display.append(0); startAnimating() }

    private func startAnimating() {
        guard timer == nil else { return }
        timer = Timer(timeInterval: 1.0/60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        scrollOffset += (barWidth + gap) / 15
        while scrollOffset >= barWidth + gap && levels.count > 40 {
            scrollOffset -= barWidth + gap; levels.removeFirst(); display.removeFirst()
        }
        if levels.count <= 40 { timer?.invalidate(); timer = nil; scrollOffset = 0 }
        let peak = max(levels.max() ?? 0, 0.001)
        for i in levels.indices { display[i] += (CGFloat(levels[i] / peak) - display[i]) * 0.25 }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let mid = bounds.midY
        for (i, d) in display.enumerated() {
            let x = CGFloat(i) * (barWidth + gap) - scrollOffset
            guard x > -barWidth && x < bounds.width else { continue }
            let h = max(d * bounds.height * 0.8, 2)
            (h < barWidth ? NSColor.secondaryLabelColor.withAlphaComponent(0.2) : NSColor.controlAccentColor).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: mid - h / 2, width: barWidth, height: h), xRadius: 2, yRadius: 2).fill()
        }
    }

    override func removeFromSuperview() { timer?.invalidate(); super.removeFromSuperview() }
    override var intrinsicContentSize: NSSize { NSSize(width: 40 * 5, height: 28) }
}
