// Speech-to-text engine using FluidAudio (on-device Whisper model)
import FluidAudio
import Foundation

final class TranscriptionEngine {
    private var models: AsrModels?
    private var manager: AsrManager?
    private(set) var isReady = false
    private var isLoading = false

    // Download and initialize the speech model
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

    // Transcribe audio samples to text
    func transcribe(_ audio: [Float]) async -> String? {
        guard let manager, !audio.isEmpty else { return nil }
        do { return normalize(try await manager.transcribe(audio)) }
        catch { return nil }
    }

    // Transcribe audio file to text (streams long files automatically)
    func transcribe(_ url: URL) async -> String? {
        guard let manager else { return nil }
        do { return normalize(try await manager.transcribe(url)) }
        catch { NSLog("[STEN] file transcription failed: %@", "\(error)"); return nil }
    }

    private func normalize(_ result: ASRResult) -> String? {
        let text = result.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    // Release model from memory
    func unload() {
        isReady = false
        manager = nil
        models = nil
    }
}
