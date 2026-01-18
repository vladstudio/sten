import AppKit

final class ListeningPanel: NSPanel {
    private let waveView = AudioWaveView()
    var onCancel: (() -> Void)?
    var onTranscribe: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 260, height: 62), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        isFloatingPanel = true; level = .floating; hidesOnDeactivate = false
        appearance = NSAppearance(named: .darkAqua)

        let transcribe = NSButton(title: "Transcribe", target: self, action: #selector(doTranscribe)); transcribe.bezelStyle = .rounded; transcribe.keyEquivalent = "\r"
        let stack = NSStackView(views: [waveView, transcribe]); stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false; stack.alignment = .centerY
        contentView?.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor, constant: -12), stack.centerYAnchor.constraint(equalTo: contentView!.centerYAnchor)])
    }

    private var isTranscribing = false
    func addLevel(_ level: Float) { waveView.addLevel(level) }
    @objc private func doTranscribe() { isTranscribing = true; close(); onTranscribe?() }
    override func close() { super.close(); if !isTranscribing { onCancel?() } }
    override var canBecomeKey: Bool { true }
}
