import XCTest
@testable import StreamDockKit

final class DeckProtocolTests: XCTestCase {
    private func ascii(_ s: String) -> [UInt8] { Array(s.utf8) }
    private var prefix: [UInt8] { ascii("CRT") + [0, 0] }

    func testWakeIsPrefixThenDIS() {
        XCTAssertEqual(DeckCommand.wake.payload, prefix + ascii("DIS"))
    }

    func testBrightnessCarriesPercentAfterTwoZeroBytes() {
        XCTAssertEqual(DeckCommand.brightness(42).payload, prefix + ascii("LIG") + [0, 0, 42])
    }

    func testBrightnessIsClampedToHundred() {
        XCTAssertEqual(DeckCommand.brightness(250).payload.last, 100)
        XCTAssertEqual(DeckCommand.brightness(-5).payload.last, 0)
    }

    func testImageHeaderCarriesBigEndianSizeThenSlot() {
        XCTAssertEqual(
            DeckCommand.imageHeader(byteCount: 0x0001_02A3, slot: 7).payload,
            prefix + ascii("BAT") + [0x00, 0x01, 0x02, 0xA3, 7])
    }

    func testRefreshClearSleepHeartbeatDisconnect() {
        XCTAssertEqual(DeckCommand.refresh.payload, prefix + ascii("STP"))
        XCTAssertEqual(DeckCommand.clear(slot: 3).payload, prefix + ascii("CLE") + [0, 0, 0, 3])
        XCTAssertEqual(DeckCommand.clearAll.payload, prefix + ascii("CLE") + [0, 0, 0, 0xFF])
        XCTAssertEqual(DeckCommand.sleep.payload, prefix + ascii("HAN"))
        XCTAssertEqual(DeckCommand.heartbeat.payload, prefix + ascii("CONNECT"))
        XCTAssertEqual(DeckCommand.disconnect.payload, prefix + ascii("CLE") + [0, 0] + ascii("DC"))
    }

    func testReportsPadShortPayloadWithZeros() {
        let reports = DeckReports.split(DeckCommand.wake.payload, reportSize: 16)
        XCTAssertEqual(reports, [prefix + ascii("DIS") + [UInt8](repeating: 0, count: 8)])
    }

    func testReportsSplitLongPayloadIntoFullSizeChunks() {
        let payload = (0..<40).map { UInt8($0) }
        let reports = DeckReports.split(payload, reportSize: 16)
        XCTAssertEqual(reports.count, 3)
        XCTAssertEqual(reports[0], Array(payload[0..<16]))
        XCTAssertEqual(reports[2], Array(payload[32..<40]) + [UInt8](repeating: 0, count: 8))
        XCTAssertTrue(reports.allSatisfy { $0.count == 16 })
    }

    func testImageUploadIsHeaderThenDataChunks() {
        let jpeg = [UInt8](repeating: 0xAB, count: 20)
        let reports = DeckReports.imageUpload(jpeg: jpeg, slot: 2, reportSize: 16)
        XCTAssertEqual(reports.count, 3)
        XCTAssertEqual(Array(reports[0].prefix(13)), prefix + ascii("BAT") + [0, 0, 0, 20, 2])
        XCTAssertEqual(reports[1], [UInt8](repeating: 0xAB, count: 16))
        XCTAssertEqual(reports[2], [UInt8](repeating: 0xAB, count: 4) + [UInt8](repeating: 0, count: 12))
    }

    private func inputReport(key: UInt8, state: UInt8) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: 512)
        r.replaceSubrange(0..<3, with: ascii("ACK"))
        r.replaceSubrange(5..<7, with: ascii("OK"))
        r[9] = key
        r[10] = state
        return r
    }

    func testParsesKeyPressAndRelease() {
        XCTAssertEqual(DeckInput(report: inputReport(key: 4, state: 1)), DeckInput(key: 4, pressed: true))
        XCTAssertEqual(DeckInput(report: inputReport(key: 4, state: 0)), DeckInput(key: 4, pressed: false))
    }

    func testIgnoresWriteAcknowledgement() {
        XCTAssertNil(DeckInput(report: inputReport(key: 0xFF, state: 0)))
    }

    func testIgnoresReportsWithoutAckSignature() {
        var r = inputReport(key: 4, state: 1)
        r[0] = 0
        XCTAssertNil(DeckInput(report: r))
        XCTAssertNil(DeckInput(report: [0x41, 0x43]))
    }
}
