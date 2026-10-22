import Foundation
import XCTest
import ObjCExceptions

final class ObjCExceptionsTests: XCTestCase {
    #if canImport(ObjectiveC)
    func testReturnsYesWhenTheBlockRuns() {
        var ran = false
        var error: NSError?
        let ok = TCTry({ ran = true }, &error)
        XCTAssertTrue(ok)
        XCTAssertTrue(ran)
        XCTAssertNil(error)
    }

    func testCatchesAnNSException() {
        var error: NSError?
        let ok = TCTry({
            NSException(
                name: NSExceptionName(rawValue: "SpeechCoreTest"),
                reason: "deliberate",
                userInfo: nil
            ).raise()
        }, &error)
        XCTAssertFalse(ok)
        XCTAssertEqual(error?.domain, "SpeechCoreTest")
        XCTAssertEqual(error?.code, 0)
        XCTAssertEqual(error?.localizedDescription, "deliberate")
    }

    func testUsesTheNameWhenTheReasonIsMissing() {
        var error: NSError?
        let ok = TCTry({
            NSException(
                name: NSExceptionName(rawValue: "SpeechCoreTest"),
                reason: nil,
                userInfo: nil
            ).raise()
        }, &error)
        XCTAssertFalse(ok)
        XCTAssertEqual(error?.domain, "SpeechCoreTest")
        XCTAssertEqual(error?.localizedDescription, "SpeechCoreTest")
    }

    func testAllowsANullErrorPointer() {
        let ok = TCTry({
            NSException(
                name: NSExceptionName(rawValue: "SpeechCoreTest"),
                reason: "deliberate",
                userInfo: nil
            ).raise()
        }, nil)
        XCTAssertFalse(ok)
    }
    #else
    func testRequiresApplePlatforms() throws {
        throw XCTSkip("NSException exists only on Apple platforms.")
    }
    #endif
}
