// Captures text context from the active app via Accessibility API
import AppKit

enum ContextCapture {
    static func fromActiveApp() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            NSLog("[STEN] context: no frontmost app")
            return nil
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var info: [String: String] = ["app": app.localizedName ?? ""]
        if let win: AXUIElement = axAttr(axApp, kAXFocusedWindowAttribute) {
            info["window"] = axAttr(win, kAXTitleAttribute)
        }
        if let el: AXUIElement = axAttr(axApp, kAXFocusedUIElementAttribute),
           let text: String = axAttr(el, kAXValueAttribute), !text.isEmpty {
            info["text"] = String(text.suffix(1000))
        }
        guard info.count > 1 else { NSLog("[STEN] context: only app name, skipping"); return nil }
        let json = try? String(data: JSONSerialization.data(withJSONObject: info), encoding: .utf8)
        NSLog("[STEN] context: %@", json ?? "nil")
        return json
    }

    private static func axAttr<T>(_ el: AXUIElement, _ attr: String) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success else { return nil }
        return ref as? T
    }
}
