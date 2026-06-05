import AppKit
import Foundation

enum MediaPlayback {
    private static let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework"))!
    private static let isPlaying = unsafeBitCast(CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying" as CFString)!,
                                                 to: (@convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void).self)
    private static let playKey: Int32 = 16

    static func pauseIfPlaying() -> Bool {
        guard isPlayingNow() else { return false }
        sendPlayPause()
        return true
    }

    static func resume(_ paused: Bool) {
        if paused { sendPlayPause() }
    }

    private static func isPlayingNow() -> Bool {
        var playing = false
        let sem = DispatchSemaphore(value: 0)
        isPlaying(DispatchQueue.global(qos: .userInitiated)) { playing = $0; sem.signal() }
        _ = sem.wait(timeout: .now() + 0.2)
        return playing
    }

    private static func sendPlayPause() {
        func post(_ down: Bool) {
            let data1 = Int((playKey << 16) | (down ? 0xA00 : 0xB00))
            let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: .init(rawValue: down ? 0xA00 : 0xB00), timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
        post(true); post(false)
    }
}
