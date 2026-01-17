import Foundation
import CWhisper

final class TranscriptionEngine {
    private var ctx: OpaquePointer?
    var isReady: Bool { ctx != nil }

    func loadModel(_ path: URL) -> Bool {
        unload()
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        ctx = whisper_init_from_file_with_params(path.path, cparams)
        return ctx != nil
    }

    func unload() {
        if let ctx = self.ctx { whisper_free(ctx) }
        ctx = nil
    }

    func transcribe(_ audio: [Float], language: String = "auto") -> String? {
        guard let ctx = ctx, !audio.isEmpty else { return nil }
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = 4
        params.print_progress = false
        params.print_timestamps = false
        params.language = language == "auto" ? nil : (language as NSString).utf8String
        let result = audio.withUnsafeBufferPointer { whisper_full(ctx, params, $0.baseAddress, Int32($0.count)) }
        guard result == 0 else { return nil }
        let n = whisper_full_n_segments(ctx)
        let text = (0..<n).compactMap { whisper_full_get_segment_text(ctx, $0).map { String(cString: $0) } }.joined().trimmingCharacters(in: .whitespaces)
        return text.contains("[BLANK_AUDIO]") ? nil : text
    }

    deinit { unload() }
}
