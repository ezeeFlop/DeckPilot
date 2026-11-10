import XCTest
@testable import DeckCore

final class ConfigStoreTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("deckcore-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testLoadingWithoutAFileGivesTheStarterConfiguration() {
        XCTAssertEqual(ConfigStore(folder: folder).load().pages.map(\.name), DeckConfiguration.starter.pages.map(\.name))
    }

    func testSavedConfigurationIsReadBack() throws {
        let store = ConfigStore(folder: folder)
        var config = DeckConfiguration(brightness: 33, pages: [Page(name: "Montage")])
        config.pages[0].keys[4] = KeyConfig(title: "Couper", action: .typeText("x"))
        try store.save(config)
        XCTAssertEqual(ConfigStore(folder: folder).load(), config)
    }

    func testUnreadableFileIsKeptAsideAndStarterIsReturned() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("pas du json".utf8).write(to: folder.appendingPathComponent("config.json"))
        let loaded = ConfigStore(folder: folder).load()
        XCTAssertEqual(loaded.pages.count, 1)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("config-illisible") }, "\(names)")
    }

    func testImportedImageIsCopiedIntoTheStoreAndResolvable() throws {
        let store = ConfigStore(folder: folder)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try Data([1, 2, 3]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let name = try store.importImage(from: source)
        XCTAssertTrue(name.hasSuffix(".png"))
        XCTAssertEqual(try Data(contentsOf: store.imageURL(named: name)), Data([1, 2, 3]))
    }

    func testImportingTheSameFileTwiceGivesTwoDistinctNames() throws {
        let store = ConfigStore(folder: folder)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gif")
        try Data([9]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        XCTAssertNotEqual(try store.importImage(from: source), try store.importImage(from: source))
    }

    func testLaunchStoreUsesTheStandardFolderByDefault() {
        let defaults = UserDefaults(suiteName: "deckcore-\(UUID().uuidString)")!
        XCTAssertEqual(ConfigStore.forLaunch(defaults: defaults).folder, ConfigStore.standard.folder)
    }

    func testLaunchStoreFollowsTheConfigFolderSetting() {
        let defaults = UserDefaults(suiteName: "deckcore-\(UUID().uuidString)")!
        defaults.set("/tmp/une-autre-config", forKey: "configFolder")
        XCTAssertEqual(ConfigStore.forLaunch(defaults: defaults).folder.path, "/tmp/une-autre-config")
    }
}
