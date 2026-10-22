import Foundation
// URLSession lives in Foundation on Apple and in FoundationNetworking elsewhere.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// One file of a pinned model, and the size a complete copy has.
public struct ModelFile: Hashable, Sendable {
    public let name: String
    public let size: Int64
    public init(name: String, size: Int64) {
        self.name = name
        self.size = size
    }
}

/// A model at a fixed revision of a Hugging Face repository, file by file.
/// Which models, and which sizes, stay with the app.
public protocol StoredModel: Sendable {
    var id: String { get }
    var repo: String { get }
    var revision: String { get }
    var files: [ModelFile] { get }
}

extension StoredModel {
    /// Bytes to fetch: the sum of the pinned file sizes.
    public var download: Int64 { files.reduce(0) { $0 + $1.size } }
}

/// Models on this device: a complete copy is every pinned file at its size.
///
/// `directory` is this app's own folder, searched first and the only folder
/// ever written. `alsoSearching` are further parents of `<id>` (a checkout's
/// `models/`, for development) and are never written. A symlink contributes
/// the size of the file it names. With `leaveLinks`, a symlink at
/// `directory/<id>` whose files do not match is left in place: writing
/// through it would change the files it names.
public struct ModelStore: Sendable {
    public struct Failure: LocalizedError, Sendable {
        public let errorDescription: String?
        public init(_ message: String) { errorDescription = message }
    }

    public let directory: URL
    public let alsoSearching: [URL]
    /// When set, a symlink at `directory/<id>` is never written through.
    public let leaveLinks: Bool

    public init(directory: URL, alsoSearching: [URL] = [], leaveLinks: Bool = false) {
        self.directory = directory
        self.alsoSearching = alsoSearching
        self.leaveLinks = leaveLinks
    }

    /// Where `model` is, if every pinned file is there at its size.
    public func location(of model: some StoredModel) -> URL? {
        location(of: model, in: ([directory] + alsoSearching).map { $0.appending(path: model.id) })
    }

    /// `folders` are candidate model directories, already including the id.
    public func location(of model: some StoredModel, in folders: [URL]) -> URL? {
        folders.first { folder in
            model.files.allSatisfy { Self.byteCount(folder.appending(path: $0.name)) == $0.size }
        }
    }

    public func isDownloaded(_ model: some StoredModel) -> Bool { location(of: model) != nil }

    /// Downloaded into this app's storage, so the app can delete it. A copy
    /// found only under `alsoSearching` belongs to whoever put it there.
    public func isDeletable(_ model: some StoredModel) -> Bool { used(model) > 0 }

    /// Bytes of this model under `directory`. Missing files contribute nothing.
    public func used(_ model: some StoredModel) -> Int64 {
        let folder = directory.appending(path: model.id)
        return model.files.compactMap { Self.byteCount(folder.appending(path: $0.name)) }.reduce(0, +)
    }

    /// Remove this app's copy. A missing folder, or a symlink whose target is
    /// gone, is left as it is. `alsoSearching` is never removed.
    public func delete(_ model: some StoredModel) throws {
        let folder = directory.appending(path: model.id)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    /// Fetch whatever of `model` is not already complete. `progress` runs from
    /// 0 to 1 while bytes arrive. A complete copy, wherever it was found, is
    /// returned without writing.
    @discardableResult
    public func download(
        _ model: some StoredModel, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        if let found = location(of: model) { return found }
        let folder = directory.appending(path: model.id)
        if leaveLinks, Self.isLink(folder) {
            throw Failure("\(model.id) in the model store is a link, and its files are not the ones this build expects. The link was left as it is.")
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The flag exists on Apple platforms. The models can be fetched again.
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = folder
        try excluded.setResourceValues(values)
        #endif
        var done: Int64 = 0
        let total = model.download
        for file in model.files {
            let target = folder.appending(path: file.name)
            if Self.byteCount(target) == file.size {
                done += file.size
                continue
            }
            let url = URL(string: "https://huggingface.co/\(model.repo)/resolve/\(model.revision)/\(file.name)")!
            let base = done
            let downloaded = try await Download.fetch(url) { written in
                progress(Double(base + written) / Double(total))
            }
            defer { try? FileManager.default.removeItem(at: downloaded) }
            guard Self.byteCount(downloaded) == file.size else {
                throw Failure("\(file.name) arrived as \(Self.byteCount(downloaded) ?? 0) bytes, not \(file.size). Try again on a steady connection.")
            }
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: downloaded, to: target)
            done += file.size
        }
        progress(1)
        return folder
    }

    /// The size of the file at `url`. A symlink earlier in the path is
    /// followed, which is how a model directory linked into the store matches
    /// the catalogue. `attributesOfItem` reads that file; it does not replace
    /// a final symlink with the file it names.
    public static func byteCount(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    /// Whether `url` itself is a symlink, including one whose target is gone.
    public static func isLink(_ url: URL) -> Bool {
        var info = stat()
        let linked = url.path.withCString { lstat($0, &info) == 0 }
        // mode_t and the S_IF* macros differ in width between Darwin and Glibc.
        return linked && (Int(info.st_mode) & Int(S_IFMT)) == Int(S_IFLNK)
    }
}

/// One file, with the bytes written so far reported as they arrive.
private final class Download: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    private init(progress: @escaping @Sendable (Int64) -> Void) { self.progress = progress }

    static func fetch(_ url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        let download = Download(progress: progress)
        let session = URLSession(configuration: .default, delegate: download, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            download.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite _: Int64
    ) {
        progress(totalBytesWritten)
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {
        guard let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            continuation?.resume(throwing: ModelStore.Failure("The model server did not return a successful HTTP response."))
            continuation = nil
            return
        }
        // The temporary file is deleted when this returns; keep it.
        let kept = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            continuation?.resume(returning: kept)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
