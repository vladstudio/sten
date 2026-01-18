import AVFoundation
import Accelerate

final class AudioRecorder {
    private var engine: AVAudioEngine?
    private var buffer: [Float] = []
    private let lock = NSLock()
    private let maxSamples = 16000 * 60 * 5
    var onLevel: ((Float) -> Void)?

    func start() throws {
        _ = stop()
        lock.lock(); buffer.removeAll(); lock.unlock()

        let eng = AVAudioEngine()
        let input = eng.inputNode
        eng.prepare()

        let native = input.outputFormat(forBus: 0)
        guard native.sampleRate > 0, native.channelCount > 0 else {
            throw NSError(domain: "AudioRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Audio hardware not ready"])
        }
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: native, to: target) else {
            throw NSError(domain: "AudioRecorder", code: 1)
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: native) { [weak self] buf, _ in
            guard let self, let out = Self.convert(buf, converter) else { return }
            let data = out.floatChannelData![0], count = Int(out.frameLength)
            self.lock.lock()
            if self.buffer.count + count <= self.maxSamples { self.buffer.append(contentsOf: UnsafeBufferPointer(start: data, count: count)) }
            self.lock.unlock()
            let rms = sqrt(vDSP.meanSquare(UnsafeBufferPointer(start: data, count: count)))
            DispatchQueue.main.async { [weak self] in self?.onLevel?(rms) }
        }

        do {
            try eng.start()
            engine = eng
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    func stop() -> [Float] {
        if let eng = engine {
            eng.inputNode.removeTap(onBus: 0)
            eng.stop()
            engine = nil
        }
        lock.lock(); let result = buffer; buffer.removeAll(); lock.unlock()
        return result
    }

    private static func convert(_ buf: AVAudioPCMBuffer, _ converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let capacity = AVAudioFrameCount(Double(buf.frameLength) * converter.outputFormat.sampleRate / converter.inputFormat.sampleRate)
        guard let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return nil }
        var err: NSError?
        converter.convert(to: out, error: &err) { _, s in s.pointee = .haveData; return buf }
        return err == nil ? out : nil
    }
}
