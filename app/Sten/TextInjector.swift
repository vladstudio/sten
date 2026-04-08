// Types text into the active app by simulating keyboard events, with clipboard-paste fallback for long text
import AppKit
import Carbon

enum TextInjector {
    static func inject(_ text: String) -> Bool {
        text.count <= 50 ? injectKeys(text) : injectViaPaste(text)
    }

    private static func injectKeys(_ text: String) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        for char in text.unicodeScalars {
            var utf16 = [UniChar](String(char).utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return false }
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)
        }
        return true
    }

    private static func injectViaPaste(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        pb.clearContents()
        pb.setString(text, forType: .string)
        guard let src = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard let saved else { return }
            pb.clearContents()
            pb.writeObjects(saved.map { itemData in
                let item = NSPasteboardItem()
                for (type, data) in itemData { item.setData(data, forType: type) }
                return item
            })
        }
        return true
    }
}
