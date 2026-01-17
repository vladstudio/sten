import AppKit
import Carbon

enum AppState { case idle, listening, transcribing, downloading, loading }

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let settings = Settings.shared
    private var refreshTimer: Timer?
    private weak var downloadMenuItem: NSMenuItem?
    var downloadProgress: Double = 0 { didSet { updateDownloadProgress() } }
    var downloadingModel: String = ""
    var state: AppState = .idle { didSet { updateIcon(); updateMenu(); updateTimer() } }
    var onModelChange: (() -> Void)?
    var onHotkeyChange: ((Bool) -> Void)? // true = restart, false = stop
    var onListen: (() -> Void)?
    var onTranscribe: (() -> Void)?
    var onCancel: (() -> Void)?
    private var hotkeyPanel: HotkeyPanel?

    private func updateTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func downloadProgressTitle() -> String {
        "Downloading \(downloadingModel)... \(Int(downloadProgress * 100))%"
    }

    private func updateDownloadProgress() {
        downloadMenuItem?.title = downloadProgressTitle()
    }

    private let models = [("Small (488 MB)", "small"), ("Medium (1.5 GB)", "medium"), ("Large Turbo (1.6 GB)", "large-v3-turbo"), ("Large (3.1 GB)", "large-v3")]
    private let languages = ["Auto", "Follow OS", "-", "English", "Spanish", "French", "German", "Italian", "Portuguese", "Dutch", "Russian", "Chinese", "Japanese", "Korean", "-", "Arabic", "Bulgarian", "Catalan", "Croatian", "Czech", "Danish", "Finnish", "Greek", "Hebrew", "Hindi", "Hungarian", "Indonesian", "Malay", "Norwegian", "Persian", "Polish", "Romanian", "Serbian", "Slovak", "Slovenian", "Swedish", "Thai", "Turkish", "Ukrainian", "Vietnamese"]

    private var permissionsMode = false

    override init() {
        super.init()
        updateIcon()
        updateMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenu()
    }

    deinit {
        refreshTimer?.invalidate()
    }

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

    func setAudioLevel(_ level: Float) {
        if state == .listening { updateIcon() }
    }

    func refreshForLanguageChange() {
        updateIcon()
        updateMenu()
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

    private func iconWithLanguageOverlay(_ baseIcon: NSImage, language: String) -> NSImage {
        let size = baseIcon.size
        let result = NSImage(size: size)
        result.lockFocus()
        baseIcon.draw(in: NSRect(origin: .zero, size: size))
        let code = String(language.uppercased().prefix(2))
        let font = NSFont.monospacedSystemFont(ofSize: 7, weight: .bold)
        code.draw(at: NSPoint(x: 0, y: -1), withAttributes: [.font: font, .foregroundColor: NSColor.black])
        result.unlockFocus()
        result.isTemplate = true
        return result
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
            case .downloading: name = "download"
            }
        }
        guard let img = loadIcon(name) else {
            statusItem.button?.image = nil
            statusItem.button?.title = "S"
            return
        }
        let finalImg: NSImage
        if state == .idle && !permissionsMode {
            let lang = settings.effectiveLanguage
            if lang != "auto" {
                finalImg = iconWithLanguageOverlay(img, language: lang)
            } else {
                img.isTemplate = true
                finalImg = img
            }
        } else {
            img.isTemplate = true
            finalImg = img
        }
        statusItem.button?.title = ""
        statusItem.button?.image = finalImg
    }

    private func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func menuHeader() -> NSMenuItem {
        let item = NSMenuItem(title: "Sten \(appVersion())", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func configureListenHotkey(_ item: NSMenuItem) {
        let code = settings.hotkeyCode
        let mods = settings.hotkeyModifiers

        // Special keys (no modifiers) - use attributed title
        if mods == 0 {
            let hotkey = HotkeyPanel.hotkeyString(code, CGEventFlags(rawValue: mods))
            let para = NSMutableParagraphStyle()
            para.tabStops = [NSTextTab(textAlignment: .right, location: tabStop)]
            let str = NSMutableAttributedString(string: "Listen\t", attributes: [.font: NSFont.menuFont(ofSize: 0), .paragraphStyle: para])
            str.append(NSAttributedString(string: hotkey, attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor]))
            item.attributedTitle = str
            return
        }

        // Regular keys with modifiers - use keyEquivalent
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
            126: String(UnicodeScalar(NSUpArrowFunctionKey)!),
            122: String(UnicodeScalar(NSF1FunctionKey)!),
            120: String(UnicodeScalar(NSF2FunctionKey)!),
            99: String(UnicodeScalar(NSF3FunctionKey)!),
            118: String(UnicodeScalar(NSF4FunctionKey)!),
            96: String(UnicodeScalar(NSF5FunctionKey)!),
            97: String(UnicodeScalar(NSF6FunctionKey)!),
            98: String(UnicodeScalar(NSF7FunctionKey)!),
            100: String(UnicodeScalar(NSF8FunctionKey)!),
            101: String(UnicodeScalar(NSF9FunctionKey)!),
            109: String(UnicodeScalar(NSF10FunctionKey)!),
            103: String(UnicodeScalar(NSF11FunctionKey)!),
            111: String(UnicodeScalar(NSF12FunctionKey)!)
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

    private let tabStop: CGFloat = 160

    func updateMenu() {
        if permissionsMode { return }
        let menu = NSMenu()

        menu.addItem(menuHeader())
        menu.addItem(.separator())

        if state == .idle {
            let listen = NSMenuItem(title: "Listen", action: #selector(listenAction), keyEquivalent: "")
            listen.target = self
            configureListenHotkey(listen)
            menu.addItem(listen)
            menu.addItem(.separator())
        } else if state == .listening {
            menu.addItem(NSMenuItem(title: "Listening...", action: nil, keyEquivalent: ""))
            let transcribe = NSMenuItem(title: "Transcribe", action: #selector(transcribeAction), keyEquivalent: "")
            transcribe.target = self; menu.addItem(transcribe)
            let cancel = NSMenuItem(title: "Cancel", action: #selector(cancelAction), keyEquivalent: "")
            cancel.target = self; menu.addItem(cancel)
            menu.addItem(.separator())
        } else if state == .transcribing {
            menu.addItem(NSMenuItem(title: "Transcribing...", action: nil, keyEquivalent: ""))
            let cancel = NSMenuItem(title: "Cancel", action: #selector(cancelAction), keyEquivalent: "")
            cancel.target = self; menu.addItem(cancel)
            menu.addItem(.separator())
        } else if state == .loading {
            menu.addItem(NSMenuItem(title: "Loading model...", action: nil, keyEquivalent: ""))
            menu.addItem(.separator())
        } else if state == .downloading {
            let info = NSMenuItem(title: downloadProgressTitle(), action: nil, keyEquivalent: "")
            info.isEnabled = false; menu.addItem(info)
            downloadMenuItem = info
            let cancel = NSMenuItem(title: "Cancel", action: #selector(cancelDownload), keyEquivalent: "")
            cancel.target = self; menu.addItem(cancel)
            menu.addItem(.separator())
        }

        let hotkeyItem = NSMenuItem(title: "Change Hotkey…", action: #selector(openHotkeyPanel), keyEquivalent: "")
        hotkeyItem.target = self; menu.addItem(hotkeyItem)

        let loginItem = NSMenuItem(title: "Start on Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self; loginItem.state = settings.startOnLogin ? .on : .off
        menu.addItem(loginItem)

        let modelMenu = NSMenu()
        let downloaded = ModelManager.shared.downloadedModels()
        for (name, id) in models {
            let isDownloaded = downloaded.contains(id)
            let item = NSMenuItem(title: "", action: #selector(selectModel(_:)), keyEquivalent: "")
            item.attributedTitle = modelMenuTitle(name, downloaded: isDownloaded)
            item.target = self; item.representedObject = id
            item.state = isDownloaded && settings.selectedModel == id ? .on : .off
            modelMenu.addItem(item)
        }
        modelMenu.addItem(.separator())
        let showFolder = NSMenuItem(title: "Show in Finder…", action: #selector(openModelsFolder), keyEquivalent: "")
        showFolder.target = self; modelMenu.addItem(showFolder)
        let modelItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        modelItem.submenu = modelMenu
        if state == .downloading { modelItem.isEnabled = false }
        menu.addItem(modelItem)

        let langMenu = NSMenu()
        for lang in languages {
            if lang == "-" { langMenu.addItem(.separator()); continue }
            let key = lang.lowercased()
            var title = lang
            if key == "follow os" && settings.selectedLanguage == key {
                let detected = InputSourceObserver.shared.currentLanguage
                title = "Follow OS (\(detected == "auto" ? "?" : detected))"
            }
            let item = NSMenuItem(title: title, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = key; item.state = settings.selectedLanguage == key ? .on : .off
            langMenu.addItem(item)
        }
        let langItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        langItem.submenu = langMenu
        menu.addItem(langItem)

        menu.addItem(.separator())
        let about = NSMenuItem(title: "About Sten", action: #selector(openAbout), keyEquivalent: "")
        about.target = self; menu.addItem(about)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.delegate = self
        statusItem.menu = menu
    }

    private func modelMenuTitle(_ name: String, downloaded: Bool) -> NSAttributedString {
        // Parse "Small (488 MB)" into "Small" and "488 MB"
        let parts = name.split(separator: "(", maxSplits: 1)
        let modelName = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let size = parts.count > 1 ? String(parts[1]).replacingOccurrences(of: ")", with: "") : ""

        let para = NSMutableParagraphStyle()
        para.tabStops = [NSTextTab(textAlignment: .right, location: 190)]

        let str = NSMutableAttributedString(string: "\(modelName)\t", attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .paragraphStyle: para
        ])

        if downloaded, let img = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil) {
            let attachment = NSTextAttachment()
            attachment.image = img.withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
            let imgStr = NSMutableAttributedString(attachment: attachment)
            imgStr.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSRange(location: 0, length: imgStr.length))
            str.append(imgStr)
            str.append(NSAttributedString(string: " "))
        }

        let sizeStr = NSAttributedString(string: size, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        str.append(sizeStr)
        return str
    }

    @objc private func cancelDownload() {
        ModelManager.shared.cancel()
        ensureValidModelSelected()
        state = .idle
    }

    private func ensureValidModelSelected() {
        let mgr = ModelManager.shared
        if !mgr.isDownloaded(settings.selectedModel), let available = mgr.firstAvailableModel() {
            settings.selectedModel = available
        }
    }
    @objc private func listenAction() { onListen?() }
    @objc private func transcribeAction() { onTranscribe?() }
    @objc private func cancelAction() { onCancel?() }
    @objc private func toggleLogin() { settings.startOnLogin.toggle(); updateMenu() }
    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? String else { return }
        let needsDownload = !ModelManager.shared.isDownloaded(v)
        if v != settings.selectedModel || needsDownload {
            settings.selectedModel = v; updateMenu(); onModelChange?()
        }
    }
    @objc private func selectLanguage(_ sender: NSMenuItem) { if let v = sender.representedObject as? String { settings.selectedLanguage = v; updateIcon(); updateMenu() } }
    @objc private func openAbout() { if let url = URL(string: "https://sten.vlad.studio") { NSWorkspace.shared.open(url) } }
    @objc private func openModelsFolder() { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: ModelManager.shared.modelsDir.path) }
    @objc private func openHotkeyPanel() {
        guard hotkeyPanel == nil else { return } // prevent multiple panels
        hotkeyPanel = HotkeyPanel()
        hotkeyPanel?.onSave = { [weak self] in self?.updateMenu() }
        hotkeyPanel?.onClose = { [weak self] in self?.hotkeyPanel = nil; self?.onHotkeyChange?(true) }
        if let button = statusItem.button, let w = button.window {
            hotkeyPanel?.positionBelow(w.convertToScreen(button.frame))
        }
        onHotkeyChange?(false) // stop hotkey while panel is open
        hotkeyPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
