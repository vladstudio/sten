import AppKit

final class ListeningPanel: NSPanel {
    private let waveView = AudioWaveView()
    var onCancel: (() -> Void)?
    var onTranscribe: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 110), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        titlebarAppearsTransparent = true; titleVisibility = .hidden; isFloatingPanel = true; level = .floating; hidesOnDeactivate = false

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(doCancel)); cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"
        let transcribe = NSButton(title: "Transcribe", target: self, action: #selector(doTranscribe)); transcribe.bezelStyle = .rounded; transcribe.keyEquivalent = "\r"

        let hotkey = HotkeyPanel.hotkeyString(Settings.shared.hotkeyCode, CGEventFlags(rawValue: Settings.shared.hotkeyModifiers))
        let cancelHint = NSTextField(labelWithString: "Esc"); cancelHint.font = .systemFont(ofSize: 10); cancelHint.textColor = .tertiaryLabelColor
        let transcribeHint = NSTextField(labelWithString: hotkey); transcribeHint.font = .systemFont(ofSize: 10); transcribeHint.textColor = .tertiaryLabelColor

        let cancelStack = NSStackView(views: [cancel, cancelHint]); cancelStack.orientation = .vertical; cancelStack.spacing = 2; cancelStack.alignment = .centerX
        let transcribeStack = NSStackView(views: [transcribe, transcribeHint]); transcribeStack.orientation = .vertical; transcribeStack.spacing = 2; transcribeStack.alignment = .centerX
        let buttons = NSStackView(views: [cancelStack, transcribeStack]); buttons.spacing = 16

        waveView.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [waveView, buttons]); stack.orientation = .vertical; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = false

        contentView?.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: contentView!.centerXAnchor), stack.centerYAnchor.constraint(equalTo: contentView!.centerYAnchor, constant: 4)])
    }

    func addLevel(_ level: Float) { waveView.addLevel(level) }
    @objc private func doCancel() { close(); onCancel?() }
    @objc private func doTranscribe() { close(); onTranscribe?() }
    override var canBecomeKey: Bool { true }
}
