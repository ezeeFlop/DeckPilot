import XCTest
@testable import DeckCore

final class KeyStateTests: XCTestCase {
    private var micKey: KeyConfig {
        var key = KeyConfig(title: "Micro", background: DeckColor(hex: "#14532D")!, icon: .symbol("mic.fill"),
                            action: .shell(command: "couper"))
        var second = KeyAlternate(follows: .press, from: key)
        second.title = "Coupé"
        second.icon = .symbol("mic.slash.fill")
        second.background = DeckColor(hex: "#7F1D1D")!
        second.action = .shell(command: "rétablir")
        key.alternate = second
        return key
    }

    func testASecondStateStartsAsACopyOfTheKey() {
        let key = KeyConfig(title: "Micro", titleSize: 18, icon: .emoji("🎙"), animation: .pulse, action: .media(.mute))
        let second = KeyAlternate(follows: .muted, from: key)
        var twoStates = key
        twoStates.alternate = second
        XCTAssertEqual(twoStates.resolved(active: true).title, "Micro")
        XCTAssertEqual(twoStates.resolved(active: true).titleSize, 18)
        XCTAssertEqual(twoStates.resolved(active: true).icon, .emoji("🎙"))
        XCTAssertEqual(twoStates.resolved(active: true).animation, .pulse)
        XCTAssertEqual(twoStates.resolved(active: true).action, .media(.mute))
    }

    func testTheFirstStateShowsTheKeyItself() {
        let resolved = micKey.resolved(active: false)
        XCTAssertEqual(resolved.title, "Micro")
        XCTAssertEqual(resolved.icon, .symbol("mic.fill"))
        XCTAssertEqual(resolved.action, .shell(command: "couper"))
    }

    func testTheSecondStateShowsItsOwnLookAndAction() {
        let resolved = micKey.resolved(active: true)
        XCTAssertEqual(resolved.title, "Coupé")
        XCTAssertEqual(resolved.icon, .symbol("mic.slash.fill"))
        XCTAssertEqual(resolved.background, DeckColor(hex: "#7F1D1D")!)
        XCTAssertEqual(resolved.action, .shell(command: "rétablir"))
    }

    func testAKeyWithoutASecondStateLooksTheSameEitherWay() {
        let key = KeyConfig(title: "Simple", action: .nextPage)
        XCTAssertEqual(key.resolved(active: true), key)
    }

    func testLiveContentIsSharedByBothStates() {
        var key = micKey
        key.live = LiveData(source: .system(.cpu))
        XCTAssertEqual(key.resolved(active: true).live, key.live)
    }

    func testEditingTheSecondStateLeavesTheFirstUntouched() {
        var key = micKey
        var edited = key.resolved(active: true)
        edited.title = "Muet"
        edited.titleColor = DeckColor(hex: "#FFFF00")!
        edited.action = .none
        key.updateAlternate(from: edited)
        XCTAssertEqual(key.title, "Micro")
        XCTAssertEqual(key.action, .shell(command: "couper"))
        XCTAssertEqual(key.resolved(active: true).title, "Muet")
        XCTAssertEqual(key.resolved(active: true).titleColor, DeckColor(hex: "#FFFF00")!)
        XCTAssertEqual(key.resolved(active: true).action, KeyAction.none)
        XCTAssertEqual(key.alternate?.follows, .press)
    }

    func testAKeyWithTwoStatesSurvivesEncodingAndDecoding() throws {
        var key = micKey
        key.alternate?.follows = .appRunning(path: "/Applications/Safari.app")
        let data = try JSONEncoder().encode(key)
        XCTAssertEqual(try JSONDecoder().decode(KeyConfig.self, from: data), key)
    }

    func testAnOlderConfigurationWithoutSecondStateStillDecodes() throws {
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(KeyConfig(title: "Ancien"))) as! [String: Any]
        old.removeValue(forKey: "alternate")
        let decoded = try JSONDecoder().decode(KeyConfig.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(decoded.alternate)
    }

    func testAPressToggleFlipsOnEachPress() {
        var toggles = PressToggles()
        XCTAssertFalse(toggles.isOn(page: pageA, slot: 3))
        toggles.flip(page: pageA, slot: 3)
        XCTAssertTrue(toggles.isOn(page: pageA, slot: 3))
        toggles.flip(page: pageA, slot: 3)
        XCTAssertFalse(toggles.isOn(page: pageA, slot: 3))
    }

    func testTogglesAreSeparateForEachPageAndSlot() {
        var toggles = PressToggles()
        toggles.flip(page: pageA, slot: 3)
        XCTAssertFalse(toggles.isOn(page: pageA, slot: 4))
        XCTAssertFalse(toggles.isOn(page: UUID(), slot: 3))
    }

    private let pageA = UUID()
}
