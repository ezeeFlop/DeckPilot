import XCTest
@testable import DeckCore

final class PageHistoryTests: XCTestCase {
    private let home = UUID(), folder = UUID(), nested = UUID()

    func testGoingBackReturnsToThePageWeCameFrom() {
        var history = PageHistory()
        history.enter(from: home)
        XCTAssertEqual(history.back(), home)
    }

    func testNestedFoldersUnwindOneLevelAtATime() {
        var history = PageHistory()
        history.enter(from: home)
        history.enter(from: folder)
        XCTAssertEqual(history.back(), folder)
        XCTAssertEqual(history.back(), home)
        XCTAssertNil(history.back())
    }

    func testADeletedPageIsForgotten() {
        var history = PageHistory()
        history.enter(from: home)
        history.enter(from: folder)
        history.forget(folder)
        XCTAssertEqual(history.back(), home)
    }
}

final class FolderPageTests: XCTestCase {
    func testNextPageSkipsFolders() {
        let config = DeckConfiguration(pages: [Page(name: "A"), Page(name: "Dossier", isFolder: true), Page(name: "B")])
        XCTAssertEqual(config.pageIndex(after: 0), 2)
        XCTAssertEqual(config.pageIndex(after: 2), 0)
        XCTAssertEqual(config.pageIndex(before: 2), 0)
    }

    func testFromInsideAFolderNextGoesToTheFollowingOrdinaryPage() {
        let config = DeckConfiguration(pages: [Page(name: "A"), Page(name: "Dossier", isFolder: true), Page(name: "B")])
        XCTAssertEqual(config.pageIndex(after: 1), 2)
        XCTAssertEqual(config.pageIndex(before: 1), 0)
    }

    func testWithOnlyOneOrdinaryPageNextStaysPut() {
        let config = DeckConfiguration(pages: [Page(name: "A"), Page(name: "Dossier", isFolder: true)])
        XCTAssertEqual(config.pageIndex(after: 0), 0)
    }

    func testAPageFromAnOlderConfigurationIsAnOrdinaryPageWithoutApps() throws {
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Ancienne","keys":{}}"#
        let page = try JSONDecoder().decode(Page.self, from: Data(old.utf8))
        XCTAssertFalse(page.isFolder)
        XCTAssertEqual(page.apps, [])
    }

    func testFolderFlagAndAppsSurviveEncodingAndDecoding() throws {
        let page = Page(name: "Montage", isFolder: true, apps: ["com.apple.FinalCut"])
        XCTAssertEqual(try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(page)), page)
    }
}

final class AutoSwitcherTests: XCTestCase {
    private let home = Page(name: "Accueil")
    private let safari = Page(name: "Web", apps: ["com.apple.Safari"])
    private let xcode = Page(name: "Code", apps: ["com.apple.dt.Xcode"])
    private var pages: [Page] { [home, safari, xcode] }

    func testAnAppWithItsOwnPageBringsThatPageUp() {
        var switcher = AutoSwitcher()
        XCTAssertEqual(switcher.frontmostChanged(to: "com.apple.Safari", pages: pages, current: home.id), safari.id)
    }

    func testLeavingForAnAppWithoutAPageReturnsToWhereWeWere() {
        var switcher = AutoSwitcher()
        _ = switcher.frontmostChanged(to: "com.apple.Safari", pages: pages, current: home.id)
        XCTAssertEqual(switcher.frontmostChanged(to: "com.apple.mail", pages: pages, current: safari.id), home.id)
    }

    func testGoingFromOneAppPageToAnotherStillReturnsToTheOriginalPage() {
        var switcher = AutoSwitcher()
        _ = switcher.frontmostChanged(to: "com.apple.Safari", pages: pages, current: home.id)
        XCTAssertEqual(switcher.frontmostChanged(to: "com.apple.dt.Xcode", pages: pages, current: safari.id), xcode.id)
        XCTAssertEqual(switcher.frontmostChanged(to: "com.apple.mail", pages: pages, current: xcode.id), home.id)
    }

    func testAnAppWithoutAPageChangesNothingWhenNoSwitchIsPending() {
        var switcher = AutoSwitcher()
        XCTAssertNil(switcher.frontmostChanged(to: "com.apple.mail", pages: pages, current: home.id))
    }

    func testAlreadyOnTheAppsPageChangesNothing() {
        var switcher = AutoSwitcher()
        XCTAssertNil(switcher.frontmostChanged(to: "com.apple.Safari", pages: pages, current: safari.id))
        XCTAssertNil(switcher.frontmostChanged(to: "com.apple.mail", pages: pages, current: safari.id),
                     "on y était déjà de son plein gré : rien à rétablir")
    }

    func testIgnoredAppsNeverSwitchAndKeepThePendingReturn() {
        var switcher = AutoSwitcher(ignoring: ["com.spongetheory.deckpilot"])
        _ = switcher.frontmostChanged(to: "com.apple.Safari", pages: pages, current: home.id)
        XCTAssertNil(switcher.frontmostChanged(to: "com.spongetheory.deckpilot", pages: pages, current: safari.id))
        XCTAssertEqual(switcher.frontmostChanged(to: "com.apple.mail", pages: pages, current: safari.id), home.id)
    }

    func testAReturnPageThatWasDeletedIsNotRestored() {
        var switcher = AutoSwitcher()
        _ = switcher.frontmostChanged(to: "com.apple.Safari", pages: pages, current: home.id)
        XCTAssertNil(switcher.frontmostChanged(to: "com.apple.mail", pages: [safari, xcode], current: safari.id))
    }

    func testAnUnknownFrontmostAppIsTreatedAsHavingNoPage() {
        var switcher = AutoSwitcher()
        XCTAssertNil(switcher.frontmostChanged(to: nil, pages: pages, current: home.id))
    }
}
