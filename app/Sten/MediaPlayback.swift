import AppKit
import Foundation

enum MediaPlayback {
    private typealias IsPlayingCompletion = @convention(block) (Bool) -> Void
    private typealias IsPlayingFn = @convention(c) (DispatchQueue, @escaping IsPlayingCompletion) -> Void
    private typealias SendCommandFn = @convention(c) (Int32, CFDictionary?) -> Bool

    private static let mediaRemote = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework"))
    private static let isPlaying = load("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: IsPlayingFn.self)
    private static let sendCommand = load("MRMediaRemoteSendCommand", as: SendCommandFn.self)

    private static let playCommand: Int32 = 0
    private static let pauseCommand: Int32 = 1
    private static let playKey: Int32 = 16

    static func pauseIfPlaying() -> Bool {
        if isPlayingNow(), sendCommand?(pauseCommand, nil) == true { return true }
        sendPlayPause()
        return true
    }

    static func resume(_ paused: Bool) {
        guard paused, !isPlayingNow() else { return }
        if sendCommand?(playCommand, nil) == true { return }
        sendPlayPause()
    }

    private static func isPlayingNow() -> Bool {
        guard let isPlaying else { return false }
        var playing = false
        let sem = DispatchSemaphore(value: 0)
        isPlaying(DispatchQueue.global(qos: .userInitiated)) { playing = $0; sem.signal() }
        _ = sem.wait(timeout: .now() + 1)
        return playing
    }

    private static func load<T>(_ name: String, as type: T.Type) -> T? {
        guard let mediaRemote else { return nil }
        CFBundleLoadExecutable(mediaRemote)
        guard let pointer = CFBundleGetFunctionPointerForName(mediaRemote, name as CFString) else { return nil }
        return unsafeBitCast(pointer, to: type)
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
