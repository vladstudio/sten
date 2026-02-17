// Persistent user preferences (UserDefaults + file-based onboarding state)
import Foundation
import ServiceManagement

final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    // Launch at login via SMAppService
    var startOnLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set { try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
    }

    // Global hotkey settings (keycode + modifiers)
    var hotkeyCode: UInt16 {
        get { UInt16(clamping: defaults.integer(forKey: "hkCode")).or(49) }
        set { defaults.set(Int(newValue), forKey: "hkCode"); defaults.set(true, forKey: "hkSet") }
    }

    var hotkeyModifiers: UInt64 {
        get { defaults.bool(forKey: "hkSet") ? UInt64(bitPattern: Int64(defaults.integer(forKey: "hkMods"))) : 0x180000 }
        set { defaults.set(Int(newValue), forKey: "hkMods"); defaults.set(true, forKey: "hkSet") }
    }

    static let stenDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".sten")

    private static let doneMarker = stenDir.appendingPathComponent(".setup-done")

    var onboardingDone: Bool {
        get { FileManager.default.fileExists(atPath: Self.doneMarker.path) }
        set {
            if newValue {
                try? FileManager.default.createDirectory(at: Self.stenDir, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: Self.doneMarker.path, contents: nil)
            } else {
                try? FileManager.default.removeItem(at: Self.doneMarker)
            }
        }
    }

    // Set of enabled transform script names
    var enabledTransforms: Set<String> {
        get { Set(defaults.stringArray(forKey: "enabledTransforms") ?? []) }
        set { defaults.set(Array(newValue), forKey: "enabledTransforms") }
    }
}

private extension UInt16 { func or(_ d: UInt16) -> UInt16 { self != 0 ? self : d } }
