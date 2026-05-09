// Speech-to-text engine using FluidAudio (Parakeet TDT v3, on-device).
import FluidAudio
import Foundation

final class TranscriptionEngine {
    static let modelDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("FluidAudio/Models")

    private var manager: AsrManager?
    private(set) var isReady = false
    private var isLoading = false

    func load() async -> Bool {
        guard !isReady, !isLoading else { return isReady }
        isLoading = true
        defer { isLoading = false }
        do {
            let m = try await AsrModels.downloadAndLoad(version: .v3)
            let mgr = AsrManager(config: .default)
            try await mgr.loadModels(m)
            self.manager = mgr
            self.isReady = true
            return true
        } catch {
            NSLog("[STEN] model load failed: %@", "\(error)")
            return false
        }
    }

    // Transcribe audio samples to text
    func transcribe(_ audio: [Float]) async -> String? {
        guard let manager, !audio.isEmpty else { return nil }
        do {
            var state = try TdtDecoderState()
            return normalize(try await manager.transcribe(audio, decoderState: &state))
        } catch {
            NSLog("[STEN] buffer transcription failed: %@", "\(error)")
            return nil
        }
    }

    // Transcribe audio file to text (streams long files automatically)
    func transcribe(_ url: URL) async -> String? {
        guard let manager else { return nil }
        do {
            var state = try TdtDecoderState()
            return normalize(try await manager.transcribe(url, decoderState: &state))
        } catch {
            NSLog("[STEN] file transcription failed: %@", "\(error)")
            return nil
        }
    }

    private func normalize(_ result: ASRResult) -> String? {
        let text = result.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    func unload() {
        isReady = false
        isLoading = false
        manager = nil
    }
}
