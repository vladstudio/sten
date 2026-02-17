// First-run wizard - guides through permissions, model download, and optional transform setup
import AppKit
import AVFoundation

final class OnboardingPanel: NSPanel {
    enum Step { case welcome, mic, accessibility, model, transforms, done }

    private let label = NSTextField(wrappingLabelWithString: "")
    private let button = NSButton(title: "", target: nil, action: nil)
    private let secondaryButton = NSButton(title: "", target: nil, action: nil)
    private let providerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var step: Step = .welcome { didSet { updateUI() } }
    private var checkTimer: Timer?
    var onComplete: (() -> Void)?
    var onChangeHotkey: (() -> Void)?
    var onCancel: (() -> Void)?
    var loadModel: ((@escaping (Bool) -> Void) -> Void)?

    private static let providers: [(name: String, configKey: String, envKey: String, keyURL: String)] = [
        ("Gemini", "gemini_api_key", "GEMINI_API_KEY", "https://aistudio.google.com/app/apikey"),
        ("OpenAI", "openai_api_key", "OPENAI_API_KEY", "https://platform.openai.com/api-keys"),
        ("Anthropic", "anthropic_api_key", "ANTHROPIC_API_KEY", "https://console.anthropic.com/settings/keys"),
    ]
    private static let configFile = Settings.stenDir.appendingPathComponent("config.json")
    private static let transformScript = MenuBarController.transformsDir.appendingPathComponent("01 Grammar and Custom Words.rb")

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
        providerPopup.addItems(withTitles: Self.providers.map(\.name)); providerPopup.isHidden = true

        let btnRow = NSStackView(views: [secondaryButton, button]); btnRow.spacing = 8
        let stack = NSStackView(views: [icon, label, providerPopup, btnRow])
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
        else if !FileManager.default.fileExists(atPath: Self.transformScript.path) { step = .transforms }
        else { step = .done }
    }

    private func updateUI() {
        checkTimer?.invalidate()
        secondaryButton.isHidden = true
        providerPopup.isHidden = true
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
        case .transforms:
            label.stringValue = "Text Transforms can fix grammar, spelling, or apply custom rules.\nSelect your LLM provider to create a grammar transform."
            providerPopup.isHidden = false
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

    private func createTransformScript() {
        let idx = providerPopup.indexOfSelectedItem
        if let key = ProcessInfo.processInfo.environment[Self.providers[idx].envKey], !key.isEmpty {
            saveApiKey(key, provider: idx); writeTransformScript(provider: idx); step = .done
        } else { promptForApiKey(provider: idx) }
    }

    private func promptForApiKey(provider idx: Int) {
        let p = Self.providers[idx]
        let alert = NSAlert()
        alert.messageText = "Enter \(p.name) API Key"
        alert.informativeText = "Get your API key at:\n\(p.keyURL)"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "API Key"
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: self) { [weak self] response in
            if response == .alertFirstButtonReturn, !field.stringValue.isEmpty {
                self?.saveApiKey(field.stringValue, provider: idx)
                self?.writeTransformScript(provider: idx)
            }
            self?.step = .done
        }
    }

    private func saveApiKey(_ key: String, provider idx: Int) {
        let url = Self.configFile
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config: [String: String] = [:]
        if let data = try? Data(contentsOf: url), let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] { config = json }
        config[Self.providers[idx].configKey] = key
        if let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }

    private func writeTransformScript(provider idx: Int) {
        let p = Self.providers[idx]
        let apiCall: String
        switch idx {
        case 0: apiCall = """
            uri = URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=#{api_key}")
            response = Net::HTTP.post(uri, { contents: [{ parts: [{ text: PROMPT + text }] }] }.to_json, 'Content-Type' => 'application/json')
            result = JSON.parse(response.body).dig('candidates', 0, 'content', 'parts', 0, 'text') rescue nil
            """
        case 1: apiCall = """
            uri = URI("https://api.openai.com/v1/chat/completions")
            response = Net::HTTP.post(uri, { model: 'gpt-5-nano', messages: [{ role: 'user', content: PROMPT + text }] }.to_json, 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{api_key}")
            result = JSON.parse(response.body).dig('choices', 0, 'message', 'content') rescue nil
            """
        case 2: apiCall = """
            uri = URI("https://api.anthropic.com/v1/messages")
            response = Net::HTTP.post(uri, { model: 'claude-haiku-4-5-20251001', max_tokens: 1024, messages: [{ role: 'user', content: PROMPT + text }] }.to_json, 'Content-Type' => 'application/json', 'x-api-key' => api_key, 'anthropic-version' => '2023-06-01')
            result = JSON.parse(response.body).dig('content', 0, 'text') rescue nil
            """
        default: assertionFailure("Unknown provider index: \(idx)"); return
        }
        let script = """
        #!/usr/bin/env ruby
        require 'json'; require 'net/http'; require 'uri'
        CUSTOM_WORDS = "Sten"
        PROMPT = "You are given a speech-to-text transcription. Correct grammar, spelling, and misrecognized words based on context. Correct these special words or their misspellings to exact spellings: #{CUSTOM_WORDS}. OUTPUT ONLY THE CORRECTED TEXT. Transcription: "
        config = JSON.parse(File.read(File.join(Dir.home, '.sten', 'config.json'))) rescue {}
        api_key = config['\(p.configKey)'] || ENV['\(p.envKey)']
        text = STDIN.read
        exit 1 if text.empty?
        (puts text; exit 0) if api_key.to_s.empty?
        \(apiCall)
        puts result || text
        """
        do {
            try FileManager.default.createDirectory(at: MenuBarController.transformsDir, withIntermediateDirectories: true)
            try script.write(to: Self.transformScript, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: Self.transformScript.path)
            var enabled = Settings.shared.enabledTransforms
            enabled.insert("01 Grammar and Custom Words.rb")
            Settings.shared.enabledTransforms = enabled
        } catch {}
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
