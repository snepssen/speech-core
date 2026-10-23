import Foundation
import XCTest
@testable import MLXLMCommon
import PromptCache

final class PromptCacheTests: XCTestCase {
    func testRebuildsWhenRewindIsUnavailable() throws {
        let old = FakeCache()
        var cache = try PromptCache { [old.offset == 0 ? old : FakeCache()] }
        old.offset = 4
        cache.settle([1, 2, 3, 4])
        old.trimmable = false
        XCTAssertEqual(try cache.prepare(for: [1, 2, 9]), [1, 2, 9])
        XCTAssertEqual(cache.kv[0].offset, 0)
        XCTAssertFalse((cache.kv[0] as? FakeCache) === old)
    }

    func testNeverSkipsUncachedLastToken() throws {
        let backing = FakeCache()
        var cache = try PromptCache { [backing] }
        backing.offset = 2
        cache.settle([1, 2, 3])
        XCTAssertEqual(try cache.prepare(for: [1, 2, 3, 4]), [3, 4])
    }

    func testEmptyPromptIsAnError() throws {
        var cache = try PromptCache { [FakeCache()] }
        XCTAssertThrowsError(try cache.prepare(for: [])) { XCTAssertTrue($0 is PromptCache.EmptyPrompt) }
    }

    func testSettleTrimsWhatWasGeneratedPastTheHeldTokens() throws {
        let backing = FakeCache()
        var cache = try PromptCache { [backing] }
        backing.offset = 6
        cache.settle([1, 2, 3, 4])
        XCTAssertEqual(backing.offset, 4)
        XCTAssertEqual(cache.tokens, [1, 2, 3, 4])
    }

    func testOnlySlidingWindowCachesKeepASnapshot() throws {
        let plain = try PromptCache { [FakeCache()] }
        XCTAssertFalse(plain.cannotRewind)
        let sliding = try PromptCache { [FakeSlidingCache()] }
        XCTAssertTrue(sliding.cannotRewind)
    }

    func testFailedTrimRestartsFromTheSnapshot() throws {
        var made = 0
        var cache = try PromptCache {
            made += 1
            return [FakeSlidingCache()]
        }
        let live = cache.kv[0] as! FakeSlidingCache
        live.offset = 3
        cache.settle([1, 2, 3])
        cache.keep([1, 2, 3])
        live.offset = 5
        cache.settle([1, 2, 3, 4, 5])
        // The ring has wrapped: [1, 2, 3, 7] can't be had by trimming.
        XCTAssertEqual(try cache.prepare(for: [1, 2, 3, 7]), [7])
        XCTAssertEqual(cache.kv[0].offset, 3)
        XCTAssertFalse((cache.kv[0] as? FakeSlidingCache) === live)
        XCTAssertEqual(made, 1)
    }

    func testSnapshotIsUnusedWhenThePromptPartsBeforeIt() throws {
        var made = 0
        var cache = try PromptCache {
            made += 1
            return [FakeSlidingCache()]
        }
        let live = cache.kv[0] as! FakeSlidingCache
        live.offset = 3
        cache.settle([1, 2, 3])
        cache.keep([1, 2, 3])
        live.offset = 5
        cache.settle([1, 2, 3, 4, 5])
        XCTAssertEqual(try cache.prepare(for: [1, 8, 9]), [1, 8, 9])
        XCTAssertEqual(cache.kv[0].offset, 0)
        XCTAssertEqual(made, 2)
    }

    func testKeepIgnoresACacheThatHoldsSomethingElse() throws {
        var made = 0
        var cache = try PromptCache {
            made += 1
            return [FakeSlidingCache()]
        }
        let live = cache.kv[0] as! FakeSlidingCache
        live.offset = 5
        cache.settle([1, 2, 3, 4, 5])
        cache.keep([1, 2, 3])  // the cache holds five, not three
        XCTAssertEqual(try cache.prepare(for: [1, 2, 3, 7]), [1, 2, 3, 7])
        XCTAssertEqual(made, 2)
    }
}

private final class FakeCache: BaseKVCache {
    var trimmable = true
    override var isTrimmable: Bool { trimmable }
    override func trim(_ n: Int) -> Int {
        let trimmed = min(offset, max(0, n))
        offset -= trimmed
        return trimmed
    }
    override func copy() -> any KVCache {
        let new = FakeCache()
        new.offset = offset
        new.trimmable = trimmable
        return new
    }
}

/// A sliding window whose ring has wrapped: it trims nothing.
private final class FakeSlidingCache: RotatingKVCache {
    init() { super.init(maxSize: 4) }
    override var isTrimmable: Bool { false }
    override func trim(_ n: Int) -> Int { 0 }
    override func copy() -> any KVCache {
        let new = FakeSlidingCache()
        new.offset = offset
        return new
    }
}
