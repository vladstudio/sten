import Foundation
import ServiceManagement

final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    var startOnLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set { try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
    }

    var hotkeyCode: UInt16 {
        get { UInt16(clamping: defaults.integer(forKey: "hkCode")).or(49) }
        set { defaults.set(Int(newValue), forKey: "hkCode"); defaults.set(true, forKey: "hkSet") }
    }

    var hotkeyModifiers: UInt64 {
        get { defaults.bool(forKey: "hkSet") ? UInt64(clamping: defaults.integer(forKey: "hkMods")) : 0x180000 }
        set { defaults.set(Int(newValue), forKey: "hkMods"); defaults.set(true, forKey: "hkSet") }
    }

    var onboardingDone: Bool {
        get { defaults.bool(forKey: "onboardingDone") }
        set { defaults.set(newValue, forKey: "onboardingDone") }
    }

    var enabledTransforms: Set<String> {
        get { Set(defaults.stringArray(forKey: "enabledTransforms") ?? []) }
        set { defaults.set(Array(newValue), forKey: "enabledTransforms") }
    }
}

private extension UInt16 { func or(_ d: UInt16) -> UInt16 { self != 0 ? self : d } }
