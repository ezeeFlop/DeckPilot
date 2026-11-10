import XCTest
@testable import DeckCore

final class ModelTests: XCTestCase {
    func testColorRoundTripsThroughHex() {
        XCTAssertEqual(DeckColor(hex: "#FF8000")?.hex, "#FF8000")
        XCTAssertEqual(DeckColor(hex: "1a2B3c")?.hex, "#1A2B3C")
        XCTAssertNil(DeckColor(hex: "zzz"))
    }

    func testConfigurationSurvivesEncodingAndDecoding() throws {
        var page = Page(name: "Travail")
        var key = KeyConfig()
        key.title = "Mail"
        key.icon = .symbol("envelope.fill")
        key.animation = .pulse
        key.action = .hotkey(keyCode: 12, modifiers: 0x100000, display: "⌘Q")
        page.keys[13] = key
        page.keys[1] = KeyConfig(title: "Site", icon: .emoji("🌍"), action: .openURL("https://example.com"))
        page.keys[2] = KeyConfig(title: "Suivant", action: .goToPage(UUID()))
        let config = DeckConfiguration(brightness: 60, pages: [page, Page(name: "Jeux")], sleepAfterMinutes: 15)

        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(DeckConfiguration.self, from: data), config)
    }

    func testEmptySlotReadsAsABlankKey() {
        let page = Page(name: "Vide")
        XCTAssertEqual(page.key(at: 7), KeyConfig())
        XCTAssertTrue(page.key(at: 7).isBlank)
    }

    func testAKeyWithATitleOrAnActionIsNotBlank() {
        XCTAssertFalse(KeyConfig(title: "A").isBlank)
        XCTAssertFalse(KeyConfig(action: .media(.mute)).isBlank)
    }

    func testNextPageWrapsAroundToTheFirst() {
        let config = DeckConfiguration(pages: [Page(name: "A"), Page(name: "B"), Page(name: "C")])
        XCTAssertEqual(config.pageIndex(after: 0), 1)
        XCTAssertEqual(config.pageIndex(after: 2), 0)
        XCTAssertEqual(config.pageIndex(before: 0), 2)
    }

    func testPageIndexLooksUpByIdentifier() {
        let b = Page(name: "B")
        let config = DeckConfiguration(pages: [Page(name: "A"), b])
        XCTAssertEqual(config.pageIndex(withID: b.id), 1)
        XCTAssertNil(config.pageIndex(withID: UUID()))
    }

    func testStarterConfigurationHasOnePageWithSomeKeys() {
        let starter = DeckConfiguration.starter
        XCTAssertEqual(starter.pages.count, 1)
        XCTAssertFalse(starter.pages[0].keys.isEmpty)
        XCTAssertTrue(starter.pages[0].keys.keys.allSatisfy { (1...18).contains($0) })
    }

    func testSwappingTwoSlotsExchangesTheirKeys() {
        var page = Page(name: "P")
        page.keys[1] = KeyConfig(title: "Un")
        page.swapKeys(1, 5)
        XCTAssertEqual(page.key(at: 5).title, "Un")
        XCTAssertNil(page.keys[1])
    }
}
