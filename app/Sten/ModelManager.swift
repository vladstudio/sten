import Foundation

final class ModelManager: NSObject, URLSessionDownloadDelegate {
    static let shared = ModelManager()
    private let baseURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
    lazy var modelsDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Sten/models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var session: URLSession!
    private var downloadTask: URLSessionDownloadTask?
    private var currentModelId: String?
    var onProgress: ((Double) -> Void)?
    var onComplete: ((Bool) -> Void)?

    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }

    private let validModels = ["small", "medium", "large-v3-turbo", "large-v3"]

    func modelPath(_ id: String) -> URL { modelsDir.appendingPathComponent("ggml-\(id).bin") }
    func isDownloaded(_ id: String) -> Bool { FileManager.default.fileExists(atPath: modelPath(id).path) }
    func downloadedModels() -> [String] { validModels.filter { isDownloaded($0) } }
    func firstAvailableModel() -> String? { downloadedModels().first }
    func hasAnyModel() -> Bool { downloadedModels().isEmpty == false }

    func download(_ id: String) {
        guard downloadTask == nil else { return }
        currentModelId = id
        let url = URL(string: "\(baseURL)/ggml-\(id).bin")!
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
    }

    func cancel() { downloadTask?.cancel(); downloadTask = nil; currentModelId = nil }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = currentModelId else { return }
        let dest = modelPath(id)
        do { try? FileManager.default.removeItem(at: dest); try FileManager.default.moveItem(at: location, to: dest) }
        catch { self.downloadTask = nil; currentModelId = nil; onComplete?(false); return }
        self.downloadTask = nil; currentModelId = nil; onComplete?(true)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil { downloadTask = nil; currentModelId = nil; onComplete?(false) }
    }
}
