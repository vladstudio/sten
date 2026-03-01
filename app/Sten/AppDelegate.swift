// Main app coordinator - manages recording, transcription, permissions, and UI state
import AppKit
import AVFoundation
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
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
    private var pendingListen = false
    private var onboarding: OnboardingPanel?
    private var listeningPanel: ListeningPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu = MenuBarController()
        menu.onHotkeyChange = { [weak self] start in start ? self?.hotkey.start() : self?.hotkey.stop() }
        menu.onListen = { [weak self] in self?.startListening() }
        menu.onTranscribe = { [weak self] in self?.stopListening() }
        menu.onCancel = { [weak self] in self?.cancelOperation() }
        setupHotkey()

        // Unload model and tear down audio session on memory pressure
        memorySource = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        memorySource?.setEventHandler { [weak self] in self?.pendingListen = false; self?.engine.unload(); self?.recorder.teardown() }
        memorySource?.resume()

        Settings.shared.syncLoginItem()
        if Settings.shared.onboardingDone { checkPermissionsAndUpdateMenu(); UpdateChecker.check() }
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
        let micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let accessibilityGranted = AXIsProcessTrusted()
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
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            DispatchQueue.main.async { self?.checkPermissionsAndUpdateMenu() }
        }
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
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
            if pendingListen { pendingListen = false; startListening() }
            return
        }
        menu.state = .loading
        Task {
            let ok = await engine.load()
            await MainActor.run {
                menu.modelReady = ok; menu.state = .idle
                if !ok { pendingListen = false; showNotification("Model Error", "Failed to load model") }
                else if pendingListen { pendingListen = false; startListening() }
                else { scheduleIdleUnload() }
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

    // Start recording and show listening panel immediately for visual feedback
    private func startListening() {
        NSLog("[STEN] startListening called, state=\(menu.state), engineReady=\(engine.isReady)")
        idleTimer?.invalidate()
        guard engine.isReady else { pendingListen = true; loadEngineIfNeeded(); return }
        menu.state = .listening
        listeningPanel = ListeningPanel()
        listeningPanel?.onCancel = { [weak self] in self?.cancelOperation() }
        listeningPanel?.onTranscribe = { [weak self] in self?.stopListening() }
        recorder.onLevel = { [weak self] in self?.listeningPanel?.addLevel($0) }
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
    }

    private func closeListeningPanel() {
        let panel = listeningPanel
        listeningPanel = nil
        recorder.onLevel = nil
        panel?.onCancel = nil
        panel?.close()
    }

    // Stop recording, transcribe, apply transforms, output text
    private func stopListening() {
        NSLog("[STEN] stopListening called, state=\(menu.state)")
        recorder.onError = nil
        let audio = recorder.stop()
        let peak = audio.map { abs($0) }.max() ?? 0
        NSLog("[STEN] audio samples=\(audio.count), minRequired=\(Self.minAudioSamples), peak=\(peak)")
        closeListeningPanel()
        guard audio.count > Self.minAudioSamples, peak > 1e-4 else {
            NSLog("[STEN] insufficient audio, discarding")
            menu.state = .idle
            scheduleIdleUnload()
            return
        }
        menu.state = .transcribing
        Task.detached { [self] in
            let text = await engine.transcribe(audio)
            NSLog("[STEN] transcription result: \(text ?? "nil")")
            let transformed = text.flatMap { t in t.isEmpty ? nil : applyTransforms(t) }
            await MainActor.run {
                menu.state = .idle
                scheduleIdleUnload()
                if let transformed { outputText(transformed) }
                else { NSLog("[STEN] no output — text was nil or empty") }
            }
        }
    }

    private func cancelOperation() {
        NSLog("[STEN] cancelOperation called, state=\(menu.state)")
        closeListeningPanel()
        if menu.state == .listening || menu.state == .loading { pendingListen = false; recorder.onReady = nil; recorder.onError = nil; _ = recorder.stop(); menu.state = .idle }
        else if menu.state == .transcribing { menu.state = .idle }
        scheduleIdleUnload()
    }

    // Inject text into active app or show notification
    private func outputText(_ text: String) {
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            showNotification("Transcription", text)
            return
        }
        if !TextInjector.inject(text) { showNotification("Transcription", text) }
    }

    // Run enabled transform scripts sequentially, piping text through each
    private func applyTransforms(_ text: String) -> String {
        let dir = MenuBarController.transformsDir
        let enabled = Settings.shared.enabledTransforms
        guard !enabled.isEmpty else { return text }
        let scripts = enabled.sorted().compactMap { name -> URL? in
            let url = dir.appendingPathComponent(name)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }
        var result = text
        for script in scripts {
            let proc = Process()
            proc.executableURL = script
            var env = ProcessInfo.processInfo.environment
            env["LANG"] = "en_US.UTF-8"
            proc.environment = env
            let stdin = Pipe(), stdout = Pipe()
            proc.standardInput = stdin
            proc.standardOutput = stdout
            proc.standardError = FileHandle.nullDevice
            defer { try? stdout.fileHandleForReading.close() }
            do {
                try proc.run()
                stdin.fileHandleForWriting.write(result.data(using: .utf8) ?? Data())
                try stdin.fileHandleForWriting.close()

                // Read stdout before waitUntilExit to avoid pipe buffer deadlock
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()

                // Timeout prevents hanging on slow scripts
                let deadline = DispatchTime.now() + Self.transformTimeoutSeconds
                DispatchQueue.global().asyncAfter(deadline: deadline) { [weak proc] in
                    if proc?.isRunning == true { proc?.terminate() }
                }
                proc.waitUntilExit()

                if proc.terminationStatus == 0, let out = String(data: outData, encoding: .utf8), !out.isEmpty {
                    result = out.trimmingCharacters(in: .newlines)
                }
            } catch {
                // Script execution failed, continue with current result
            }
        }
        return result
    }

    private func showNotification(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    func deleteModelAndQuit() {
        if let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("FluidAudio/Models") {
            try? FileManager.default.removeItem(at: dir)
        }
        NSApp.terminate(nil)
    }
}
