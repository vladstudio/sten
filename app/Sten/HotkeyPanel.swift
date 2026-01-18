// Panel for setting global hotkey - captures key press or allows special key buttons
import AppKit

final class HotkeyPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "Press new hotkey or Esc to cancel")
    private var saved = false
    private var specialButtons: [UInt16: NSButton] = [:]
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?

    private static let specialKeys: [(String, UInt16)] = [("⇪ Caps", 57), ("⌘ Right", 54), ("⇧ Right", 60)]

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 260, height: 130), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "Set Hotkey"
        isFloatingPanel = true
        level = .floating

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)

        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.alignment = .center
        updateLabel()

        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        // Special key buttons for modifier-only hotkeys
        let btnRow = NSStackView()
        btnRow.spacing = 8
        for (title, code) in Self.specialKeys {
            let btn = NSButton(title: title, target: self, action: #selector(specialKeyClicked(_:)))
            btn.tag = Int(code)
            btn.bezelStyle = .rounded
            btn.controlSize = .small
            btn.refusesFirstResponder = true
            specialButtons[code] = btn
            btnRow.addArrangedSubview(btn)
        }
        updateButtonSelection()

        stack.addArrangedSubview(label)
        stack.addArrangedSubview(hint)
        stack.addArrangedSubview(btnRow)
        contentView = stack
    }

    private func updateButtonSelection() {
        let current = Settings.shared.hotkeyCode
        let isSpecial = Settings.shared.hotkeyModifiers == 0
        for (baseTitle, code) in Self.specialKeys {
            guard let btn = specialButtons[code] else { continue }
            let selected = isSpecial && code == current
            btn.title = selected ? "✓ \(baseTitle)" : baseTitle
        }
    }

    @objc private func specialKeyClicked(_ sender: NSButton) {
        guard !saved else { return }
        saveHotkey(UInt16(sender.tag), 0)
    }

    override var canBecomeKey: Bool { true }
    override func close() { super.close(); onClose?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close(); return }  // Esc
        guard !saved else { return }
        let mods = event.modifierFlags.intersection([.command, .option, .shift, .control])
        guard !mods.isEmpty else { return }  // Require at least one modifier
        saveHotkey(event.keyCode, CGEventFlags(rawValue: UInt64(mods.rawValue)).rawValue)
    }

    private func saveHotkey(_ code: UInt16, _ mods: UInt64) {
        saved = true
        Settings.shared.hotkeyCode = code
        Settings.shared.hotkeyModifiers = mods
        onSave?()
        updateLabel()
        updateButtonSelection()
        hint.stringValue = "Hotkey set!"
        hint.textColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.close() }
    }

    private func updateLabel() {
        label.stringValue = Self.hotkeyString(Settings.shared.hotkeyCode, CGEventFlags(rawValue: Settings.shared.hotkeyModifiers))
    }

    // Format hotkey as human-readable string (e.g., "⌘⇧K")
    static func hotkeyString(_ code: UInt16, _ mods: CGEventFlags) -> String {
        var s = ""
        if mods.contains(.maskControl) { s += "⌃" }
        if mods.contains(.maskAlternate) { s += "⌥" }
        if mods.contains(.maskShift) { s += "⇧" }
        if mods.contains(.maskCommand) { s += "⌘" }
        return s + keyName(code)
    }

    private static func keyName(_ code: UInt16) -> String {
        let special: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc",
            123: "←", 124: "→", 125: "↓", 126: "↑", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
            97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            57: "⇪ Caps Lock", 54: "⌘ Right Command", 60: "⇧ Right Shift"]
        return special[code] ?? translateKeyCode(code)?.uppercased() ?? "?"
    }
}
