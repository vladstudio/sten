// Menu bar icon and dropdown menu - shows app state and provides controls
import AppKit

enum AppState { case idle, listening, transcribing, loading }

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var statusButton: NSStatusBarButton? { statusItem.button }
    private let settings = Settings.shared
    var state: AppState = .idle { didSet { updateIcon(); updateMenu() } }
    var modelReady = false { didSet { if oldValue != modelReady { updateMenu() } } }

    // Callbacks to AppDelegate
    var onHotkeyChange: ((Bool) -> Void)?
    var onListen: (() -> Void)?
    var onTranscribe: (() -> Void)?
    var onCancel: (() -> Void)?
    var onTranscribeFile: (() -> Void)?
    var onPasteAgain: (() -> Void)?
    var hasLastTranscription = false { didSet { if oldValue != hasLastTranscription { updateMenu() } } }

    private var hotkeyPanel: HotkeyPanel?
    private var confirmPanel: ConfirmPanel?
    private var permissionsMode = false
    private var iconCache: [String: NSImage] = [:]

    override init() {
        super.init()
        updateIcon()
        updateMenu()
    }

    // Populate transform items in main menu when opened
    func menuWillOpen(_ menu: NSMenu) {
        menu.items.filter { $0.action == #selector(toggleTransform(_:)) }.forEach { menu.removeItem($0) }
        guard let folderIndex = menu.items.firstIndex(where: { $0.tag == 999 }) else { return }
        let scripts = Set((try? FileManager.default.contentsOfDirectory(atPath: Self.transformsDir.path))?.filter { !$0.hasPrefix(".") } ?? [])
        for (i, name) in scripts.sorted().enumerated() {
            let mi = NSMenuItem(title: name, action: #selector(toggleTransform(_:)), keyEquivalent: "")
            mi.target = self; mi.state = settings.enabledTransforms.contains(name) ? .on : .off
            menu.insertItem(mi, at: folderIndex + i)
        }
    }

    // Show permissions-required menu when mic or accessibility missing
    func showPermissionsRequired(mic: Bool, accessibility: Bool) {
        permissionsMode = true
        let menu = NSMenu()
        var missing: [String] = []
        if mic { missing.append("Microphone") }
        if accessibility { missing.append("Accessibility") }
        let info = NSMenuItem(title: "Permissions needed: \(missing.joined(separator: ", "))", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())
        let grant = NSMenuItem(title: "Grant Permissions...", action: #selector(grantPermissions), keyEquivalent: "")
        grant.target = self
        menu.addItem(grant)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func showNormalMenu() {
        permissionsMode = false
        updateIcon()
        updateMenu()
    }

    private var appDelegate: AppDelegate? { NSApp.delegate as? AppDelegate }

    @objc private func grantPermissions() {
        appDelegate?.grantPermissions()
    }

    private func loadIcon(_ name: String) -> NSImage? {
        if let cached = iconCache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.size = NSSize(width: 18, height: 18)
        iconCache[name] = img
        return img
    }

    // Update menu bar icon based on current state
    private func updateIcon() {
        let name: String
        if permissionsMode {
            name = "warning"
        } else {
            switch state {
            case .idle: name = "idle"
            case .listening: name = "listen"
            case .transcribing, .loading: name = "think"
            }
        }
        guard let img = loadIcon(name) else {
            statusItem.button?.image = nil
            statusItem.button?.title = "S"
            return
        }
        img.isTemplate = true
        statusItem.button?.title = ""
        statusItem.button?.image = img
    }

    private func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // Configure Listen menu item with hotkey shortcut
    private func configureListenHotkey(_ item: NSMenuItem) {
        let code = settings.hotkeyCode
        let mods = settings.hotkeyModifiers
        if mods == 0 {
            // Special key (no modifiers) - show as grayed text
            let hotkey = HotkeyPanel.hotkeyString(code, CGEventFlags(rawValue: mods))
            let para = NSMutableParagraphStyle()
            para.tabStops = [NSTextTab(textAlignment: .right, location: 160)]
            let str = NSMutableAttributedString(string: "Listen\t", attributes: [.font: NSFont.menuFont(ofSize: 0), .paragraphStyle: para])
            str.append(NSAttributedString(string: hotkey, attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor]))
            item.attributedTitle = str
            return
        }
        if let char = keyChar(code) {
            item.keyEquivalent = char
            item.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: UInt(mods))
        }
    }

    private func keyChar(_ code: UInt16) -> String? {
        let special: [UInt16: String] = [49: " ", 36: "\r", 48: "\t", 51: "\u{8}", 53: "\u{1B}",
            123: String(UnicodeScalar(NSLeftArrowFunctionKey)!), 124: String(UnicodeScalar(NSRightArrowFunctionKey)!),
            125: String(UnicodeScalar(NSDownArrowFunctionKey)!), 126: String(UnicodeScalar(NSUpArrowFunctionKey)!)]
        return special[code] ?? translateKeyCode(code)?.lowercased()
    }

    // Rebuild menu based on current state
    func updateMenu() {
        if permissionsMode { return }
        let menu = NSMenu()
        let header = NSMenuItem(title: "Sten \(appVersion())", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        switch state {
        case .idle where modelReady:
            let listen = NSMenuItem(title: "Listen", action: #selector(listenAction), keyEquivalent: "")
            listen.target = self; listen.isEnabled = settings.onboardingDone; configureListenHotkey(listen)
            menu.addItem(listen)
            let fileItem = NSMenuItem(title: "Transcribe Audio File...", action: #selector(transcribeFileAction), keyEquivalent: "")
            fileItem.target = self; fileItem.isEnabled = settings.onboardingDone
            menu.addItem(fileItem)
            if hasLastTranscription {
                let paste = NSMenuItem(title: "Paste Again", action: #selector(pasteAgainAction), keyEquivalent: "")
                paste.target = self
                menu.addItem(paste)
            }
        case .idle:
            menu.addItem(NSMenuItem(title: "Loading model...", action: nil, keyEquivalent: ""))
        case .listening:
            menu.addItem(NSMenuItem(title: "Listening...", action: nil, keyEquivalent: ""))
            let transcribe = NSMenuItem(title: "Transcribe", action: #selector(transcribeAction), keyEquivalent: "")
            transcribe.target = self
            menu.addItem(transcribe)
            let cancel = NSMenuItem(title: "Cancel", action: #selector(cancelAction), keyEquivalent: "")
            cancel.target = self
            menu.addItem(cancel)
        case .transcribing:
            menu.addItem(NSMenuItem(title: "Transcribing...", action: nil, keyEquivalent: ""))
            let cancel = NSMenuItem(title: "Cancel", action: #selector(cancelAction), keyEquivalent: "")
            cancel.target = self
            menu.addItem(cancel)
        case .loading:
            menu.addItem(NSMenuItem(title: "Preparing...", action: nil, keyEquivalent: ""))
            let cancel = NSMenuItem(title: "Cancel", action: #selector(cancelAction), keyEquivalent: "")
            cancel.target = self
            menu.addItem(cancel)
        }

        menu.addItem(.separator())
        let hotkeyItem = NSMenuItem(title: "Change Hotkey...", action: #selector(openHotkeyPanel), keyEquivalent: "")
        hotkeyItem.target = self
        menu.addItem(hotkeyItem)
        let loginItem = NSMenuItem(title: "Start on Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = settings.startOnLogin ? .on : .off
        menu.addItem(loginItem)
        let contextItem = NSMenuItem(title: "Include Context", action: #selector(toggleContext), keyEquivalent: "")
        contextItem.target = self
        contextItem.state = settings.includeContext ? .on : .off
        menu.addItem(contextItem)
        menu.addItem(.separator())
        let openFolder = NSMenuItem(title: "Open transforms folder", action: #selector(openTransformsFolder), keyEquivalent: "")
        openFolder.target = self; openFolder.tag = 999
        menu.addItem(openFolder)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "About Sten", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let update = NSMenuItem(title: "Check for Updates...", action: #selector(checkUpdate), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        if settings.onboardingDone, let size = modelSizeMB() {
            let del = NSMenuItem(title: "Delete model (\(size) MB) and quit", action: #selector(deleteModelAction), keyEquivalent: "")
            del.target = self
            menu.addItem(del)
        }
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func listenAction() { onListen?() }
    @objc private func transcribeAction() { onTranscribe?() }
    @objc private func cancelAction() { onCancel?() }
    @objc private func transcribeFileAction() { onTranscribeFile?() }
    @objc private func pasteAgainAction() { onPasteAgain?() }
    @objc private func toggleLogin() { settings.startOnLogin.toggle(); updateMenu() }
    @objc private func toggleContext() { settings.includeContext.toggle(); updateMenu() }
    @objc private func openAbout() { if let url = URL(string: "https://sten.vlad.studio") { NSWorkspace.shared.open(url) } }
    @objc private func checkUpdate() { StenUpdater.check(manual: true) }

    static let transformsDir = Settings.stenDir.appendingPathComponent("transforms")

    @objc private func toggleTransform(_ sender: NSMenuItem) {
        var enabled = settings.enabledTransforms
        if enabled.contains(sender.title) { enabled.remove(sender.title); sender.state = .off }
        else { enabled.insert(sender.title); sender.state = .on }
        settings.enabledTransforms = enabled
    }

    @objc private func openTransformsFolder() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.transformsDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Self.transformsDir)
    }

    private func modelDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("FluidAudio/Models")
    }

    private func modelSizeMB() -> Int? {
        guard let dir = modelDirectory(), FileManager.default.fileExists(atPath: dir.path) else { return nil }
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
        var total: Int64 = 0
        for case let url as URL in enumerator { total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0 }
        return total > 0 ? Int(total / 1_000_000) : nil
    }

    @objc private func deleteModelAction() {
        confirmPanel = ConfirmPanel(message: "Delete the speech model and quit?\nYou can re-download it later.", confirmTitle: "Delete and Quit")
        confirmPanel?.onConfirm = { [weak self] in
            Settings.shared.onboardingDone = false
            self?.appDelegate?.deleteModelAndQuit()
        }
        confirmPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openHotkeyPanel() { showHotkeyPanel(below: nil) }

    func showHotkeyPanel(below anchor: NSWindow?) {
        guard hotkeyPanel == nil else { return }
        hotkeyPanel = HotkeyPanel()
        hotkeyPanel?.onSave = { [weak self] in self?.updateMenu() }
        hotkeyPanel?.onClose = { [weak self] in self?.hotkeyPanel = nil; self?.onHotkeyChange?(true) }
        if let anchor { hotkeyPanel?.positionBelow(anchor.frame) }
        else if let button = statusItem.button, let w = button.window { hotkeyPanel?.positionBelow(w.convertToScreen(button.frame)) }
        onHotkeyChange?(false)
        hotkeyPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
