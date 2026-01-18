import AVFoundation
import Accelerate

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var buffer: [Float] = []
    private let lock = NSLock()
    private let maxSamples = 16000 * 60 * 5
    var onLevel: ((Float) -> Void)?

    func start() throws {
        guard !engine.isRunning else { return }
        lock.lock(); buffer.removeAll(); lock.unlock()
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let native = input.outputFormat(forBus: 0)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: native, to: target) else { throw NSError(domain: "AudioRecorder", code: 1) }

        input.installTap(onBus: 0, bufferSize: 4096, format: native) { [weak self] buf, _ in
            guard let self, let out = Self.convert(buf, converter) else { return }
            let data = out.floatChannelData![0], count = Int(out.frameLength)
            self.lock.lock()
            if self.buffer.count + count <= self.maxSamples { self.buffer.append(contentsOf: UnsafeBufferPointer(start: data, count: count)) }
            self.lock.unlock()
            let rms = sqrt(vDSP.meanSquare(UnsafeBufferPointer(start: data, count: count)))
            DispatchQueue.main.async { [weak self] in self?.onLevel?(rms) }
        }
        do { try engine.start() } catch { input.removeTap(onBus: 0); throw error }
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0); engine.stop()
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
