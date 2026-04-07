// First-run wizard - guides through permissions, model download, and optional transform setup
import AppKit
import AVFoundation

final class OnboardingPanel: NSPanel {
    enum Step { case welcome, mic, accessibility, model, done }

    private let label = NSTextField(wrappingLabelWithString: "")
    private let button = NSButton(title: "", target: nil, action: nil)
    private let secondaryButton = NSButton(title: "", target: nil, action: nil)
    private var step: Step = .welcome { didSet { updateUI() } }
    private var checkTimer: Timer?
    var onComplete: (() -> Void)?
    var onChangeHotkey: (() -> Void)?
    var onCancel: (() -> Void)?
    var loadModel: ((@escaping (Bool) -> Void) -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 280), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "Welcome to Sten"; isFloatingPanel = true; level = .floating; hidesOnDeactivate = false

        let icon = NSImageView()
        if let url = Bundle.main.url(forResource: "Sten", withExtension: "png") { icon.image = NSImage(contentsOf: url) }
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentHuggingPriority(.required, for: .vertical)
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 100), icon.heightAnchor.constraint(equalToConstant: 100)])

        label.font = .systemFont(ofSize: 13); label.alignment = .center
        button.bezelStyle = .rounded; button.target = self; button.action = #selector(primaryAction)
        secondaryButton.bezelStyle = .rounded; secondaryButton.target = self; secondaryButton.action = #selector(secondaryAction); secondaryButton.isHidden = true

        let btnRow = NSStackView(views: [secondaryButton, button]); btnRow.spacing = 8
        let stack = NSStackView(views: [icon, label, btnRow])
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(); container.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: container.centerXAnchor), stack.centerYAnchor.constraint(equalTo: container.centerYAnchor), stack.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -40)])
        contentView = container
    }

    func start() { step = .welcome }

    // Determine next step based on what's still needed
    private func nextStep() {
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized { step = .mic }
        else if !AXIsProcessTrusted() { step = .accessibility }
        else if loadModel != nil { step = .model }
        else { step = .done }
    }

    private func updateUI() {
        checkTimer?.invalidate()
        secondaryButton.isHidden = true
        button.isEnabled = true
        switch step {
        case .welcome:
            label.stringValue = "Thanks for installing Sten!\nLet's get started."
            button.title = "Next"
        case .mic:
            label.stringValue = "Sten needs microphone access to hear your voice."
            button.title = "Grant Microphone Access"
        case .accessibility:
            label.stringValue = "Sten needs accessibility access to type text into other apps.\n\nClick the button, then enable Sten in System Settings."
            button.title = "Open System Settings"
            startPolling(check: { AXIsProcessTrusted() }, then: { [weak self] in self?.nextStep() })
        case .model:
            label.stringValue = "Downloading speech recognition model...\nThis runs entirely on your device."
            button.title = "Downloading..."
            button.isEnabled = false
            secondaryButton.title = "Cancel"
            secondaryButton.isHidden = false
            loadModel? { [weak self] ok in
                DispatchQueue.main.async {
                    self?.button.isEnabled = true
                    self?.secondaryButton.isHidden = true
                    if ok { self?.loadModel = nil; self?.nextStep() }
                    else { self?.button.title = "Retry"; self?.label.stringValue = "Download failed. Check your connection." }
                }
            }
        case .done:
            let hk = HotkeyPanel.hotkeyString(Settings.shared.hotkeyCode, CGEventFlags(rawValue: Settings.shared.hotkeyModifiers))
            label.stringValue = "All set! Press \(hk) to speak.\nPress again to insert text into the active app."
            button.title = "Done"
            secondaryButton.title = "Change Hotkey"
            secondaryButton.isHidden = false
        }
    }

    @objc private func primaryAction() {
        switch step {
        case .welcome: nextStep()
        case .mic: AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in DispatchQueue.main.async { self?.nextStep() } }
        case .accessibility:
            if AXIsProcessTrusted() { nextStep() }
            else { AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) }
        case .model: step = .model // retry
        case .done: Settings.shared.onboardingDone = true; close(); onComplete?()
        }
    }

    @objc private func secondaryAction() {
        if step == .model { onCancel?() } else { onChangeHotkey?() }
    }

    // Poll condition until true, then call callback
    private func startPolling(check: @escaping () -> Bool, then: @escaping () -> Void) {
        checkTimer?.invalidate()
        checkTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] t in
            if check() { t.invalidate(); self?.checkTimer = nil; then() }
        }
        if let timer = checkTimer { RunLoop.main.add(timer, forMode: .common) }
    }

    override var canBecomeKey: Bool { true }
    override func close() { checkTimer?.invalidate(); super.close(); if !Settings.shared.onboardingDone { NSApp.terminate(nil) } }
}
