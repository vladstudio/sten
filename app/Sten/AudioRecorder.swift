// Records audio from microphone, converts to 16kHz mono, reports RMS levels
import AVFoundation
import Accelerate
import CoreMedia

final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    static let sampleRate = 16000
    static let maxDurationSeconds = 5 * 60

    private var session: AVCaptureSession?
    private var buffer: [Float] = []
    private let lock = NSLock()
    private let maxSamples = sampleRate * maxDurationSeconds
    private var ready = false
    private let callbackQueue = DispatchQueue(label: "audio-capture")
    var onLevel: ((Float) -> Void)?
    var onReady: (() -> Void)?

    private lazy var targetFormat: AVAudioFormat? = {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(Self.sampleRate), channels: 1, interleaved: false)
    }()

    func start() throws {
        _ = stop()
        lock.lock(); buffer.removeAll(); ready = false; lock.unlock()

        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw NSError(domain: "AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio input device"])
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(domain: "AudioRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add audio input"])
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: callbackQueue)
        guard session.canAddOutput(output) else {
            throw NSError(domain: "AudioRecorder", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot add audio output"])
        }
        session.addOutput(output)

        session.startRunning()
        self.session = session
    }

    func stop() -> [Float] {
        if let session {
            session.stopRunning()
            self.session = nil
        }
        cachedConverter = nil
        cachedSourceFormat = nil
        lock.lock(); let result = buffer; buffer.removeAll(); lock.unlock()
        return result
    }

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let target = targetFormat,
              let pcmBuffer = pcmBuffer(from: sampleBuffer) else { return }

        let converter = converterFor(pcmBuffer.format, target: target)
        guard let converter, let out = Self.convert(pcmBuffer, converter),
              let channelData = out.floatChannelData?[0] else { return }

        let count = Int(out.frameLength)
        lock.lock()
        if buffer.count + count <= maxSamples {
            buffer.append(contentsOf: UnsafeBufferPointer(start: channelData, count: count))
        }
        let isFirst = !ready
        if isFirst { ready = true }
        lock.unlock()

        let rms = sqrt(vDSP.meanSquare(UnsafeBufferPointer(start: channelData, count: count)))
        DispatchQueue.main.async { [weak self] in
            if isFirst { self?.onReady?() }
            self?.onLevel?(rms)
        }
    }

    // MARK: - Private

    private func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return nil }
        guard let format = AVAudioFormat(streamDescription: asbd) else { return nil }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return nil }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }

        return pcmBuffer
    }

    // Cache converter — recreate only if source format changes
    private var cachedConverter: AVAudioConverter?
    private var cachedSourceFormat: AVAudioFormat?

    private func converterFor(_ source: AVAudioFormat, target: AVAudioFormat) -> AVAudioConverter? {
        if let cached = cachedConverter, cachedSourceFormat == source { return cached }
        guard source.sampleRate > 0, source.channelCount > 0 else { return nil }
        cachedConverter = AVAudioConverter(from: source, to: target)
        cachedSourceFormat = source
        return cachedConverter
    }

    // Resample audio buffer to target format
    private static func convert(_ buf: AVAudioPCMBuffer, _ converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let capacity = AVAudioFrameCount(Double(buf.frameLength) * converter.outputFormat.sampleRate / converter.inputFormat.sampleRate)
        guard let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return nil }
        var err: NSError?
        var provided = false
        converter.convert(to: out, error: &err) { _, s in
            if provided { s.pointee = .noDataNow; return nil }
            provided = true; s.pointee = .haveData; return buf
        }
        return err == nil ? out : nil
    }
}
