import Carbon
import CoreGraphics
import Foundation

final class HotkeyManager {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pressTime: Date?
    private var keyCode: UInt16 = 49
    private var modifiers: CGEventFlags = []
    private static let modifierKeys: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63] // cmd/shift/opt/ctrl/caps/fn

    var onPress: (() -> Void)?

    func start() {
        stop()
        keyCode = Settings.shared.hotkeyCode
        modifiers = CGEventFlags(rawValue: Settings.shared.hotkeyModifiers)
        let isModifierKey = Self.modifierKeys.contains(keyCode)

        let cb: CGEventTapCallBack = { _, type, event, info in
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(info!).takeUnretainedValue()
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            guard code == mgr.keyCode else { return Unmanaged.passUnretained(event) }

            let flags = event.flags.intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
            let isModKey = HotkeyManager.modifierKeys.contains(code)
            let isDown = (type == .keyDown) || (type == .flagsChanged && mgr.isModifierDown(event.flags))
            let isUp = (type == .keyUp) || (type == .flagsChanged && !mgr.isModifierDown(event.flags))
            let modsMatch = isModKey || flags == mgr.modifiers // modifier keys don't check flags

            if isDown && mgr.pressTime == nil && modsMatch {
                mgr.pressTime = Date()
                return nil
            } else if isUp && mgr.pressTime != nil {
                mgr.pressTime = nil
                DispatchQueue.main.async { mgr.onPress?() }
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        var mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        if isModifierKey { mask |= (1 << CGEventType.flagsChanged.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(mask), callback: cb, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func isModifierDown(_ flags: CGEventFlags) -> Bool {
        switch keyCode {
        case 57: return flags.contains(.maskAlphaShift) // caps lock
        case 54, 55: return flags.contains(.maskCommand)
        case 56, 60: return flags.contains(.maskShift)
        case 58, 61: return flags.contains(.maskAlternate) // option
        case 59, 62: return flags.contains(.maskControl)
        case 63: return flags.contains(.maskSecondaryFn) // fn
        default: return false
        }
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes) }
        tap = nil; runLoopSource = nil; pressTime = nil
    }
}
