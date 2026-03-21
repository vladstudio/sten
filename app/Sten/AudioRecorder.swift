// Records audio from microphone, converts to 16kHz mono, reports RMS levels
import AVFoundation
import Accelerate
import CoreMedia

final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    static let sampleRate = 16000
    static let maxDurationSeconds = 5 * 60
    private static let warmupSamples = sampleRate / 10  // 100ms
    private static let maxSamples = sampleRate * maxDurationSeconds
    private static let sessionKeepAliveSeconds: Double = 60

    private var session: AVCaptureSession?
    private var stopTimer: DispatchWorkItem?
    private var currentDeviceID: String?
    private var cachedConverter: AVAudioConverter?
    private var cachedSourceFormat: AVAudioFormat?
    private var buffer: [Float] = []
    private let lock = NSLock()
    private var ready = false
    private var warmupCount = 0
    private var capturing = false
    private var generation = 0
    private var loggedDropOnce = false
    private let callbackQueue = DispatchQueue(label: "audio-capture")
    private let sessionQueue = DispatchQueue(label: "session-lifecycle")
    var onLevel: ((Float) -> Void)?
    var onError: ((String) -> Void)?

    private lazy var targetFormat: AVAudioFormat? = {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(Self.sampleRate), channels: 1, interleaved: false)
    }()

    /// Configure the AVCaptureSession without starting it. Call once after mic permission is granted.
    func prepare() throws {
        guard session == nil else { return }

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

        self.session = session
        self.currentDeviceID = device.uniqueID

        NotificationCenter.default.addObserver(self, selector: #selector(deviceDisconnected(_:)),
                                               name: .AVCaptureDeviceWasDisconnected, object: nil)
        NSLog("[STEN] session prepared, device=%@", device.localizedName)
    }

    /// Begin capturing audio. If session is already running (hot), captures immediately with no warmup.
    func start() throws {
        stopTimer?.cancel()
        stopTimer = nil
        if session != nil,
           let dev = AVCaptureDevice.default(for: .audio),
           dev.uniqueID != currentDeviceID {
            NSLog("[STEN] default device changed to %@, rebuilding session", dev.localizedName)
            teardown()
        }
        try prepare()

        let alreadyRunning = session?.isRunning ?? false

        lock.lock()
        buffer.removeAll()
        ready = alreadyRunning  // skip warmup if session already hot
        warmupCount = 0
        capturing = true
        generation += 1
        let gen = generation
        loggedDropOnce = false
        lock.unlock()

        if !alreadyRunning {
            let session = self.session
            sessionQueue.async {
                session?.startRunning()
            }
        }

        // Watchdog: if no audio arrives within 3 seconds, fire error
        callbackQueue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let stalled = self.capturing && !self.ready && self.generation == gen
            self.lock.unlock()
            if stalled {
                NSLog("[STEN] watchdog: no audio after 3s")
                DispatchQueue.main.async { self.onError?("No audio from microphone") }
            }
        }
    }

    /// Stop accumulating and return captured samples. Session stays running for 60s for fast restart.
    func stop() -> [Float] {
        lock.lock()
        capturing = false
        let result = buffer
        buffer.removeAll()
        lock.unlock()
        stopTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.session?.stopRunning()
            NSLog("[STEN] session stopped after keep-alive")
        }
        stopTimer = item
        sessionQueue.asyncAfter(deadline: .now() + Self.sessionKeepAliveSeconds, execute: item)
        return result
    }

    /// Tear down the session entirely (memory pressure, app quit).
    func teardown() {
        stopTimer?.cancel()
        stopTimer = nil
        guard session != nil else { return }
        lock.lock()
        capturing = false
        buffer.removeAll()
        lock.unlock()
        let s = session
        session = nil
        cachedConverter = nil
        cachedSourceFormat = nil
        currentDeviceID = nil
        NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceWasDisconnected, object: nil)
        sessionQueue.async { s?.stopRunning() }
        NSLog("[STEN] session torn down")
    }

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.lock()
        let active = capturing
        lock.unlock()
        guard active else { return }

        guard let target = targetFormat,
              let pcmBuffer = pcmBuffer(from: sampleBuffer) else {
            logDrop("pcm extraction failed")
            return
        }

        let converter = converterFor(pcmBuffer.format, target: target)
        guard let converter, let out = Self.convert(pcmBuffer, converter),
              let channelData = out.floatChannelData?[0] else {
            logDrop(String(format: "resampling failed (rate=%.0f ch=%d)", pcmBuffer.format.sampleRate, pcmBuffer.format.channelCount))
            return
        }

        let count = Int(out.frameLength)
        lock.lock()
        if !ready {
            warmupCount += count
            if warmupCount >= Self.warmupSamples { ready = true }
        } else if buffer.count + count <= Self.maxSamples {
            buffer.append(contentsOf: UnsafeBufferPointer(start: channelData, count: count))
        }
        lock.unlock()

        let rms = sqrt(vDSP.meanSquare(UnsafeBufferPointer(start: channelData, count: count)))
        DispatchQueue.main.async { [weak self] in
            self?.onLevel?(rms)
        }
    }

    // MARK: - Device monitoring

    @objc private func deviceDisconnected(_ note: Notification) {
        guard let device = note.object as? AVCaptureDevice, device.uniqueID == currentDeviceID else { return }
        NSLog("[STEN] audio device disconnected: %@", device.localizedName)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let wasCapturing: Bool
            self.lock.lock()
            wasCapturing = self.capturing
            self.lock.unlock()
            self.teardown()
            if wasCapturing { self.onError?("Microphone disconnected") }
        }
    }

    // MARK: - Private

    private func logDrop(_ reason: String) {
        lock.lock()
        let shouldLog = !loggedDropOnce
        if shouldLog { loggedDropOnce = true }
        lock.unlock()
        if shouldLog { NSLog("[STEN] audio frame dropped: %@", reason) }
    }

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
