// Persistent user preferences backed by ~/.config/sten/config.json
import Foundation
import MacAppKit

final class Settings {
    static let shared = Settings()
    static let stenDir: URL = {
        ConfigDir.migrateDirectory(from: "~/.sten", to: "sten")
        return ConfigDir.url(for: "sten")
    }()
    static let configFile = stenDir.appendingPathComponent("config.json")

    // Launch at login — config.json is source of truth, SMAppService is side-effect only
    var startOnLogin: Bool {
        get { read("start_on_login") as? Bool ?? false }
        set {
            write("start_on_login", newValue)
            if newValue { LoginItem.enable() } else { LoginItem.disable() }
        }
    }

    var keepMicActiveAfterStart: Bool {
        get { read("keep_mic_active_after_start") as? Bool ?? true }
        set { write("keep_mic_active_after_start", newValue) }
    }

    var pauseMediaWhileListening: Bool {
        get { read("pause_media_while_listening") as? Bool ?? true }
        set { write("pause_media_while_listening", newValue) }
    }

    func syncLoginItem() {
        if startOnLogin { LoginItem.enable() } else { LoginItem.disable() }
    }

    // Global hotkey settings (keycode + modifiers)
    var hotkeyCode: UInt16 {
        get { (read("hotkey_code") as? Int).map { UInt16(clamping: $0) } ?? 49 }
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

    var includeContext: Bool {
        get { read("include_context") as? Bool ?? false }
        set { write("include_context", newValue) }
    }

    // Run the "Fix Speech" Tetra command on each transcription.
    var fixWithTetra: Bool {
        get { read("fix_with_tetra") as? Bool ?? true }
        set { write("fix_with_tetra", newValue) }
    }

    var tetraPort: Int {
        get { read("tetra_port") as? Int ?? 24100 }
        set { write("tetra_port", newValue) }
    }

    // Write an arbitrary key into config.json (used by OnboardingPanel for API keys)
    func setConfig(_ key: String, _ value: Any) { write(key, value) }

    // MARK: - Private

    private var cache: [String: Any]?

    private func load() -> [String: Any] {
        if let cache { return cache }
        let dict = (try? Data(contentsOf: Self.configFile))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        cache = dict
        return dict
    }

    private func read(_ key: String) -> Any? { load()[key] }

    private func write(_ key: String, _ value: Any) {
        var config = load()
        config[key] = value
        cache = config
        if let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: Self.configFile, options: .atomic)
        }
    }
}
