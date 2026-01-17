import FluidAudio

final class TranscriptionEngine {
    private var models: AsrModels?
    private var manager: AsrManager?
    var isReady: Bool { manager != nil }

    func load() async -> Bool {
        do {
            models = try await AsrModels.downloadAndLoad(version: .v3)
            guard let m = models else { return false }
            manager = AsrManager(config: .default)
            try await manager?.initialize(models: m)
            return true
        } catch { return false }
    }

    func transcribe(_ audio: [Float]) async -> String? {
        guard let manager, !audio.isEmpty else { return nil }
        do {
            let result = try await manager.transcribe(audio)
            let text = result.text.trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }

    func unload() {
        manager = nil
        models = nil
    }
}
