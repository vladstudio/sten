// Captures text context from the active app via Accessibility API + clipboard fallback
import AppKit

enum ContextCapture {
    /// Try AX first (native apps), fall back to Cmd+C clipboard trick (Electron apps).
    static func capture() -> String? {
        textViaAX() ?? textViaClipboard()
    }

    private static func textViaAX() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let el: AXUIElement = axAttr(axApp, kAXFocusedUIElementAttribute) else { return nil }
        let text: String? = axAttr(el, kAXValueAttribute) ?? axAttr(el, kAXSelectedTextAttribute)
        guard let text, !text.isEmpty else { return nil }
        return String(text.suffix(1000))
    }

    private static func textViaClipboard() -> String? {
        let pb = NSPasteboard.general
        let savedChangeCount = pb.changeCount
        let saved = pb.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }

        defer {
            if let saved {
                pb.clearContents()
                pb.writeObjects(saved.map { itemData in
                    let item = NSPasteboardItem()
                    for (type, data) in itemData { item.setData(data, forType: type) }
                    return item
                })
            }
        }

        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false) else { return nil }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        for _ in 0..<5 {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
            if pb.changeCount != savedChangeCount { break }
        }

        guard pb.changeCount != savedChangeCount,
              let text = pb.string(forType: .string), !text.isEmpty else { return nil }
        return String(text.suffix(1000))
    }

    private static func axAttr<T>(_ el: AXUIElement, _ attr: String) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success else { return nil }
        return ref as? T
    }
}
