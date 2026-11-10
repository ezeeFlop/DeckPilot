import XCTest
@testable import StreamDockKit

final class DeckLayoutTests: XCTestCase {
    let layout = DeckLayout.streamDock293SV3

    func testGridIsSixColumnsByThreeRows() {
        XCTAssertEqual(layout.columns, 6)
        XCTAssertEqual(layout.rows, 3)
        XCTAssertEqual(layout.slots.count, 18)
    }

    func testTopRowReadsThirteenTenSevenFourOne() {
        XCTAssertEqual((0..<5).map { layout.slot(row: 0, column: $0) }, [13, 10, 7, 4, 1])
    }

    func testSlotsRunDownEachColumn() {
        XCTAssertEqual((0..<3).map { layout.slot(row: $0, column: 0) }, [13, 14, 15])
        XCTAssertEqual((0..<3).map { layout.slot(row: $0, column: 4) }, [1, 2, 3])
    }

    func testLastColumnIsTheDisplayOnlyStrip() {
        XCTAssertEqual((0..<3).map { layout.slot(row: $0, column: 5) }, [16, 17, 18])
        XCTAssertFalse(layout.isPressable(slot: 16))
        XCTAssertTrue(layout.isPressable(slot: 15))
    }

    func testPositionIsTheInverseOfSlot() {
        for row in 0..<3 {
            for column in 0..<6 {
                let slot = layout.slot(row: row, column: column)
                XCTAssertEqual(layout.position(ofSlot: slot), DeckLayout.Position(row: row, column: column))
            }
        }
    }

    func testReadingOrderListsSlotsRowByRow() {
        XCTAssertEqual(Array(layout.slotsInReadingOrder.prefix(7)), [13, 10, 7, 4, 1, 16, 14])
    }

    func testOnlyTheDisplayStripHidesItsLeadingEdge() {
        XCTAssertEqual(layout.leadingInset(ofSlot: 1), 0)
        XCTAssertEqual(layout.leadingInset(ofSlot: 15), 0)
        XCTAssertEqual(layout.leadingInset(ofSlot: 16), 14)
        XCTAssertEqual(layout.leadingInset(ofSlot: 18), 14)
    }

    func testStripContentIsCentredInItsGlassWindow() {
        // La vitre montre les 82 pixels de droite de l'image, puis 7 pixels noirs au-delà de son bord droit.
        // Pour paraître centré dans la vitre, le contenu laisse donc 7 pixels de plus à gauche.
        XCTAssertEqual(layout.contentLeadingInset(ofSlot: 16), 21)
        XCTAssertEqual(layout.trailingGlass(ofSlot: 16), 7)
        XCTAssertEqual(layout.contentLeadingInset(ofSlot: 4), 0)
        XCTAssertEqual(layout.trailingGlass(ofSlot: 4), 0)
    }
}
