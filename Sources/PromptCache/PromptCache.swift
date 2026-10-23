import Foundation
import MLXLMCommon

/// An attention cache and the tokens it holds, reused across calls that share
/// a prefix.
///
/// `prepare(for:)` trims the cache back to what the next prompt shares with
/// what is held and returns the part still to be read. `settle(_:)` records
/// what the cache holds after the call. A sliding-window cache (Gemma) cannot
/// be trimmed once its ring wraps; `keep(_:)` stores a copy at a point the next
/// prompt will share, and a failed trim restarts from that copy instead of
/// from nothing.
public struct PromptCache {
    public private(set) var kv: [KVCache]
    private let freshCache: () throws -> [KVCache]
    public private(set) var tokens: [Int] = []

    /// The prompt was empty. A call must read at least one token.
    public struct EmptyPrompt: LocalizedError {
        public var errorDescription: String? { "The model produced an empty prompt." }
    }

    public init(_ model: any LanguageModel) throws {
        try self.init { try model.newCache(parameters: nil) }
    }

    public init(makeCache: @escaping () throws -> [KVCache]) throws {
        freshCache = makeCache
        kv = try makeCache()
    }

    public mutating func reset() throws {
        kv = try freshCache()
        tokens = []
        snapshot = nil
    }

    /// A copy of the cache at a point the next prompt will share, for a
    /// cache that can't rewind to it.
    private var snapshot: (tokens: [Int], kv: [KVCache])?

    /// Sliding-window attention (Gemma): once past its window the cache can't
    /// be trimmed back, so a changed tail can't simply be cut off.
    public var cannotRewind: Bool { kv.contains { $0 is RotatingKVCache } }

    /// Remember the cache as it is, holding exactly `held`.
    public mutating func keep(_ held: [Int]) {
        guard cannotRewind, kv.first?.offset == held.count else { return }
        snapshot = (held, kv.map { $0.copy() })
    }

    /// Trim back to what `prompt` shares with what is held; returns the part to read.
    public mutating func prepare(for prompt: [Int]) throws -> [Int] {
        guard !prompt.isEmpty else { throw EmptyPrompt() }
        var keep = zip(tokens, prompt).prefix { $0 == $1 }.count
        let offset = kv.first?.offset ?? 0
        keep = min(keep, prompt.count - 1, offset)  // always read at least one token
        let trim = offset - keep
        if trim > 0 && (!canTrimPromptCache(kv) || trimPromptCache(kv, numTokens: trim) != trim) {
            // Sliding attention can no longer rewind once its ring wraps. A
            // failed trim must rebuild, not feed a suffix behind stale tokens:
            // from the snapshot when the prompt begins with it, else from nothing.
            if let snapshot, snapshot.tokens.count < prompt.count, prompt.starts(with: snapshot.tokens) {
                kv = snapshot.kv.map { $0.copy() }
                tokens = snapshot.tokens
                keep = snapshot.tokens.count
            } else {
                try reset()
                keep = 0
            }
        }
        return Array(prompt[keep...])
    }

    /// After a call: the cache holds `held`, and nothing past it.
    public mutating func settle(_ held: [Int]) {
        let extra = (kv.first?.offset ?? 0) - held.count
        if extra > 0 { _ = trimPromptCache(kv, numTokens: extra) }
        tokens = Array(held.prefix(kv.first?.offset ?? 0))
    }
}
