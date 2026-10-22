import Foundation
import ModelStore
import XCTest

final class ModelStoreTests: XCTestCase {
    private struct Fixture: StoredModel {
        var id: String
        var repo = "org/name"
        var revision = "abc"
        var files: [ModelFile]
    }

    private func scratch() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "model-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func testPartialFilesAreNotAModelUntilEverySizeMatches() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = Fixture(id: "test", files: [.init(name: "weights", size: 3), .init(name: "config", size: 2)])
        let store = ModelStore(directory: folder)
        try write(Data([1, 2, 3]), to: folder.appending(path: "weights"))
        XCTAssertNil(store.location(of: model, in: [folder]))
        try write(Data([1]), to: folder.appending(path: "config"))
        XCTAssertNil(store.location(of: model, in: [folder]))
        try write(Data([1, 2]), to: folder.appending(path: "config"))
        XCTAssertEqual(store.location(of: model, in: [folder]), folder)
        XCTAssertEqual(model.download, 5)
    }

    func testTheAppFolderWinsAndAPartialCopyDoesNot() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let install = root.appending(path: "install")
        let checkout = root.appending(path: "checkout")
        let model = Fixture(id: "m", files: [.init(name: "weights", size: 3)])
        let store = ModelStore(directory: install, alsoSearching: [checkout])
        try write(Data([9]), to: install.appending(path: "m/weights"))
        try write(Data([1, 2, 3]), to: checkout.appending(path: "m/weights"))
        XCTAssertEqual(store.location(of: model)?.path, checkout.appending(path: "m").path)
        XCTAssertFalse(store.isDownloaded(Fixture(id: "missing", files: model.files)))
        try write(Data([1, 2, 3]), to: install.appending(path: "m/weights"))
        XCTAssertEqual(store.location(of: model)?.path, install.appending(path: "m").path)
        XCTAssertTrue(store.isDownloaded(model))
    }

    func testANestedRelativePathMatches() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = Fixture(id: "nested", files: [.init(name: "sub/weights", size: 3)])
        try write(Data([1, 2, 3]), to: folder.appending(path: "sub/weights"))
        let store = ModelStore(directory: folder.deletingLastPathComponent())
        XCTAssertEqual(store.location(of: model, in: [folder])?.path, folder.path)
    }

    func testByteCountFollowsADirectoryLinkAndIsNilWhenMissing() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "shared/m/weights")
        try write(Data("gemma-weights".utf8), to: file)
        let link = root.appending(path: "linked")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: file.deletingLastPathComponent().deletingLastPathComponent())
        let through = link.appending(path: "m/weights")
        XCTAssertEqual(ModelStore.byteCount(through), ModelStore.byteCount(file))
        XCTAssertEqual(ModelStore.byteCount(file), Int64("gemma-weights".utf8.count))
        XCTAssertNil(ModelStore.byteCount(root.appending(path: "absent")))
        let broken = root.appending(path: "broken")
        try FileManager.default.createSymbolicLink(at: broken, withDestinationURL: root.appending(path: "gone"))
        XCTAssertNil(ModelStore.byteCount(broken.appending(path: "m/weights")))
    }

    func testIsLinkSeesABrokenLinkAndNotADirectory() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "real")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let link = root.appending(path: "linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
        let broken = root.appending(path: "broken")
        try FileManager.default.createSymbolicLink(at: broken, withDestinationURL: root.appending(path: "gone"))
        XCTAssertTrue(ModelStore.isLink(link))
        XCTAssertTrue(ModelStore.isLink(broken))
        XCTAssertFalse(ModelStore.isLink(directory))
        XCTAssertFalse(ModelStore.isLink(root.appending(path: "absent")))
    }

    func testUsedAndDeleteStayInsideTheAppFolder() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let install = root.appending(path: "install")
        let checkout = root.appending(path: "checkout")
        let model = Fixture(id: "m", files: [.init(name: "weights", size: 3), .init(name: "config", size: 2)])
        let store = ModelStore(directory: install, alsoSearching: [checkout])
        try write(Data([1, 2, 3]), to: checkout.appending(path: "m/weights"))
        try write(Data([1, 2]), to: checkout.appending(path: "m/config"))
        XCTAssertEqual(store.used(model), 0)
        XCTAssertFalse(store.isDeletable(model))
        XCTAssertTrue(store.isDownloaded(model))
        try write(Data([9]), to: install.appending(path: "m/weights"))
        XCTAssertEqual(store.used(model), 1)
        XCTAssertTrue(store.isDeletable(model))
        XCTAssertNil(store.location(of: model, in: [install.appending(path: "m")]))
        try store.delete(model)
        XCTAssertEqual(store.used(model), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: install.appending(path: "m").path))
        XCTAssertEqual(store.location(of: model)?.path, checkout.appending(path: "m").path)
        XCTAssertEqual(ModelStore.byteCount(checkout.appending(path: "m/weights")), 3)
    }

    func testDeleteRemovesALinkAndNotItsTarget() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appending(path: "shared/m")
        try write(Data([1, 2, 3]), to: target.appending(path: "weights"))
        let install = root.appending(path: "install")
        try FileManager.default.createDirectory(at: install, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: install.appending(path: "m"), withDestinationURL: target)
        let store = ModelStore(directory: install)
        try store.delete(Fixture(id: "m", files: [.init(name: "weights", size: 3)]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: install.appending(path: "m").path))
        XCTAssertEqual(ModelStore.byteCount(target.appending(path: "weights")), 3)
    }

    func testDeleteLeavesABrokenLink() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let install = root.appending(path: "install")
        try FileManager.default.createDirectory(at: install, withIntermediateDirectories: true)
        let link = install.appending(path: "m")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appending(path: "gone"))
        let store = ModelStore(directory: install)
        try store.delete(Fixture(id: "m", files: [.init(name: "weights", size: 1)]))
        XCTAssertTrue(ModelStore.isLink(link))
    }

    func testACompleteCopyIsReturnedWithoutWriting() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let install = root.appending(path: "install")
        let checkout = root.appending(path: "checkout")
        let model = Fixture(id: "m", files: [.init(name: "weights", size: 3)])
        try write(Data([1, 2, 3]), to: checkout.appending(path: "m/weights"))
        let store = ModelStore(directory: install, alsoSearching: [checkout], leaveLinks: true)
        let found = try await store.download(model) { _ in
            XCTFail("a complete copy is not fetched again")
        }
        XCTAssertEqual(found.path, checkout.appending(path: "m").path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: install.appending(path: "m").path))
    }

    func testAMatchingLinkIsTheModelForEitherFlag() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appending(path: "shared/m")
        try write(Data([1, 2, 3]), to: target.appending(path: "weights"))
        let model = Fixture(id: "m", files: [.init(name: "weights", size: 3)])
        for leaveLinks in [true, false] {
            let install = root.appending(path: "install-\(leaveLinks)")
            try FileManager.default.createDirectory(at: install, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: install.appending(path: "m"), withDestinationURL: target)
            let store = ModelStore(directory: install, leaveLinks: leaveLinks)
            let found = try await store.download(model) { _ in
                XCTFail("a complete link is not fetched again")
            }
            XCTAssertEqual(found.path, install.appending(path: "m").path)
            XCTAssertTrue(ModelStore.isLink(install.appending(path: "m")))
            XCTAssertEqual(ModelStore.byteCount(target.appending(path: "weights")), 3)
        }
    }

    func testAMismatchedLinkIsLeftUntouched() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appending(path: "shared/m")
        try write(Data([9]), to: target.appending(path: "weights"))
        let install = root.appending(path: "install")
        try FileManager.default.createDirectory(at: install, withIntermediateDirectories: true)
        let link = install.appending(path: "m")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let model = Fixture(id: "m", files: [.init(name: "weights", size: 3)])
        let store = ModelStore(directory: install, leaveLinks: true)
        do {
            _ = try await store.download(model) { _ in }
            XCTFail("the link should have been left")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "m in the model store is a link, and its files are not the ones this build expects. The link was left as it is."
            )
        }
        XCTAssertTrue(ModelStore.isLink(link))
        XCTAssertEqual(try Data(contentsOf: target.appending(path: "weights")), Data([9]))
    }
}
