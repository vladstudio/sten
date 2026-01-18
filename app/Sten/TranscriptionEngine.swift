import FluidAudio

final class TranscriptionEngine {
    private var models: AsrModels?
    private var manager: AsrManager?
    private(set) var isReady = false
    private var isLoading = false

    func load() async -> Bool {
        guard !isReady, !isLoading else { return isReady }
        isLoading = true
        defer { isLoading = false }
        do {
            models = try await AsrModels.downloadAndLoad(version: .v3)
            guard let m = models else { return false }
            let mgr = AsrManager(config: .default)
            try await mgr.initialize(models: m)
            manager = mgr
            isReady = true
            return true
        } catch { return false }
    }

    func transcribe(_ audio: [Float]) async -> String? {
        guard let manager, !audio.isEmpty else { return nil }
        do {
            let result = try await manager.transcribe(audio)
            let text = result.text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }

    func unload() {
        isReady = false
        manager = nil
        models = nil
    }
}
