import Foundation
import XCTest
import SampleBuffer

final class SampleBufferTests: XCTestCase {
    func testPreservesAbsoluteStreamIndicesAfterDrop() {
        let buffer = SampleBuffer()
        buffer.append([1, 2, 3, 4])
        buffer.drop(before: 3)
        buffer.append([5, 6])
        XCTAssertEqual(buffer.count, 6)
        XCTAssertEqual(buffer.read(0, 6), [4, 5, 6])
        XCTAssertEqual(buffer.read(0, 1), [])
        XCTAssertEqual(buffer.read(2, 5), [4, 5])
        buffer.drop(before: 100)
        XCTAssertEqual(buffer.count, 6)
        XCTAssertTrue(buffer.everything().isEmpty)
        XCTAssertEqual(buffer.read(0, 6), [])
    }

    func testLevelIsTheRMSOfTheLastBlock() {
        let buffer = SampleBuffer()
        XCTAssertEqual(buffer.level, 0)
        buffer.append([0.25])
        XCTAssertEqual(buffer.level, 0.25)
        buffer.append([-0.5, 0.5])
        XCTAssertEqual(buffer.level, 0.5)
        buffer.append([])
        XCTAssertEqual(buffer.level, 0)
        XCTAssertEqual(buffer.count, 3)
    }

    func testReadOfAGapOrAnEmptyBufferIsEmpty() {
        let buffer = SampleBuffer()
        XCTAssertEqual(buffer.read(0, 0), [])
        XCTAssertEqual(buffer.read(2, 1), [])
        buffer.append([1, 2])
        XCTAssertEqual(buffer.read(-4, -1), [])
        XCTAssertEqual(buffer.read(8, 10), [])
        buffer.drop(before: -5)
        XCTAssertEqual(buffer.everything(), [1, 2])
        XCTAssertEqual(buffer.count, 2)
    }

    func testListenerRunsAfterTheBlockIsStored() {
        let buffer = SampleBuffer()
        let note = Note()
        buffer.listener = { block in
            note.calls += 1
            note.last = block
            note.held = buffer.everything()
            note.count = buffer.count
            buffer.drop(before: buffer.count)
        }
        buffer.append([1, 2, 3])
        XCTAssertEqual(note.calls, 1)
        XCTAssertEqual(note.last, [1, 2, 3])
        XCTAssertEqual(note.held, [1, 2, 3])
        XCTAssertEqual(note.count, 3)
        XCTAssertEqual(buffer.count, 3)
        XCTAssertTrue(buffer.everything().isEmpty)

        buffer.listener = nil
        buffer.append([4])
        XCTAssertEqual(note.calls, 1)
        XCTAssertEqual(buffer.everything(), [4])
    }

    func testEmptyBlockStillReachesTheListener() {
        let buffer = SampleBuffer()
        let note = Note()
        buffer.listener = { block in
            note.calls += 1
            note.last = block
        }
        buffer.append([])
        XCTAssertEqual(note.calls, 1)
        XCTAssertEqual(note.last, [])
        XCTAssertEqual(buffer.count, 0)
    }

    func testConcurrentAppendReadAndMeter() async {
        let buffer = SampleBuffer()
        let note = Note()
        buffer.listener = { _ in note.lock.withLock { note.calls += 1 } }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { for _ in 0..<1_000 { buffer.append([0.25]) } }
            group.addTask {
                for _ in 0..<1_000 {
                    _ = buffer.level
                    _ = buffer.read(0, buffer.count)
                    _ = buffer.everything()
                }
            }
        }
        XCTAssertEqual(buffer.count, 1_000)
        XCTAssertEqual(buffer.level, 0.25)
        XCTAssertEqual(note.calls, 1_000)
        XCTAssertEqual(buffer.everything().count, 1_000)
    }
}

private final class Note: @unchecked Sendable {
    let lock = NSLock()
    var calls = 0
    var last: [Float] = []
    var held: [Float] = []
    var count = 0
}
