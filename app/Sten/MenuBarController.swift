import AppKit
import Carbon

enum AppState { case idle, listening, transcribing, loading }

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let settings = Settings.shared
    var state: AppState = .idle { didSet { updateIcon(); updateMenu() } }
    var onHotkeyChange: ((Bool) -> Void)?
    var onListen: (() -> Void)?
    var onTranscribe: (() -> Void)?
    var onCancel: (() -> Void)?
    private var hotkeyPanel: HotkeyPanel?
    private var permissionsMode = false

    override init() {
        super.init()
        updateIcon()
        updateMenu()
    }

    func menuWillOpen(_ menu: NSMenu) { updateMenu() }

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

    @objc private func grantPermissions() {
        (NSApp.delegate as? AppDelegate)?.grantPermissions()
    }

    private func loadIcon(_ name: String) -> NSImage? {
        var img: NSImage?
        if let url = Bundle.main.url(forResource: name, withExtension: "png") {
            img = NSImage(contentsOf: url)
        } else if let resourcePath = Bundle.main.resourcePath {
            img = NSImage(contentsOfFile: "\(resourcePath)/\(name).png")
        }
        img?.size = NSSize(width: 18, height: 18)
        return img
    }

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

    private func configureListenHotkey(_ item: NSMenuItem) {
        let code = settings.hotkeyCode
        let mods = settings.hotkeyModifiers
        if mods == 0 {
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
        let special: [UInt16: String] = [
            49: " ", 36: "\r", 48: "\t", 51: "\u{8}", 53: "\u{1B}",
            123: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
            124: String(UnicodeScalar(NSRightArrowFunctionKey)!),
            125: String(UnicodeScalar(NSDownArrowFunctionKey)!),
            126: String(UnicodeScalar(NSUpArrowFunctionKey)!)
        ]
        if let s = special[code] { return s }
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layout = unsafeBitCast(layoutData, to: CFData.self) as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var len: Int = 0
        layout.withUnsafeBytes { ptr in
            let layoutPtr = ptr.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            UCKeyTranslate(layoutPtr, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, 4, &len, &chars)
        }
        return len > 0 ? String(utf16CodeUnits: chars, count: len).lowercased() : nil
    }

    func updateMenu() {
        if permissionsMode { return }
        let menu = NSMenu()
        let header = NSMenuItem(title: "Sten \(appVersion())", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        switch state {
        case .idle:
            let listen = NSMenuItem(title: "Listen", action: #selector(listenAction), keyEquivalent: "")
            listen.target = self
            configureListenHotkey(listen)
            menu.addItem(listen)
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
            menu.addItem(NSMenuItem(title: "Loading model...", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        let hotkeyItem = NSMenuItem(title: "Change Hotkey...", action: #selector(openHotkeyPanel), keyEquivalent: "")
        hotkeyItem.target = self
        menu.addItem(hotkeyItem)
        let loginItem = NSMenuItem(title: "Start on Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = settings.startOnLogin ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "About Sten", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func listenAction() { onListen?() }
    @objc private func transcribeAction() { onTranscribe?() }
    @objc private func cancelAction() { onCancel?() }
    @objc private func toggleLogin() { settings.startOnLogin.toggle(); updateMenu() }
    @objc private func openAbout() { if let url = URL(string: "https://sten.vlad.studio") { NSWorkspace.shared.open(url) } }

    @objc private func openHotkeyPanel() {
        guard hotkeyPanel == nil else { return }
        hotkeyPanel = HotkeyPanel()
        hotkeyPanel?.onSave = { [weak self] in self?.updateMenu() }
        hotkeyPanel?.onClose = { [weak self] in self?.hotkeyPanel = nil; self?.onHotkeyChange?(true) }
        if let button = statusItem.button, let w = button.window {
            hotkeyPanel?.positionBelow(w.convertToScreen(button.frame))
        }
        onHotkeyChange?(false)
        hotkeyPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
