import XCTest
@testable import DeckCore

final class PressTrackerTests: XCTestCase {
    func testAPressedKeyIsHeldUntilReleased() {
        var tracker = PressTracker(holdLimit: 0.3)
        tracker.press(4, at: 10)
        XCTAssertEqual(tracker.held(at: 10.1), [4])
        tracker.release(4)
        XCTAssertEqual(tracker.held(at: 10.15), [])
    }

    func testAPressWithoutReleaseExpiresAfterTheHoldLimit() {
        var tracker = PressTracker(holdLimit: 0.3)
        tracker.press(4, at: 10)
        XCTAssertEqual(tracker.held(at: 10.29), [4])
        XCTAssertEqual(tracker.held(at: 10.31), [])
    }

    func testKeysAreTrackedIndependently() {
        var tracker = PressTracker(holdLimit: 0.3)
        tracker.press(1, at: 0)
        tracker.press(2, at: 0.2)
        XCTAssertEqual(tracker.held(at: 0.35), [2])
    }
}
