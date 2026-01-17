import AppKit
import AVFoundation
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menu: MenuBarController!
    private let hotkey = HotkeyManager()
    private let recorder = AudioRecorder()
    private let models = ModelManager.shared
    private var engine = TranscriptionEngine()
    private var permissionTimer: Timer?
    private var idleTimer: Timer?
    private var memorySource: DispatchSourceMemoryPressure?
    private var pendingListen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu = MenuBarController()
        menu.onModelChange = { [weak self] in self?.ensureModelDownloaded() }
        menu.onHotkeyChange = { [weak self] start in start ? self?.hotkey.start() : self?.hotkey.stop() }
        menu.onListen = { [weak self] in self?.startListening() }
        menu.onTranscribe = { [weak self] in self?.stopListening() }
        menu.onCancel = { [weak self] in self?.cancelOperation() }
        recorder.onLevel = { [weak self] level in self?.menu.setAudioLevel(level) }
        setupHotkey()
        setupModelManager()
        InputSourceObserver.shared.onChange = { [weak self] in self?.menu.refreshForLanguageChange() }
        InputSourceObserver.shared.start()
        memorySource = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        memorySource?.setEventHandler { [weak self] in self?.pendingListen = false; self?.engine.unload() }
        memorySource?.resume()
        requestPermissions()
    }

    private func requestPermissions() {
        checkPermissionsAndUpdateMenu()
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
            ensureModelDownloaded()
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

    private func setupModelManager() {
        models.onProgress = { [weak self] progress in
            self?.menu.downloadProgress = progress
        }
        models.onComplete = { [weak self] success in
            guard let self else { return }
            menu.state = .idle
            if success {
                loadEngine()
            } else {
                ensureValidModelSelected()
                showNotification("Download failed", "Please try again.")
            }
        }
    }

    private func ensureValidModelSelected() {
        if !models.isDownloaded(Settings.shared.selectedModel), let available = models.firstAvailableModel() {
            Settings.shared.selectedModel = available
        }
    }

    private func ensureModelDownloaded() {
        ensureValidModelSelected()
        let id = Settings.shared.selectedModel
        if models.isDownloaded(id) { loadEngine() }
        else { menu.downloadingModel = id; menu.state = .downloading; models.download(id) }
    }

    private func loadEngine() {
        let id = Settings.shared.selectedModel
        guard models.isDownloaded(id) else { ensureModelDownloaded(); return }
        let path = models.modelPath(id)
        menu.state = .loading
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let ok = self.engine.loadModel(path)
            DispatchQueue.main.async {
                self.menu.state = .idle
                self.menu.updateMenu()
                if !ok { self.pendingListen = false; self.showNotification("Model Error", "Failed to load model") }
                else if self.pendingListen { self.pendingListen = false; self.startListening() }
                else { self.scheduleIdleUnload() }
            }
        }
    }

    private func scheduleIdleUnload() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: false) { [weak self] _ in self?.engine.unload() }
    }

    private func hasReadyModel() -> Bool {
        let id = Settings.shared.selectedModel
        return models.isDownloaded(id) && engine.isReady
    }

    private func startListening() {
        idleTimer?.invalidate()
        guard hasReadyModel() else {
            if models.hasAnyModel() {
                pendingListen = true
                ensureModelDownloaded()
            } else {
                showNotification("No Model", "Please download a model first from the menu.")
            }
            return
        }
        // Verify model file still exists (could have been deleted while app running)
        let id = Settings.shared.selectedModel
        guard models.isDownloaded(id) else {
            engine.unload()
            menu.updateMenu()
            if let available = models.firstAvailableModel() {
                Settings.shared.selectedModel = available
                ensureModelDownloaded()
            } else {
                showNotification("Model Missing", "The model file was deleted. Please download a model.")
            }
            return
        }
        menu.state = .listening
        do { try recorder.start() } catch { menu.state = .idle }
    }

    private func stopListening() {
        let audio = recorder.stop()
        guard audio.count > 8000 else { menu.state = .idle; scheduleIdleUnload(); return }
        menu.state = .transcribing
        let lang = Settings.shared.effectiveLanguage
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let text = self.engine.transcribe(audio, language: lang)
            DispatchQueue.main.async {
                self.menu.state = .idle
                self.scheduleIdleUnload()
                if let text, !text.isEmpty { self.outputText(text) }
            }
        }
    }

    private func cancelOperation() {
        if menu.state == .listening {
            _ = recorder.stop()
            menu.state = .idle
        } else if menu.state == .transcribing {
            menu.state = .idle
        }
        scheduleIdleUnload()
    }

    private func outputText(_ text: String) {
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            showNotification("Transcription", text)
            return
        }
        TextInjector.inject(text)
    }

    private func showNotification(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}
