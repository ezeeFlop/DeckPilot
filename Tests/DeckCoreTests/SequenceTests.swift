import XCTest
@testable import DeckCore

final class SequenceTests: XCTestCase {
    func testStepsAreTheActionsInOrder() {
        let action = KeyAction.sequence(steps: [.openURL("a"), .typeText("b"), .media(.mute)], pause: 0.5)
        XCTAssertEqual(action.steps, [.openURL("a"), .typeText("b"), .media(.mute)])
    }

    func testEmptyStepsAndNestedSequencesAreFlattened() {
        let inner = KeyAction.sequence(steps: [.typeText("b"), .none, .typeText("c")], pause: 2)
        let action = KeyAction.sequence(steps: [.openURL("a"), .none, inner, .nextPage], pause: 0)
        XCTAssertEqual(action.steps, [.openURL("a"), .typeText("b"), .typeText("c"), .nextPage])
    }

    func testASingleActionIsItsOwnOnlyStep() {
        XCTAssertEqual(KeyAction.media(.next).steps, [.media(.next)])
        XCTAssertEqual(KeyAction.none.steps, [])
    }

    func testASequenceSurvivesEncodingAndDecoding() throws {
        let action = KeyAction.sequence(steps: [.launchApp(path: "/Applications/Safari.app"), .hotkey(keyCode: 17, modifiers: 1 << 20, display: "⌘T")], pause: 1)
        XCTAssertEqual(try JSONDecoder().decode(KeyAction.self, from: JSONEncoder().encode(action)), action)
    }

    func testRunsEveryStepInOrderWithAPauseBetweenButNotAfter() async {
        let log = Log()
        let finished = await SequenceRunner.run(
            [.typeText("1"), .typeText("2"), .typeText("3")], pause: 0.5,
            perform: { await log.add("action \($0)"); return true },
            sleep: { await log.add("pause \($0)") })
        let entries = await log.entries
        XCTAssertTrue(finished)
        XCTAssertEqual(entries, ["action typeText(\"1\")", "pause 0.5", "action typeText(\"2\")", "pause 0.5", "action typeText(\"3\")"])
    }

    func testWithoutPauseNoSleepIsRequested() async {
        let log = Log()
        _ = await SequenceRunner.run([.nextPage, .previousPage], pause: 0,
                                     perform: { await log.add("\($0)"); return true }, sleep: { await log.add("pause \($0)") })
        let entries = await log.entries
        XCTAssertEqual(entries, ["nextPage", "previousPage"])
    }

    func testStopsAtTheFirstStepThatFails() async {
        let log = Log()
        let finished = await SequenceRunner.run(
            [.typeText("1"), .typeText("échec"), .typeText("3")], pause: 0,
            perform: { await log.add("\($0)"); return $0 != .typeText("échec") }, sleep: { _ in })
        let entries = await log.entries
        XCTAssertFalse(finished)
        XCTAssertEqual(entries.count, 2)
    }

    func testStopsWhenCancelled() async {
        let log = Log()
        let task = Task {
            await SequenceRunner.run([.typeText("1"), .typeText("2")], pause: 1,
                                     perform: { await log.add("\($0)"); return true },
                                     sleep: { _ in withUnsafeCurrentTask { $0?.cancel() } })
        }
        let finished = await task.value
        let entries = await log.entries
        XCTAssertFalse(finished)
        XCTAssertEqual(entries.count, 1)
    }
}

private actor Log {
    private(set) var entries: [String] = []
    func add(_ entry: String) { entries.append(entry) }
}
