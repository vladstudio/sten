import AppKit
import Carbon

extension NSPanel {
    func positionBelow(_ rect: NSRect) {
        var pt = NSPoint(x: rect.midX - frame.width / 2, y: rect.minY - 4)
        if let screen = NSScreen.main { pt.x = max(screen.visibleFrame.minX, min(pt.x, screen.visibleFrame.maxX - frame.width)) }
        setFrameTopLeftPoint(pt)
    }
}

func translateKeyCode(_ code: UInt16) -> String? {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
    let layout = unsafeBitCast(layoutData, to: CFData.self) as Data
    var deadKeyState: UInt32 = 0, chars = [UniChar](repeating: 0, count: 4), len = 0
    _ = layout.withUnsafeBytes { UCKeyTranslate($0.bindMemory(to: UCKeyboardLayout.self).baseAddress!, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, 4, &len, &chars) }
    return len > 0 ? String(utf16CodeUnits: chars, count: len) : nil
}
