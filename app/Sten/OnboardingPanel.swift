// First-run wizard - guides through permissions, model download, and optional transform setup
import AppKit
import AVFoundation

final class OnboardingPanel: NSPanel {
    enum Step { case welcome, mic, accessibility, model, transforms, done }

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

    private static let transformScript = MenuBarController.transformsDir.appendingPathComponent("01 Grammar and Custom Words.rb")

    // Determine next step based on what's still needed
    private func nextStep() {
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized { step = .mic }
        else if !AXIsProcessTrusted() { step = .accessibility }
        else if loadModel != nil { step = .model }
        else if !FileManager.default.fileExists(atPath: Self.transformScript.path) { step = .transforms }
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
            label.stringValue = "Downloading speech recognition model...\nThis runs entirely on your device for privacy."
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
        case .transforms:
            label.stringValue = "Text Transforms can fix grammar, spelling, or apply custom rules.\nCreate a grammar-fixing transform powered by Gemini AI?\n\nGemini API key is required."
            button.title = "Create Text Transform"
            secondaryButton.title = "Skip"
            secondaryButton.isHidden = false
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
        case .transforms: createTransformScript()
        case .done: Settings.shared.onboardingDone = true; close(); onComplete?()
        }
    }

    @objc private func secondaryAction() {
        if step == .model { onCancel?() } else if step == .transforms { step = .done } else { onChangeHotkey?() }
    }

    // Create default Gemini-powered grammar transform script
    private func createTransformScript() {
        if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty {
            writeTransformScript(apiKey: key); step = .done
        } else { promptForApiKey() }
    }

    private func promptForApiKey() {
        let alert = NSAlert()
        alert.messageText = "Enter Gemini API Key"
        alert.informativeText = "Get your free API key at:\nhttps://aistudio.google.com/app/apikey"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "API Key"
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: self) { [weak self] response in
            if response == .alertFirstButtonReturn, !field.stringValue.isEmpty {
                self?.writeTransformScript(apiKey: field.stringValue)
            }
            self?.step = .done
        }
    }

    private func writeTransformScript(apiKey: String?) {
        let keyLine = apiKey.map { "api_key = \"\($0)\"" } ?? "api_key = ENV['GEMINI_API_KEY']"
        let script = """
        #!/usr/bin/env ruby
        require 'json'; require 'net/http'; require 'uri'
        CUSTOM_WORDS = "Sten"
        PROMPT = "You are given a speech-to-text transcription. Correct grammar, spelling, and misrecognized words based on context. Correct these special words or their misspellings to exact spellings: #{CUSTOM_WORDS}. OUTPUT ONLY THE CORRECTED TEXT. Transcription: "
        \(keyLine)
        text = STDIN.read
        exit 1 if text.empty?
        (puts text; exit 0) if api_key.nil? || api_key.empty?
        uri = URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=#{api_key}")
        response = Net::HTTP.post(uri, { contents: [{ parts: [{ text: PROMPT + text }] }] }.to_json, 'Content-Type' => 'application/json')
        result = JSON.parse(response.body).dig('candidates', 0, 'content', 'parts', 0, 'text') rescue nil
        puts result || text
        """
        try? FileManager.default.createDirectory(at: MenuBarController.transformsDir, withIntermediateDirectories: true)
        try? script.write(to: Self.transformScript, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: Self.transformScript.path)
        Settings.shared.enabledTransforms.insert("01 Grammar and Custom Words.rb")
    }

    // Poll condition until true, then call callback
    private func startPolling(check: @escaping () -> Bool, then: @escaping () -> Void) {
        checkTimer?.invalidate()
        checkTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] t in
            if check() { t.invalidate(); self?.checkTimer = nil; then() }
        }
        RunLoop.main.add(checkTimer!, forMode: .common)
    }

    override var canBecomeKey: Bool { true }
    override func close() { checkTimer?.invalidate(); super.close(); if !Settings.shared.onboardingDone { NSApp.terminate(nil) } }
}
