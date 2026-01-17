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
            Task {
                let ok = await self?.engine.load() ?? false
                await MainActor.run { done(ok) }
            }
        }
        onboarding?.onComplete = { [weak self] in self?.onboarding = nil; self?.checkPermissionsAndUpdateMenu() }
        onboarding?.onChangeHotkey = { [weak self] in self?.menu.showHotkeyPanel(below: self?.onboarding) }
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
            if pendingListen { pendingListen = false; startListening() }
            return
        }
        menu.state = .loading
        Task {
            let ok = await engine.load()
            await MainActor.run {
                menu.state = .idle
                if !ok {
                    pendingListen = false
                    showNotification("Model Error", "Failed to load model")
                } else if pendingListen {
                    pendingListen = false
                    startListening()
                } else {
                    scheduleIdleUnload()
                }
            }
        }
    }

    private func scheduleIdleUnload() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: false) { [weak self] _ in
            self?.engine.unload()
        }
    }

    private func startListening() {
        idleTimer?.invalidate()
        guard engine.isReady else {
            pendingListen = true
            loadEngineIfNeeded()
            return
        }
        menu.state = .listening
        do { try recorder.start() } catch { menu.state = .idle }
    }

    private func stopListening() {
        let audio = recorder.stop()
        guard audio.count > 8000 else { menu.state = .idle; scheduleIdleUnload(); return }
        menu.state = .transcribing
        Task {
            let text = await engine.transcribe(audio)
            await MainActor.run {
                menu.state = .idle
                scheduleIdleUnload()
                if let text, !text.isEmpty { outputText(text) }
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
