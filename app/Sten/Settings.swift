import Foundation
import ServiceManagement

final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard
    private let validModels = ["small", "medium", "large-v3-turbo", "large-v3"]
    var selectedModel: String {
        get { let v = defaults.string(forKey: "selectedModel"); return validModels.contains(v ?? "") ? v! : "small" }
        set { defaults.set(newValue, forKey: "selectedModel") }
    }
    var selectedLanguage: String {
        get { defaults.string(forKey: "selectedLanguage") ?? "auto" }
        set { defaults.set(newValue, forKey: "selectedLanguage") }
    }

    var startOnLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set { try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
    }

    var effectiveLanguage: String {
        if selectedLanguage == "follow os" { return InputSourceObserver.shared.currentLanguage }
        return selectedLanguage
    }

    var hotkeyCode: UInt16 {
        get { UInt16(clamping: defaults.integer(forKey: "hkCode")).or(49) }
        set { defaults.set(Int(newValue), forKey: "hkCode"); defaults.set(true, forKey: "hkSet") }
    }
    var hotkeyModifiers: UInt64 {
        get { defaults.bool(forKey: "hkSet") ? UInt64(clamping: defaults.integer(forKey: "hkMods")) : 0x180000 }
        set { defaults.set(Int(newValue), forKey: "hkMods") }
    }
}

private extension UInt16 { func or(_ d: UInt16) -> UInt16 { self != 0 ? self : d } }
