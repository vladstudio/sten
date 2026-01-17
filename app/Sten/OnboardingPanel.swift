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
    var loadModel: ((@escaping (Bool) -> Void) -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
        title = "Welcome to Sten"
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)

        label.font = .systemFont(ofSize: 13)
        label.alignment = .center
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(primaryAction)

        secondaryButton.bezelStyle = .rounded
        secondaryButton.target = self
        secondaryButton.action = #selector(secondaryAction)
        secondaryButton.isHidden = true

        let btnRow = NSStackView(views: [secondaryButton, button])
        btnRow.spacing = 8

        stack.addArrangedSubview(label)
        stack.addArrangedSubview(btnRow)
        contentView = stack
    }

    func start() { step = .welcome }

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
            label.stringValue = "Thanks for installing Sten!\nWe need a few permissions to get started."
            button.title = "Next"
        case .mic:
            label.stringValue = "Sten needs microphone access to hear your voice."
            button.title = "Grant Microphone Access"
        case .accessibility:
            label.stringValue = "Sten needs accessibility access to type text into other apps.\n\nClick the button, then enable Sten in System Settings."
            button.title = "Open System Settings"
            startPolling { AXIsProcessTrusted() } then: { [weak self] in self?.nextStep() }
        case .model:
            label.stringValue = "Downloading speech recognition model...\nThis runs entirely on your device for privacy."
            button.title = "Downloading..."
            button.isEnabled = false
            loadModel? { [weak self] ok in
                DispatchQueue.main.async {
                    self?.button.isEnabled = true
                    if ok { self?.step = .done }
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

    @objc private func secondaryAction() { onChangeHotkey?() }

    private func startPolling(check: @escaping () -> Bool, then: @escaping () -> Void) {
        checkTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] t in
            if check() { t.invalidate(); self?.checkTimer = nil; then() }
        }
        RunLoop.main.add(checkTimer!, forMode: .common)
    }

    override var canBecomeKey: Bool { true }
    override func close() { checkTimer?.invalidate(); super.close() }
}
