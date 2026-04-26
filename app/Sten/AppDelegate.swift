// Main app coordinator - manages recording, transcription, permissions, and UI state
import AppKit
import AVFoundation
import MacAppKit
import UniformTypeIdentifiers
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private static let idleUnloadSeconds: TimeInterval = 15 * 60
    private static let minAudioSamples = AudioRecorder.sampleRate / 2  // 0.5 seconds
    private static let transformTimeoutSeconds: TimeInterval = 30

    private var menu: MenuBarController!
    private let hotkey = HotkeyManager()
    private let recorder = AudioRecorder()
    private var engine = TranscriptionEngine()
    private var permissionTimer: Timer?
    private var idleTimer: Timer?
    private var memorySource: DispatchSourceMemoryPressure?
    private var pendingAudio: [Float]?
    private var engineLoading = false
    private var pendingFileURL: URL?
    private var onboarding: OnboardingPanel?
    private var listeningPanel: ListeningPanel?
    private var lastTranscription: String?
    private var capturedContext: String?
    private var transcriptionGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu = MenuBarController()
        menu.onHotkeyChange = { [weak self] start in start ? self?.hotkey.start() : self?.hotkey.stop() }
        menu.onListen = { [weak self] in self?.startListening() }
        menu.onTranscribe = { [weak self] in self?.stopListening() }
        menu.onCancel = { [weak self] in self?.cancelOperation() }
        menu.onTranscribeFile = { [weak self] in self?.transcribeFile() }
        menu.onPasteAgain = { [weak self] in self?.pasteAgain() }
        setupHotkey()

        // Unload model and tear down audio session on memory pressure
        memorySource = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        memorySource?.setEventHandler { [weak self] in
            DispatchQueue.main.async { self?.pendingAudio = nil; self?.pendingFileURL = nil; self?.engineLoading = false; self?.engine.unload(); self?.recorder.teardown() }
        }
        memorySource?.resume()

        Settings.shared.syncLoginItem()
        if Settings.shared.onboardingDone { checkPermissionsAndUpdateMenu(); StenUpdater.check() }
        else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.showOnboarding() } }
    }

    private func showOnboarding() {
        onboarding = OnboardingPanel()
        onboarding?.loadModel = { [weak self] done in
            Task { [weak self] in
                let ok = await self?.engine.load() ?? false
                await MainActor.run { done(ok) }
            }
        }
        onboarding?.onComplete = { [weak self] in self?.onboarding = nil; self?.checkPermissionsAndUpdateMenu() }
        onboarding?.onCancel = { [weak self] in self?.deleteModelAndQuit() }
        onboarding?.onChangeHotkey = { [weak self] in
            Settings.shared.onboardingDone = true
            self?.onboarding?.close()
            self?.onboarding = nil
            self?.checkPermissionsAndUpdateMenu()
            self?.menu.showHotkeyPanel(below: nil)
        }
        if let button = menu.statusButton, let w = button.window {
            onboarding?.positionBelow(w.convertToScreen(button.frame))
        }
        onboarding?.start()
        onboarding?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Check mic + accessibility permissions, show appropriate UI
    @objc func checkPermissionsAndUpdateMenu() {
        let micGranted = Permissions.isGranted(.microphone)
        let accessibilityGranted = Permissions.isGranted(.accessibility)
        if !micGranted || !accessibilityGranted {
            hotkey.stop()
            menu.showPermissionsRequired(mic: !micGranted, accessibility: !accessibilityGranted)
            startPermissionPolling()
        } else {
            stopPermissionPolling()
            if !engine.isReady { menu.state = .loading }
            menu.showNormalMenu()
            hotkey.start()
            do { try recorder.prepare() } catch { NSLog("[STEN] recorder.prepare() failed: %@", "\(error)") }
            loadEngineIfNeeded()
        }
    }

    private func startPermissionPolling() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPermissionsAndUpdateMenu()
        }
    }

    private func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    @objc func grantPermissions() {
        Permissions.request(.microphone)
        Permissions.request(.accessibility)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.checkPermissionsAndUpdateMenu()
        }
    }

    private func setupHotkey() {
        hotkey.onPress = { [weak self] in
            guard let self else { return }
            if menu.state == .idle { startListening() }
            else if menu.state == .loading { cancelOperation() }
            else if menu.state == .listening { stopListening() }
        }
        hotkey.onTapFailed = { [weak self] in
            self?.checkPermissionsAndUpdateMenu()
        }
    }

    // Load model on demand, unload after idle timeout
    private func loadEngineIfNeeded() {
        guard !engine.isReady else {
            menu.modelReady = true
            if let audio = pendingAudio { pendingAudio = nil; transcribeAudio(audio) }
            else if let url = pendingFileURL { pendingFileURL = nil; startFileTranscription(url) }
            return
        }
        guard !engineLoading else { return }
        engineLoading = true
        if menu.state != .listening { menu.state = .loading }
        Task {
            let ok = await engine.load()
            await MainActor.run {
                engineLoading = false
                menu.modelReady = ok
                if !ok {
                    pendingAudio = nil; pendingFileURL = nil
                    if menu.state == .listening { cancelOperation() }
                    else { menu.state = .idle }
                    showNotification("Model Error", "Failed to load model")
                } else if let audio = pendingAudio {
                    pendingAudio = nil; transcribeAudio(audio)
                } else if menu.state == .listening {
                    // Recording in progress, model now ready — nothing to do
                } else if let url = pendingFileURL {
                    pendingFileURL = nil; startFileTranscription(url)
                } else {
                    menu.state = .idle
                    scheduleIdleUnload()
                }
            }
        }
    }

    private func scheduleIdleUnload() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleUnloadSeconds, repeats: false) { [weak self] _ in
            self?.engine.unload()
            self?.menu.modelReady = false
        }
    }

    // Start recording immediately and load model in parallel if needed
    private func startListening() {
        capturedContext = Settings.shared.includeContext ? ContextCapture.capture() : nil
        NSLog("[STEN] startListening called, state=\(menu.state), engineReady=\(engine.isReady)")
        idleTimer?.invalidate()
        menu.state = .listening
        listeningPanel = ListeningPanel()
        listeningPanel?.onCancel = { [weak self] in self?.cancelOperation() }
        listeningPanel?.onTranscribe = { [weak self] in self?.stopListening() }
        recorder.onLevel = { [weak self] in self?.listeningPanel?.addLevel($0) }
        recorder.onMaxDuration = { [weak self] in self?.stopListening() }
        if let btn = menu.statusButton, let w = btn.window { listeningPanel?.positionBelow(w.convertToScreen(btn.frame)) }
        listeningPanel?.makeKeyAndOrderFront(nil)
        recorder.onError = { [weak self] msg in
            guard let self, menu.state == .listening else { return }
            NSLog("[STEN] recorder error: %@", msg)
            self.cancelOperation()
            self.showNotification("Recording Failed", "\(msg). Check System Settings.")
        }
        do { try recorder.start() } catch {
            NSLog("[STEN] recorder.start() FAILED: \(error)")
            recorder.onError = nil
            closeListeningPanel()
            menu.state = .idle
            showNotification("Recording Failed", "\(error.localizedDescription)")
            return
        }
        listeningPanel?.title = AVCaptureDevice.default(for: .audio)?.localizedName ?? ""
        if !engine.isReady { loadEngineIfNeeded() }
    }

    private func closeListeningPanel() {
        let panel = listeningPanel
        listeningPanel = nil
        recorder.onLevel = nil
        recorder.onMaxDuration = nil
        panel?.onCancel = nil
        panel?.close()
    }

    // Stop recording, transcribe (or wait for model), apply transforms, output text
    private func stopListening() {
        NSLog("[STEN] stopListening called, state=\(menu.state)")
        recorder.onError = nil
        let audio = recorder.stop()
        let peak = audio.reduce(Float(0)) { max($0, abs($1)) }
        NSLog("[STEN] audio samples=\(audio.count), minRequired=\(Self.minAudioSamples), peak=\(peak)")
        closeListeningPanel()
        guard audio.count > Self.minAudioSamples, peak > 1e-4 else {
            NSLog("[STEN] insufficient audio, discarding")
            menu.state = .idle
            scheduleIdleUnload()
            return
        }
        if engine.isReady {
            transcribeAudio(audio)
        } else {
            pendingAudio = audio
            menu.state = .loading
        }
    }

    private func transcribeAudio(_ audio: [Float]) {
        menu.state = .transcribing
        transcriptionGeneration += 1
        let gen = transcriptionGeneration
        let context = capturedContext
        Task { [weak self] in
            guard let self else { return }
            let text = await engine.transcribe(audio)
            NSLog("[STEN] transcription result: \(text ?? "nil")")
            let transformed = (text?.isEmpty == false) ? await self.applyTransforms(text!, context: context) : nil
            await MainActor.run {
                guard gen == self.transcriptionGeneration else { return }
                self.menu.state = .idle
                self.scheduleIdleUnload()
                if let transformed { self.outputText(transformed) }
                else { NSLog("[STEN] no output — text was nil or empty") }
            }
        }
    }

    private static let audioFileTypes = ["wav", "mp3", "m4a", "aiff", "aif", "caf", "flac", "mp4", "mov"]

    private func transcribeFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.audioFileTypes.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an audio file to transcribe"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        idleTimer?.invalidate()
        guard engine.isReady else {
            pendingFileURL = url
            loadEngineIfNeeded()
            return
        }
        startFileTranscription(url)
    }

    private func startFileTranscription(_ url: URL) {
        menu.state = .transcribing
        transcriptionGeneration += 1
        let gen = transcriptionGeneration
        Task { [weak self] in
            guard let self else { return }
            let text = await engine.transcribe(url)
            NSLog("[STEN] file transcription result length: \(text?.count ?? 0)")
            let transformed = (text?.isEmpty == false) ? await self.applyTransforms(text!, context: nil) : nil
            await MainActor.run {
                guard gen == self.transcriptionGeneration else { return }
                self.menu.state = .idle
                self.scheduleIdleUnload()
                guard let transformed else {
                    self.showNotification("Transcription Failed", "Could not transcribe \(url.lastPathComponent)")
                    return
                }
                let outURL = url.deletingPathExtension().appendingPathExtension("txt")
                do {
                    try transformed.write(to: outURL, atomically: true, encoding: .utf8)
                    self.showNotification("Transcription Complete", outURL.lastPathComponent)
                } catch {
                    self.showNotification("Write Failed", "Could not save \(outURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
    }

    private func cancelOperation() {
        NSLog("[STEN] cancelOperation called, state=\(menu.state)")
        transcriptionGeneration += 1
        closeListeningPanel()
        if menu.state == .listening || menu.state == .loading {
            pendingAudio = nil
            pendingFileURL = nil
            recorder.onError = nil
            _ = recorder.stop()
            menu.state = .idle
        }
        else if menu.state == .transcribing { menu.state = .idle }
        scheduleIdleUnload()
    }

    // Inject text into active app or show notification
    private func outputText(_ text: String) {
        lastTranscription = text
        menu.hasLastTranscription = true
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            showNotification("Transcription", text)
            return
        }
        if !TextInjector.inject(text) { showNotification("Transcription", text) }
    }

    private func pasteAgain() {
        guard let text = lastTranscription else { return }
        outputText(text)
    }

    // Run enabled Tetra commands sequentially, piping text through each
    private func applyTransforms(_ text: String, context: String?) async -> String {
        guard Settings.shared.transformText else { return text }
        let enabled = Settings.shared.enabledTransforms
        guard !enabled.isEmpty else { return text }
        let args = context.map { ["context": $0] }
        var result = text
        for command in enabled.sorted() {
            if let output = await tetraTransform(command: command, text: result, args: args) { result = output }
        }
        return result
    }

    private func tetraTransform(command: String, text: String, args: [String: String]?) async -> String? {
        var request = URLRequest(url: URL(string: "http://localhost:\(Settings.shared.tetraPort)/transform")!,
                                 timeoutInterval: Self.transformTimeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["command": command, "text": text]
        if let args { body["args"] = args }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? String, !result.isEmpty else { return nil }
            return result
        } catch {
            NSLog("[STEN] transform '%@' failed: %@", command, error.localizedDescription)
            return nil
        }
    }

    private func showNotification(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    func deleteModelAndQuit() {
        if let dir = TranscriptionEngine.modelDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        NSApp.terminate(nil)
    }
}
