// Speech-to-text engine using FluidAudio (on-device Whisper model)
import FluidAudio
import Foundation

extension AsrManager: @unchecked @retroactive Sendable {}

final class TranscriptionEngine {
    static let modelDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("FluidAudio/Models")

    private var models: AsrModels?
    private var manager: AsrManager?
    private(set) var isReady = false
    private var isLoading = false

    // Download and initialize the speech model. State changes happen on MainActor.
    func load() async -> Bool {
        guard !isReady, !isLoading else { return isReady }
        isLoading = true
        do {
            let m = try await AsrModels.downloadAndLoad(version: .v3)
            let mgr = AsrManager(config: .default)
            try await mgr.initialize(models: m)
            await MainActor.run { [m, mgr] in
                self.models = m
                self.manager = mgr
                self.isReady = true
                self.isLoading = false
            }
            return true
        } catch { isLoading = false; return false }
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
