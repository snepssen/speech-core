import Foundation
import XCTest
import SileroVAD

/// The bundled graph is not Silero. `make_fixture.py` builds it:
/// mean of the 64-sample context plus the frame, plus `stateBump` times
/// `state[0,0,0]`, plus `(sr - 16000)`. Each call adds one to that state
/// element. A dropped round-trip, a wrong context, or a sample rate other
/// than 16 kHz moves the score off the values these tests expect.
final class SileroVADTests: XCTestCase {
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    private let stateBump: Float = 0.001

    func testStartsSilent() throws {
        let vad = try make()
        XCTAssertEqual(SileroVAD.frame, 512)
        XCTAssertFalse(vad.speaking)
        XCTAssertEqual(vad.probability, 0)
        XCTAssertEqual(vad.lastSpeech, -1e9)
        XCTAssertEqual(vad.silence(at: 0), 1e9)
        XCTAssertEqual(vad.silence(at: 4), 1e9 + 4)
    }

    func testSilenceDoesNotBecomeSpeech() throws {
        let vad = try make()
        let silence = [Float](repeating: 0, count: SileroVAD.frame)
        for step in 0..<100 {
            XCTAssertFalse(try vad.push(silence[...], at: Double(step + 1) * 0.032))
            XCTAssertEqual(vad.probability, Float(step) * stateBump)
        }
        XCTAssertLessThan(vad.lastSpeech, 0)
        XCTAssertFalse(vad.speaking)
    }

    func testContextIsTheLastSixtyFourSamples() throws {
        let vad = try make()
        let width = Float(64 + SileroVAD.frame)
        let carried = Float(64) / width
        var tail = [Float](repeating: 0, count: SileroVAD.frame - 64)
        tail.append(contentsOf: [Float](repeating: 1, count: 64))
        let zeros = [Float](repeating: 0, count: SileroVAD.frame)

        XCTAssertFalse(try vad.push(tail[...], at: 0.032))
        XCTAssertEqual(vad.probability, carried)
        XCTAssertFalse(try vad.push(zeros[...], at: 0.064))
        XCTAssertEqual(vad.probability, carried + stateBump)
        XCTAssertFalse(try vad.push(zeros[...], at: 0.096))
        XCTAssertEqual(vad.probability, Float(2) * stateBump)
    }

    func testHysteresisHoldsBetweenTheThresholds() throws {
        let vad = try make()
        let quiet = samples(0.45)
        XCTAssertFalse(try vad.push(quiet[...], at: 0.032))
        XCTAssertFalse(vad.speaking)
        XCTAssertEqual(vad.probability, score(context: 0, frame: 0.45, step: 0), accuracy: 1e-5)
        XCTAssertGreaterThanOrEqual(vad.probability, 0.35)
        XCTAssertLessThan(vad.probability, 0.5)

        let loud = samples(1)
        XCTAssertTrue(try vad.push(loud[...], at: 0.064))
        XCTAssertTrue(vad.speaking)
        XCTAssertEqual(vad.lastSpeech, 0.064)
        XCTAssertEqual(vad.silence(at: 10), 0)

        let held = samples(0.325)
        XCTAssertTrue(try vad.push(held[...], at: 0.096))
        XCTAssertTrue(vad.speaking)
        XCTAssertEqual(vad.lastSpeech, 0.096)
        XCTAssertEqual(vad.probability, score(context: 1, frame: 0.325, step: 2), accuracy: 1e-5)
        XCTAssertGreaterThanOrEqual(vad.probability, 0.35)
        XCTAssertLessThan(vad.probability, 0.5)

        let dropped = samples(0)
        XCTAssertFalse(try vad.push(dropped[...], at: 0.128))
        XCTAssertFalse(vad.speaking)
        XCTAssertLessThan(vad.probability, 0.35)
        XCTAssertEqual(vad.lastSpeech, 0.096)
        XCTAssertEqual(vad.silence(at: 2.096), 2, accuracy: 1e-9)
    }

    func testResetClearsContextStateAndSpeech() throws {
        let vad = try make()
        XCTAssertTrue(try vad.push(samples(1)[...], at: 1))
        XCTAssertTrue(vad.speaking)
        vad.reset()
        XCTAssertFalse(vad.speaking)
        XCTAssertEqual(vad.probability, 0)
        XCTAssertEqual(vad.lastSpeech, -1e9)
        XCTAssertFalse(try vad.push(samples(0)[...], at: 2))
        XCTAssertEqual(vad.probability, 0)
    }

    func testThresholdsAreInclusive() throws {
        let width = Float(64 + SileroVAD.frame)
        let on = Float(SileroVAD.frame) / width
        let off = Float(64) / width + stateBump
        let vad = try make(on: on, off: off)
        XCTAssertTrue(try vad.push(samples(1)[...], at: 0.032))
        XCTAssertEqual(vad.probability, on)
        XCTAssertTrue(try vad.push(samples(0)[...], at: 0.064))
        XCTAssertEqual(vad.probability, off)
        XCTAssertTrue(vad.speaking)
    }

    func testAStricterOnThresholdStaysSilent() throws {
        let vad = try make(on: 0.95, off: 0.35)
        XCTAssertFalse(try vad.push(samples(1)[...], at: 0.032))
        XCTAssertFalse(vad.speaking)
        XCTAssertLessThan(vad.lastSpeech, 0)
    }

    func testAMissingModelThrows() {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "speech-core-vad-\(UUID().uuidString).onnx")
        XCTAssertThrowsError(try SileroVAD(model: missing))
    }

    private func make(on: Float = 0.5, off: Float = 0.35) throws -> SileroVAD {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/mean_window.onnx", withExtension: nil))
        return try SileroVAD(model: url, on: on, off: off)
    }

    private func samples(_ value: Float) -> [Float] {
        [Float](repeating: value, count: SileroVAD.frame)
    }

    private func score(context: Float, frame: Float, step: Int) -> Float {
        let width = Float(64 + SileroVAD.frame)
        let mean = (Float(64) * context + Float(SileroVAD.frame) * frame) / width
        return mean + Float(step) * stateBump
    }
    #else
    func testRequiresApplePlatforms() throws {
        throw XCTSkip("ONNX Runtime is linked on Apple platforms.")
    }
    #endif
}
