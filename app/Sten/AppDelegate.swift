import AppKit
import AVFoundation
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
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
        memorySource = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        memorySource?.setEventHandler { [weak self] in self?.pendingListen = false; self?.engine.unload() }
        memorySource?.resume()
        if Settings.shared.onboardingDone { checkPermissionsAndUpdateMenu() }
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

    @objc func checkPermissionsAndUpdateMenu() {
        let micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let accessibilityGranted = AXIsProcessTrusted()
        if !micGranted || !accessibilityGranted {
            hotkey.stop()
            menu.showPermissionsRequired(mic: !micGranted, accessibility: !accessibilityGranted)
            startPermissionPolling()
        } else {
            stopPermissionPolling()
            menu.showNormalMenu()
            hotkey.start()
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
            else if menu.state == .listening { stopListening() }
        }
    }

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
        idleTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: false) { [weak self] _ in
            self?.engine.unload(); self?.menu.modelReady = false
        }
    }

    private func startListening() {
        idleTimer?.invalidate()
        guard engine.isReady else { pendingListen = true; loadEngineIfNeeded(); return }
        menu.state = .listening
        do { try recorder.start() } catch { menu.state = .idle; return }
        listeningPanel = ListeningPanel()
        listeningPanel?.onCancel = { [weak self] in self?.cancelOperation() }
        listeningPanel?.onTranscribe = { [weak self] in self?.stopListening() }
        recorder.onLevel = { [weak self] in self?.listeningPanel?.addLevel($0) }
        if let btn = menu.statusButton, let w = btn.window { listeningPanel?.positionBelow(w.convertToScreen(btn.frame)) }
        listeningPanel?.makeKeyAndOrderFront(nil)
    }

    private func closeListeningPanel() { let p = listeningPanel; listeningPanel = nil; recorder.onLevel = nil; p?.onCancel = nil; p?.close() }

    private func stopListening() {
        let audio = recorder.stop()
        closeListeningPanel()
        guard audio.count > 8000 else { menu.state = .idle; scheduleIdleUnload(); return }
        menu.state = .transcribing
        Task {
            let text = await engine.transcribe(audio)
            let transformed = text.flatMap { t in t.isEmpty ? nil : applyTransforms(t) }
            await MainActor.run {
                menu.state = .idle
                scheduleIdleUnload()
                if let transformed { outputText(transformed) }
            }
        }
    }

    private func cancelOperation() {
        closeListeningPanel()
        if menu.state == .listening { _ = recorder.stop(); menu.state = .idle }
        else if menu.state == .transcribing { menu.state = .idle }
        scheduleIdleUnload()
    }

    private func outputText(_ text: String) {
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            showNotification("Transcription", text)
            return
        }
        TextInjector.inject(text)
    }

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
            let stdin = Pipe(), stdout = Pipe()
            proc.standardInput = stdin
            proc.standardOutput = stdout
            proc.standardError = FileHandle.nullDevice
            defer { try? stdin.fileHandleForWriting.close(); try? stdout.fileHandleForReading.close() }
            do {
                try proc.run()
                stdin.fileHandleForWriting.write(result.data(using: .utf8) ?? Data())
                stdin.fileHandleForWriting.closeFile()
                proc.waitUntilExit()
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                if proc.terminationStatus == 0, let out = String(data: outData, encoding: .utf8), !out.isEmpty {
                    result = out.trimmingCharacters(in: .newlines)
                }
            } catch {}
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
