import Carbon

enum TextInjector {
    static func inject(_ text: String) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for char in text.unicodeScalars {
            var utf16 = [UniChar](String(char).utf16)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            down?.post(tap: .cgAnnotatedSessionEventTap)
            up?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
