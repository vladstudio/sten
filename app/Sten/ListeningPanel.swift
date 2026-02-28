// Floating panel shown during recording with audio visualizer and transcribe button
import AppKit

final class ListeningPanel: NSPanel {
    private let waveView = AudioWaveView()
    private let silentLabel = NSTextField(labelWithString: "Microphone silent")
    private var silentCount = 0
    var onCancel: (() -> Void)?
    var onTranscribe: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 260, height: 62), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        isFloatingPanel = true; level = .floating; hidesOnDeactivate = false
        appearance = NSAppearance(named: .darkAqua)

        let transcribe = NSButton(title: "Transcribe", target: self, action: #selector(doTranscribe)); transcribe.bezelStyle = .rounded; transcribe.keyEquivalent = "\r"
        let stack = NSStackView(views: [waveView, transcribe]); stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false; stack.alignment = .centerY
        guard let content = contentView else { return }
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12), stack.centerYAnchor.constraint(equalTo: content.centerYAnchor)])
        silentLabel.font = .systemFont(ofSize: 11); silentLabel.textColor = .secondaryLabelColor; silentLabel.isHidden = true; silentLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(silentLabel)
        NSLayoutConstraint.activate([silentLabel.centerXAnchor.constraint(equalTo: waveView.centerXAnchor), silentLabel.centerYAnchor.constraint(equalTo: waveView.centerYAnchor)])
    }

    func addLevel(_ level: Float) {
        if level < 1e-5 { silentCount += 1 } else { silentCount = 0 }
        silentLabel.isHidden = silentCount < 30
        waveView.addLevel(level)
    }
    @objc private func doTranscribe() { onCancel = nil; close(); onTranscribe?() }
    override func close() { let cb = onCancel; onCancel = nil; super.close(); cb?() }
    override var canBecomeKey: Bool { true }
}
