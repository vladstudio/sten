// Types text into the active app by simulating keyboard events, with clipboard-paste fallback
import AppKit
import Carbon

enum TextInjector {
    static func inject(_ text: String) -> Bool {
        // Resolve each char to a real keycode. Receivers like Screen Sharing forward keycodes,
        // not the unicode string payload, so a dummy virtualKey comes out wrong ("aaaa").
        // Real keycodes fix that when local/remote layouts match; chars we can't resolve
        // (accents, emoji, CJK) fall back to layout-agnostic paste.
        let map = charCodeMap()
        if text.count <= 50 && text.allSatisfy({ map[$0] != nil }) {
            return injectKeys(text, map: map)
        }
        return injectViaPaste(text)
    }

    // char -> (keycode, needsShift) for the current keyboard layout, built per call
    private static func charCodeMap() -> [Character: (code: UInt16, shift: Bool)] {
        var m: [Character: (UInt16, Bool)] = [:]
        for code in UInt16(0)...127 {
            if let s = translateKeyCode(code), let c = s.first { m[c] = (code, false) }
            if let s = translateKeyCode(code, modifiers: 1 << 1), let c = s.first, m[c] == nil { m[c] = (code, true) }
        }
        return m
    }

    private static func injectKeys(_ text: String, map: [Character: (code: UInt16, shift: Bool)]) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        for ch in text {
            guard let (code, shift) = map[ch] else { return false }
            var utf16 = [UniChar](String(ch).utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return false }
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            if shift { down.flags.insert(.maskShift); up.flags.insert(.maskShift) }
            else { down.flags.subtract(.maskShift); up.flags.subtract(.maskShift) }
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