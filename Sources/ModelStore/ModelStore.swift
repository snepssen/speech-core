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
    /// A Release store. It does not download, move, or delete.
    public let readOnly: Bool

    /// The app group a sandboxed Release build uses to share models.
    /// Both apps add `group.com.snepssen.models` before this can open.
    public static let sharedAppGroup = "group.com.snepssen.models"

    public init(directory: URL, alsoSearching: [URL] = [], leaveLinks: Bool = false) {
        self.directory = directory
        self.alsoSearching = alsoSearching
        self.leaveLinks = leaveLinks
        self.readOnly = false
    }

    /// Release builds read only `root/<id>`. Nothing is downloaded, moved, or
    /// deleted. The app chooses this with its own `#if DEBUG`: a package
    /// cannot see the app's DEBUG flag. Debug builds and command-line checks
    /// keep the initializer above, including a checkout path.
    public static func release(at root: URL) -> ModelStore {
        ModelStore(reading: root)
    }

    private init(reading root: URL) {
        directory = root
        alsoSearching = []
        leaveLinks = true
        readOnly = true
    }

    /// The folder Release builds share.
    ///
    /// An unsandboxed Mac app gets `~/Library/Application Support/snepssen/models`.
    /// The name is the workshop's, not either app's, and `models` is the same
    /// directory name a checkout already uses. Linux uses
    /// `$XDG_DATA_HOME/snepssen/models`, or `~/.local/share/snepssen/models`
    /// when that variable is unset. A sandboxed app (every iOS app, and a Mac
    /// app with `APP_SANDBOX_CONTAINER_ID`) gets
    /// `<group container>/models` for `appGroup`, or `sharedAppGroup` when
    /// the group is omitted. This does not create the folder.
    public static func sharedRoot(
        appGroup: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> URL {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        let sandboxed = appleSandboxed(environment)
        if sandboxed || appGroup != nil {
            let group = appGroup ?? sharedAppGroup
            guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
                throw Failure(missingGroup(group, home: home))
            }
            return container.appending(path: "models")
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "snepssen/models")
        #else
        if let appGroup {
            let root = linuxSharedRoot(environment: environment, home: home)
            throw Failure("\(appGroup) is an Apple app group. On this system the shared folder is \(root.path).")
        }
        return linuxSharedRoot(environment: environment, home: home)
        #endif
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

    /// The model directory under `directory`, when every pinned file is there
    /// at its size. A missing or wrong-sized file throws, and the message
    /// names that file's path. `alsoSearching` is not consulted.
    public func require(_ model: some StoredModel) throws -> URL {
        let folder = directory.appending(path: model.id)
        let wrong = model.files.filter { Self.byteCount(folder.appending(path: $0.name)) != $0.size }
        guard wrong.isEmpty else { throw Failure(missing(model, folder: folder, wrong: wrong)) }
        return folder
    }

    /// Downloaded into this app's storage, so the app can delete it. A copy
    /// found only under `alsoSearching` belongs to whoever put it there.
    /// A Release store never offers deletion.
    public func isDeletable(_ model: some StoredModel) -> Bool { !readOnly && used(model) > 0 }

    /// Bytes of this model under `directory`. Missing files contribute nothing.
    public func used(_ model: some StoredModel) -> Int64 {
        let folder = directory.appending(path: model.id)
        return model.files.compactMap { Self.byteCount(folder.appending(path: $0.name)) }.reduce(0, +)
    }

    /// Remove this app's copy. A missing folder, or a symlink whose target is
    /// gone, is left as it is. `alsoSearching` is never removed.
    public func delete(_ model: some StoredModel) throws {
        let folder = directory.appending(path: model.id)
        if readOnly {
            throw Failure("\(folder.path) was left as it is.")
        }
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
        if readOnly { return try require(model) }
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

    private func missing(_ model: some StoredModel, folder: URL, wrong: [ModelFile]) -> String {
        let parts = wrong.map { file -> String in
            let url = folder.appending(path: file.name)
            let found = Self.byteCount(url).map { "\($0) bytes" } ?? "nothing"
            return "\(url.path) (\(file.size) bytes, found \(found))"
        }
        return "\(model.id) is not at \(folder.path). Expected \(parts.joined(separator: "; "))."
    }

    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    private static func appleSandboxed(_ environment: [String: String]) -> Bool {
        #if os(macOS)
        environment["APP_SANDBOX_CONTAINER_ID"] != nil
        #else
        true
        #endif
    }

    private static func missingGroup(_ group: String, home: URL) -> String {
        #if os(macOS)
        let expected = home.appending(path: "Library/Group Containers/\(group)/models").path
        return "Expected \(expected). Add \(group) to the entitlements. A sandboxed app's own Application Support is private, so it is not ~/Library/Application Support/snepssen/models."
        #else
        _ = home
        return "Expected the app group \(group) container's models directory. Add \(group) to the entitlements. A sandboxed app's Application Support is private to it."
        #endif
    }
    #else
    private static func linuxSharedRoot(environment: [String: String], home: URL) -> URL {
        let base: URL
        if let xdg = environment["XDG_DATA_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            base = home.appending(path: ".local/share")
        }
        return base.appending(path: "snepssen/models")
    }
    #endif
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
