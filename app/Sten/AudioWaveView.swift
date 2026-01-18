import AppKit

final class AudioWaveView: NSView {
    private var levels: [Float] = Array(repeating: 0, count: 41)
    private var scrollOffset: CGFloat = 0
    private var timer: Timer?
    private let barWidth: CGFloat = 5, gap: CGFloat = 2

    func addLevel(_ level: Float) { levels.append(level); startAnimating() }

    private func startAnimating() {
        guard timer == nil else { return }
        timer = Timer(timeInterval: 1.0/60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        scrollOffset += (barWidth + gap) / 15 // ~4Hz arrival, 60fps = 15 frames per bar
        while scrollOffset >= barWidth + gap && levels.count > 40 {
            scrollOffset -= barWidth + gap; levels.removeFirst()
        }
        if levels.count <= 40 { timer?.invalidate(); timer = nil; scrollOffset = 0 }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(red: 0.36, green: 0.55, blue: 0.94, alpha: 1).setFill()
        let mid = bounds.midY, peak = max(levels.max() ?? 0, 0.001)
        for (i, level) in levels.enumerated() {
            let x = CGFloat(i) * (barWidth + gap) - scrollOffset
            guard x > -barWidth && x < bounds.width else { continue }
            let h = max(CGFloat(level / peak) * bounds.height * 0.8, 2)
            NSBezierPath(roundedRect: NSRect(x: x, y: mid - h / 2, width: barWidth, height: h), xRadius: 2, yRadius: 2).fill()
        }
    }

    override func removeFromSuperview() { timer?.invalidate(); super.removeFromSuperview() }
    override var intrinsicContentSize: NSSize { NSSize(width: 40 * 7, height: 34) }
}
