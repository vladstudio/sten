// Persistent user preferences backed by ~/.sten/config.json
import Foundation
import ServiceManagement

final class Settings {
    static let shared = Settings()
    static let stenDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".sten")
    static let configFile = stenDir.appendingPathComponent("config.json")

    // Launch at login — config.json is source of truth, SMAppService is side-effect only
    var startOnLogin: Bool {
        get { read("start_on_login") as? Bool ?? false }
        set {
            write("start_on_login", newValue)
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }

    func syncLoginItem() {
        try? startOnLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    }

    // Global hotkey settings (keycode + modifiers)
    var hotkeyCode: UInt16 {
        get { (read("hotkey_code") as? Int).map { UInt16(clamping: $0) }?.or(49) ?? 49 }
        set { write("hotkey_code", Int(newValue)); write("hotkey_set", true) }
    }

    var hotkeyModifiers: UInt64 {
        get {
            let isSet = read("hotkey_set") as? Bool ?? false
            guard isSet, let v = read("hotkey_modifiers") as? Int else { return 0x180000 }
            return UInt64(bitPattern: Int64(v))
        }
        set { write("hotkey_modifiers", Int(newValue)); write("hotkey_set", true) }
    }

    var onboardingDone: Bool {
        get { read("onboarding_done") as? Bool ?? false }
        set { write("onboarding_done", newValue) }
    }

    // Set of enabled transform script names
    var enabledTransforms: Set<String> {
        get { Set(read("enabled_transforms") as? [String] ?? []) }
        set { write("enabled_transforms", Array(newValue)) }
    }

    // Write an arbitrary key into config.json (used by OnboardingPanel for API keys)
    func setConfig(_ key: String, _ value: Any) { write(key, value) }

    // MARK: - Private

    private func read(_ key: String) -> Any? {
        guard let data = try? Data(contentsOf: Self.configFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json[key]
    }

    private func write(_ key: String, _ value: Any) {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.stenDir, withIntermediateDirectories: true)
        var config: [String: Any] = [:]
        if let data = try? Data(contentsOf: Self.configFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { config = json }
        config[key] = value
        if let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: Self.configFile)
        }
    }
}

private extension UInt16 { func or(_ d: UInt16) -> UInt16 { self != 0 ? self : d } }
