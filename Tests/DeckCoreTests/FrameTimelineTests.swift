import XCTest
@testable import DeckCore

final class FrameTimelineTests: XCTestCase {
    func testPicksTheFrameWhoseIntervalContainsTheTime() {
        let timeline = FrameTimeline(delays: [0.1, 0.2, 0.1])
        XCTAssertEqual(timeline.index(at: 0.05), 0)
        XCTAssertEqual(timeline.index(at: 0.15), 1)
        XCTAssertEqual(timeline.index(at: 0.35), 2)
    }

    func testLoopsBackToTheFirstFrameAfterTheLastOne() {
        let timeline = FrameTimeline(delays: [0.1, 0.2, 0.1])
        XCTAssertEqual(timeline.duration, 0.4, accuracy: 1e-9)
        XCTAssertEqual(timeline.index(at: 0.45), 0)
        XCTAssertEqual(timeline.index(at: 0.95), 1)
    }

    func testASingleFrameIsNotAnimated() {
        let timeline = FrameTimeline(delays: [0.1])
        XCTAssertFalse(timeline.isAnimated)
        XCTAssertEqual(timeline.index(at: 12), 0)
    }

    func testVeryShortDelaysAreRaisedToAPlayableMinimum() {
        // Beaucoup de GIF déclarent un délai nul ; les navigateurs les jouent à environ 10 images par seconde.
        let timeline = FrameTimeline(delays: [0, 0.01, 0.5])
        XCTAssertEqual(timeline.duration, 0.1 + 0.1 + 0.5, accuracy: 1e-9)
    }
}
