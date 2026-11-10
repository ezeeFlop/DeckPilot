import XCTest
@testable import DeckCore

final class LiveValueTests: XCTestCase {
    func testReadsAPlainNumber() {
        XCTAssertEqual(LiveValue(text: "42").number, 42)
        XCTAssertEqual(LiveValue(text: " 42.5 \n").number, 42.5)
    }

    func testReadsTheFirstNumberInsideText() {
        XCTAssertEqual(LiveValue(text: "CPU: 63.4% used").number, 63.4)
        XCTAssertEqual(LiveValue(text: "-7,5 °C").number, -7.5)
    }

    func testKeepsTheFirstLineAsText() {
        let value = LiveValue(text: "  en ligne \nligne 2")
        XCTAssertEqual(value.text, "en ligne")
        XCTAssertNil(value.number)
    }

    func testEmptyTextHasNoValue() {
        XCTAssertNil(LiveValue(text: "  \n").number)
        XCTAssertEqual(LiveValue(text: "  \n").text, "")
    }
}

final class JSONPathTests: XCTestCase {
    private func extract(_ path: String, _ json: String) -> LiveValue? {
        JSONPath.extract(path, from: Data(json.utf8))
    }

    func testFollowsDottedKeys() {
        XCTAssertEqual(extract("data.temperature", #"{"data":{"temperature":21.5}}"#)?.number, 21.5)
    }

    func testFollowsArrayIndexes() {
        XCTAssertEqual(extract("items[1].name", #"{"items":[{"name":"a"},{"name":"b"}]}"#)?.text, "b")
        XCTAssertEqual(extract("[0]", "[7, 8]")?.number, 7)
    }

    func testAnEmptyPathReadsTheWholeBody() {
        XCTAssertEqual(extract("", "42")?.number, 42)
        XCTAssertEqual(extract("", "pas du json : 12 %")?.number, 12)
    }

    func testCountsAnArrayOrObjectWhenThePathEndsOnOne() {
        XCTAssertEqual(extract("items", #"{"items":[1,2,3]}"#)?.number, 3)
    }

    func testBooleansReadAsText() {
        XCTAssertEqual(extract("ok", #"{"ok":true}"#)?.text, "true")
    }

    func testAMissingKeyGivesNothing() {
        XCTAssertNil(extract("data.missing", #"{"data":{}}"#))
        XCTAssertNil(extract("items[5]", #"{"items":[1]}"#))
        XCTAssertNil(extract("a.b", "pas du json"))
    }
}

final class LiveDataTests: XCTestCase {
    func testFractionIsThePositionBetweenMinimumAndMaximum() {
        let live = LiveData(minimum: 0, maximum: 200)
        XCTAssertEqual(live.fraction(of: 50), 0.25)
    }

    func testFractionIsClamped() {
        let live = LiveData(minimum: 10, maximum: 20)
        XCTAssertEqual(live.fraction(of: 5), 0)
        XCTAssertEqual(live.fraction(of: 99), 1)
        XCTAssertEqual(LiveData(minimum: 5, maximum: 5).fraction(of: 5), 0)
    }

    func testLevelRisesAboveThresholds() {
        let live = LiveData(warning: 70, critical: 90)
        XCTAssertEqual(live.level(of: 50), .normal)
        XCTAssertEqual(live.level(of: 70), .warning)
        XCTAssertEqual(live.level(of: 95), .critical)
    }

    func testLevelCanAlertBelowThresholds() {
        let live = LiveData(warning: 30, critical: 10, alertsWhenBelow: true)
        XCTAssertEqual(live.level(of: 80), .normal)
        XCTAssertEqual(live.level(of: 25), .warning)
        XCTAssertEqual(live.level(of: 10), .critical)
    }

    func testWithoutThresholdsTheLevelIsNormal() {
        XCTAssertEqual(LiveData().level(of: 1_000_000), .normal)
    }

    func testFormatsWithDecimalsAndUnit() {
        let live = LiveData(unit: " %", decimals: 1)
        XCTAssertEqual(live.format(63.456, locale: Locale(identifier: "en_US")), "63.5 %")
        XCTAssertEqual(live.format(63.456, locale: Locale(identifier: "fr_FR")), "63,5 %")
        XCTAssertEqual(LiveData(decimals: 0).format(1234.6, locale: Locale(identifier: "en_US")), "1,235")
    }

    func testAKeyWithoutLiveDataDecodesFromAnOlderConfiguration() throws {
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(KeyConfig(title: "Ancien"))) as! [String: Any]
        old.removeValue(forKey: "live")
        let decoded = try JSONDecoder().decode(KeyConfig.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(decoded.title, "Ancien")
        XCTAssertNil(decoded.live)
    }

    func testLiveDataSurvivesEncodingAndDecoding() throws {
        var key = KeyConfig(title: "CPU")
        key.live = LiveData(source: .http(url: "https://example.com/api", jsonPath: "a.b", headers: "X-Key: 1"),
                            interval: 15, style: .ring, minimum: 0, maximum: 100, unit: "%", decimals: 0,
                            warning: 70, critical: 90)
        let data = try JSONEncoder().encode(key)
        XCTAssertEqual(try JSONDecoder().decode(KeyConfig.self, from: data), key)
    }

    func testAKeyWithLiveDataIsNotBlank() {
        var key = KeyConfig()
        key.live = LiveData(source: .system(.cpu))
        XCTAssertFalse(key.isBlank)
    }
}

final class LiveHistoryTests: XCTestCase {
    func testKeepsOnlyTheMostRecentValues() {
        var history = LiveHistory(capacity: 3)
        for value in [1.0, 2, 3, 4, 5] { history.append(value) }
        XCTAssertEqual(history.values, [3, 4, 5])
    }
}

final class LiveTransitionTests: XCTestCase {
    func testStartsAtThePreviousValueAndEndsAtTheNewOne() {
        let transition = LiveTransition(from: 10, to: 30, startedAt: 100, duration: 0.5)
        XCTAssertEqual(transition.value(at: 100), 10)
        XCTAssertEqual(transition.value(at: 100.5), 30)
        XCTAssertEqual(transition.value(at: 200), 30)
    }

    func testMovesMonotonicallyInBetween() {
        let transition = LiveTransition(from: 10, to: 30, startedAt: 0, duration: 1)
        let samples = stride(from: 0.0, through: 1.0, by: 0.1).map { transition.value(at: $0) }
        XCTAssertEqual(samples, samples.sorted())
        XCTAssertGreaterThan(transition.value(at: 0.5), 20, "la décélération place le milieu du temps après le milieu du trajet")
    }

    func testIsRunningOnlyDuringItsDuration() {
        let transition = LiveTransition(from: 0, to: 1, startedAt: 10, duration: 0.5)
        XCTAssertTrue(transition.isRunning(at: 10.2))
        XCTAssertFalse(transition.isRunning(at: 10.6))
    }
}
