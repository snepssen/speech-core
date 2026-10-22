import Foundation

/// Samples the microphone has delivered, 16 kHz mono, shared between the audio
/// thread that appends and the loop that reads.
///
/// `count` counts from the start of the stream. Dropping samples moves the
/// window forward and leaves `count` where it is, so a later read still uses
/// stream indices. `everything` is what the window still holds. `listener`,
/// when one is set, is called with each block after it is stored, and not
/// while this buffer's lock is held.
public final class SampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var base = 0  // stream index of samples[0]
    private var rms: Float = 0
    public var level: Float { lock.withLock { rms } }

    public var count: Int { lock.withLock { base + samples.count } }

    public init() {}

    /// Handed each block as it arrives, on the appending thread: keep it quick.
    public var listener: (@Sendable ([Float]) -> Void)? {
        get { lock.withLock { heard } }
        set { lock.withLock { heard = newValue } }
    }
    private var heard: (@Sendable ([Float]) -> Void)?

    public func append(_ block: [Float]) {
        let rms = block.isEmpty ? 0 : (block.reduce(0) { $0 + $1 * $1 } / Float(block.count)).squareRoot()
        let listener = lock.withLock {
            samples += block
            self.rms = rms
            return heard
        }
        listener?(block)
    }

    /// Stream samples from `start` to `end`, whatever of them is still held.
    public func read(_ start: Int, _ end: Int) -> [Float] {
        lock.withLock {
            let lo = max(start, base) - base
            let hi = min(end, base + samples.count) - base
            return lo < hi ? Array(samples[lo..<hi]) : []
        }
    }

    /// Let go of everything before stream index `index`.
    public func drop(before index: Int) {
        lock.withLock {
            let n = min(max(0, index - base), samples.count)
            samples.removeFirst(n)
            base += n
        }
    }

    public func everything() -> [Float] { lock.withLock { samples } }
}
