import Foundation

// Pause/resume system media playback via the `media-control` CLI (Homebrew: ungive/media-control).
//
// Since macOS 15.4 the `mediaremoted` daemon requires a private entitlement, so third-party apps
// can no longer load MediaRemote directly to read now-playing state or send play/pause. The CLI
// runs those calls through an entitled system binary, so it reports *true* playing state and
// exposes separate `play`/`pause` commands (not just a toggle) — which lets us pause only when
// something is actually playing and resume only what we paused.
//
// All work is serialized on one queue and runs off the main thread: recording starts with no
// added latency, and a pending `pause` always completes before a `resume` runs.
enum MediaPlayback {
    private static let queue = DispatchQueue(label: "sten.mediaplayback")
    private static var pausedByUs = false  // touched only on `queue`

    private static let cliPath: String? = {
        ["/opt/homebrew/bin/media-control", "/usr/local/bin/media-control"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    // Whether the `media-control` CLI is installed (resolved once at launch).
    static var isAvailable: Bool { cliPath != nil }

    // Pause playback if something is actually playing. Async; no-op if nothing is playing.
    static func pauseIfPlaying() {
        queue.async {
            guard isPlaying() else {
                NSLog("[STEN] media pause skipped: nothing playing")
                return
            }
            run("pause")
            pausedByUs = true
        }
    }

    // Resume playback, but only what we paused. Serialized after any pending pause.
    static func resume() {
        queue.async {
            guard pausedByUs else { return }
            pausedByUs = false
            run("play")
        }
    }

    // MARK: - CLI

    private static func isPlaying() -> Bool {
        guard let json = run("get"), let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return obj["playing"] as? Bool ?? false
    }

    @discardableResult
    private static func run(_ args: String...) -> String? {
        guard let cliPath else {
            NSLog("[STEN] media-control not installed; skipping playback control")
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let out = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: out, encoding: .utf8)
        } catch {
            NSLog("[STEN] media-control failed: %@", error.localizedDescription)
            return nil
        }
    }
}
