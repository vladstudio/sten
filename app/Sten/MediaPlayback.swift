import AppKit
import Foundation

enum MediaPlayback {
    private typealias IsPlayingCompletion = @convention(block) (Bool) -> Void
    private typealias IsPlayingFn = @convention(c) (DispatchQueue, @escaping IsPlayingCompletion) -> Void
    private typealias NowPlayingInfoCompletion = @convention(block) (CFDictionary?) -> Void
    private typealias NowPlayingInfoFn = @convention(c) (DispatchQueue, @escaping NowPlayingInfoCompletion) -> Void
    private typealias SendCommandFn = @convention(c) (Int32, CFDictionary?) -> Bool

    private static let mediaRemote = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework"))
    private static let isPlaying = load("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: IsPlayingFn.self)
    private static let nowPlayingInfo = load("MRMediaRemoteGetNowPlayingInfo", as: NowPlayingInfoFn.self)
    private static let sendCommand = load("MRMediaRemoteSendCommand", as: SendCommandFn.self)
    private static let playbackRateKey = loadConstant("kMRMediaRemoteNowPlayingInfoPlaybackRate")

    private static let playbackStateTimeout: DispatchTimeInterval = .milliseconds(500)

    // MediaRemote command IDs: play=0, pause=1. Hardware media key code: play/pause=16.
    private static let playCommand: Int32 = 0
    private static let pauseCommand: Int32 = 1
    private static let playKey: Int32 = 16

    static func pauseIfPlaying() -> Bool {
        guard isPlayingNow() else {
            NSLog("[STEN] media pause skipped: playback not detected")
            return false
        }
        if sendCommand?(pauseCommand, nil) == true { return true }
        NSLog("[STEN] MediaRemote pause failed; falling back to media key")
        sendPlayPause()
        return true
    }

    static func resume(_ paused: Bool) {
        guard paused, !isPlayingNow() else { return }
        if sendCommand?(playCommand, nil) == true { return }
        NSLog("[STEN] MediaRemote play failed; falling back to media key")
        sendPlayPause()
    }

    private static func isPlayingNow() -> Bool {
        if let playing = playingFromNowPlayingInfo() { return playing }
        guard let isPlaying else { return false }
        var playing = false
        let sem = DispatchSemaphore(value: 0)
        isPlaying(DispatchQueue.global(qos: .userInitiated)) { playing = $0; sem.signal() }
        guard sem.wait(timeout: .now() + playbackStateTimeout) == .success else {
            NSLog("[STEN] MediaRemote playing-state check timed out")
            return false
        }
        return playing
    }

    private static func playingFromNowPlayingInfo() -> Bool? {
        guard let nowPlayingInfo else { return nil }
        var info: CFDictionary?
        let sem = DispatchSemaphore(value: 0)
        nowPlayingInfo(DispatchQueue.global(qos: .userInitiated)) { info = $0; sem.signal() }
        guard sem.wait(timeout: .now() + playbackStateTimeout) == .success else {
            NSLog("[STEN] MediaRemote now-playing info check timed out")
            return nil
        }
        guard let dict = info as? [String: Any] else { return nil }

        if let key = playbackRateKey as String?,
           let rate = dict[key] as? NSNumber {
            return rate.doubleValue > 0
        }
        if let rate = dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber {
            return rate.doubleValue > 0
        }
        return nil
    }

    private static func load<T>(_ name: String, as type: T.Type) -> T? {
        guard let mediaRemote else {
            NSLog("[STEN] MediaRemote framework unavailable")
            return nil
        }
        CFBundleLoadExecutable(mediaRemote)
        guard let pointer = CFBundleGetFunctionPointerForName(mediaRemote, name as CFString) else {
            NSLog("[STEN] MediaRemote function unavailable: %@", name)
            return nil
        }
        return unsafeBitCast(pointer, to: type)
    }

    private static func loadConstant(_ name: String) -> CFString? {
        guard let mediaRemote else { return nil }
        CFBundleLoadExecutable(mediaRemote)
        guard let pointer = CFBundleGetDataPointerForName(mediaRemote, name as CFString) else {
            NSLog("[STEN] MediaRemote constant unavailable: %@", name)
            return nil
        }
        return pointer.assumingMemoryBound(to: CFString.self).pointee
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
