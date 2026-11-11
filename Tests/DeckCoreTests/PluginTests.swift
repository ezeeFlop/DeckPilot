import XCTest
@testable import DeckCore

final class JSONValueTests: XCTestCase {
    func testDecodesAndReencodesAnyJSON() throws {
        let text = #"{"a":1,"b":[true,null,"x",2.5],"c":{"d":"e"}}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        XCTAssertEqual(value["a"], .number(1))
        XCTAssertEqual(value["b"], .array([.bool(true), .null, .string("x"), .number(2.5)]))
        XCTAssertEqual(value["c"]?["d"], .string("e"))
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)), value)
    }

    func testConvertsFromAndToFoundationObjects() {
        let value = JSONValue(any: ["n": 3, "s": "t", "flag": true, "list": [1, "deux"]] as [String: Any])
        XCTAssertEqual(value, .object(["n": .number(3), "s": .string("t"), "flag": .bool(true),
                                       "list": .array([.number(1), .string("deux")])]))
        XCTAssertEqual(JSONValue(any: value.any), value)
    }

    func testWholeNumbersAreWrittenWithoutADecimalPoint() throws {
        let text = String(data: try JSONEncoder().encode(JSONValue.object(["n": .number(3)])), encoding: .utf8)
        XCTAssertEqual(text, #"{"n":3}"#)
    }
}

final class PluginManifestTests: XCTestCase {
    private let json = """
    {
      "Name": "Météo", "UUID": "com.example.meteo", "Version": "1.0.0.0", "Author": "Moi", "Description": "Mesures",
      "Icon": "imgs/plugin", "CodePath": "bin/plugin.js", "SDKVersion": 2,
      "Nodejs": { "Version": "20" }, "Software": { "MinimumVersion": "6.5" },
      "Actions": [
        { "UUID": "com.example.meteo.metric", "Name": "Mesure", "Icon": "imgs/metric", "Tooltip": "Affiche une mesure",
          "PropertyInspectorPath": "ui/metric.html", "Controllers": ["Keypad"],
          "States": [ { "Image": "imgs/key" }, { "Image": "imgs/key-on", "Title": "On" } ] },
        { "UUID": "com.example.meteo.dial", "Name": "Molette", "Controllers": ["Encoder"], "States": [ { "Image": "imgs/dial" } ] }
      ]
    }
    """

    func testReadsThePluginIdentityAndEntryPoint() throws {
        let manifest = try PluginManifest(json: Data(json.utf8))
        XCTAssertEqual(manifest.name, "Météo")
        XCTAssertEqual(manifest.uuid, "com.example.meteo")
        XCTAssertEqual(manifest.version, "1.0.0.0")
        XCTAssertEqual(manifest.codePath, "bin/plugin.js")
        XCTAssertTrue(manifest.runsOnNode)
    }

    func testReadsActionsWithTheirStatesAndSettingsPage() throws {
        let action = try XCTUnwrap(PluginManifest(json: Data(json.utf8)).actions.first)
        XCTAssertEqual(action.uuid, "com.example.meteo.metric")
        XCTAssertEqual(action.name, "Mesure")
        XCTAssertEqual(action.propertyInspectorPath, "ui/metric.html")
        XCTAssertEqual(action.states.map(\.image), ["imgs/key", "imgs/key-on"])
        XCTAssertEqual(action.states[1].title, "On")
    }

    func testKeepsOnlyActionsThatWorkOnKeys() throws {
        XCTAssertEqual(try PluginManifest(json: Data(json.utf8)).keyActions.map(\.uuid), ["com.example.meteo.metric"])
    }

    func testPrefersTheMacEntryPointAndFallsBackToThePluginSettingsPage() throws {
        let text = #"{"Name":"N","UUID":"u","Version":"1","CodePath":"win.exe","CodePathMac":"mac-bin","PropertyInspectorPath":"pi.html","Actions":[{"UUID":"u.a","Name":"A","States":[{"Image":"i"}]}]}"#
        let manifest = try PluginManifest(json: Data(text.utf8))
        XCTAssertEqual(manifest.codePath, "mac-bin")
        XCTAssertFalse(manifest.runsOnNode)
        XCTAssertEqual(manifest.propertyInspectorPath(for: manifest.actions[0]), "pi.html")
    }

    func testAManifestWithoutEntryPointIsRejected() {
        XCTAssertThrowsError(try PluginManifest(json: Data(#"{"Name":"N","UUID":"u","Actions":[]}"#.utf8)))
    }
}

final class PluginMessageTests: XCTestCase {
    private func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    func testParsesRegistration() {
        XCTAssertEqual(PluginCommand(json: #"{"event":"registerPlugin","uuid":"ABC"}"#), .register(event: "registerPlugin", uuid: "ABC"))
    }

    func testParsesDrawingCommands() {
        XCTAssertEqual(PluginCommand(json: #"{"event":"setTitle","context":"c1","payload":{"title":"42 %","target":0}}"#),
                       .setTitle(context: "c1", title: "42 %"))
        XCTAssertEqual(PluginCommand(json: #"{"event":"setTitle","context":"c1","payload":{}}"#), .setTitle(context: "c1", title: nil))
        XCTAssertEqual(PluginCommand(json: #"{"event":"setImage","context":"c1","payload":{"image":"data:image/png;base64,AAAA"}}"#),
                       .setImage(context: "c1", image: "data:image/png;base64,AAAA"))
        XCTAssertEqual(PluginCommand(json: #"{"event":"setState","context":"c1","payload":{"state":1}}"#), .setState(context: "c1", state: 1))
        XCTAssertEqual(PluginCommand(json: #"{"event":"showOk","context":"c1"}"#), .showOk(context: "c1"))
        XCTAssertEqual(PluginCommand(json: #"{"event":"showAlert","context":"c1"}"#), .showAlert(context: "c1"))
    }

    func testParsesSettingsCommands() {
        XCTAssertEqual(PluginCommand(json: #"{"event":"setSettings","context":"c1","payload":{"node":"n1"}}"#),
                       .setSettings(context: "c1", settings: .object(["node": .string("n1")])))
        XCTAssertEqual(PluginCommand(json: #"{"event":"getSettings","context":"c1","id":"r7"}"#), .getSettings(context: "c1", id: "r7"))
        XCTAssertEqual(PluginCommand(json: #"{"event":"setGlobalSettings","context":"P","payload":{"url":"x"}}"#),
                       .setGlobalSettings(context: "P", settings: .object(["url": .string("x")])))
        XCTAssertEqual(PluginCommand(json: #"{"event":"getGlobalSettings","context":"P"}"#), .getGlobalSettings(context: "P", id: nil))
    }

    func testParsesMessagesBetweenPluginAndSettingsPage() {
        XCTAssertEqual(PluginCommand(json: #"{"event":"sendToPropertyInspector","context":"c1","payload":{"nodes":["a"]}}"#),
                       .sendToPropertyInspector(context: "c1", payload: .object(["nodes": .array([.string("a")])])))
        XCTAssertEqual(PluginCommand(json: #"{"event":"sendToPlugin","action":"act","context":"c1","payload":{"ask":"nodes"}}"#),
                       .sendToPlugin(context: "c1", payload: .object(["ask": .string("nodes")])))
    }

    func testParsesSystemCommands() {
        XCTAssertEqual(PluginCommand(json: #"{"event":"openUrl","payload":{"url":"https://example.com"}}"#), .openURL("https://example.com"))
        XCTAssertEqual(PluginCommand(json: #"{"event":"logMessage","payload":{"message":"bonjour"}}"#), .log("bonjour"))
    }

    func testUnknownOrMalformedMessagesAreIgnored() {
        XCTAssertNil(PluginCommand(json: "pas du json"))
        XCTAssertEqual(PluginCommand(json: #"{"event":"setFeedback","context":"c","payload":{}}"#), .unsupported("setFeedback"))
    }

    func testWillAppearCarriesActionContextDeviceSettingsAndCoordinates() throws {
        let instance = PluginInstance(action: "act", context: "c1", settings: .object(["k": .string("v")]), row: 2, column: 4, state: 1)
        let event = try object(PluginEvent.willAppear(instance, device: "dev"))
        XCTAssertEqual(event["event"] as? String, "willAppear")
        XCTAssertEqual(event["action"] as? String, "act")
        XCTAssertEqual(event["context"] as? String, "c1")
        XCTAssertEqual(event["device"] as? String, "dev")
        let payload = try XCTUnwrap(event["payload"] as? [String: Any])
        XCTAssertEqual(payload["controller"] as? String, "Keypad")
        XCTAssertEqual(payload["isInMultiAction"] as? Bool, false)
        XCTAssertEqual(payload["state"] as? Int, 1)
        XCTAssertEqual((payload["settings"] as? [String: Any])?["k"] as? String, "v")
        XCTAssertEqual((payload["coordinates"] as? [String: Any])?["row"] as? Int, 2)
        XCTAssertEqual((payload["coordinates"] as? [String: Any])?["column"] as? Int, 4)
        XCTAssertNotNil(payload["resources"] as? [String: Any])
    }

    func testKeyEventsAndSettingsRepliesUseTheSameShape() throws {
        let instance = PluginInstance(action: "act", context: "c1", settings: .object([:]), row: 0, column: 0, state: 0)
        XCTAssertEqual(try object(PluginEvent.keyDown(instance, device: "dev"))["event"] as? String, "keyDown")
        XCTAssertEqual(try object(PluginEvent.keyUp(instance, device: "dev"))["event"] as? String, "keyUp")
        let reply = try object(PluginEvent.didReceiveSettings(instance, device: "dev", id: "r7"))
        XCTAssertEqual(reply["event"] as? String, "didReceiveSettings")
        XCTAssertEqual(reply["id"] as? String, "r7")
    }

    func testGlobalSettingsReplyHasNoActionOrContext() throws {
        let reply = try object(PluginEvent.didReceiveGlobalSettings(.object(["url": .string("x")]), id: nil))
        XCTAssertEqual(reply["event"] as? String, "didReceiveGlobalSettings")
        XCTAssertNil(reply["context"])
        XCTAssertNil(reply["id"])
        XCTAssertEqual(((reply["payload"] as? [String: Any])?["settings"] as? [String: Any])?["url"] as? String, "x")
    }

    func testRegistrationInfoDescribesTheHostAndItsDeck() throws {
        let info = try object(PluginEvent.registrationInfo(pluginUUID: "com.example.meteo", pluginVersion: "1.0", device: "dev",
                                                           deviceName: "StreamDock", columns: 5, rows: 3, language: "fr"))
        let application = try XCTUnwrap(info["application"] as? [String: Any])
        XCTAssertEqual(application["platform"] as? String, "mac")
        XCTAssertEqual(application["language"] as? String, "fr")
        XCTAssertNotNil(application["version"] as? String)
        XCTAssertEqual((info["plugin"] as? [String: Any])?["uuid"] as? String, "com.example.meteo")
        let device = try XCTUnwrap((info["devices"] as? [[String: Any]])?.first)
        XCTAssertEqual(device["id"] as? String, "dev")
        XCTAssertEqual((device["size"] as? [String: Any])?["columns"] as? Int, 5)
        XCTAssertNotNil(info["colors"] as? [String: Any])
        XCTAssertNotNil(info["devicePixelRatio"])
    }
}

final class DataURLTests: XCTestCase {
    func testDecodesBase64() {
        let decoded = DataURL.decode("data:image/png;base64,AQID")
        XCTAssertEqual(decoded?.mimeType, "image/png")
        XCTAssertEqual(decoded?.data, Data([1, 2, 3]))
    }

    func testDecodesPercentEncodedText() {
        let decoded = DataURL.decode("data:image/svg+xml;charset=utf8,%3Csvg%20width%3D%221%22%2F%3E")
        XCTAssertEqual(decoded?.mimeType, "image/svg+xml")
        XCTAssertEqual(decoded.map { String(decoding: $0.data, as: UTF8.self) }, #"<svg width="1"/>"#)
    }

    func testDecodesUnencodedSVGText() {
        let decoded = DataURL.decode(#"data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg"/>"#)
        XCTAssertEqual(decoded.map { String(decoding: $0.data, as: UTF8.self) }, #"<svg xmlns="http://www.w3.org/2000/svg"/>"#)
    }

    func testAnythingElseIsNotADataURL() {
        XCTAssertNil(DataURL.decode("imgs/key.png"))
        XCTAssertNil(DataURL.decode("data:image/png;base64,###"))
    }
}

final class PluginBindingTests: XCTestCase {
    func testAKeyBoundToAPluginSurvivesEncodingAndDecoding() throws {
        var key = KeyConfig(title: "GPU")
        key.plugin = PluginBinding(action: "com.example.meteo.metric", context: "ctx-1", settings: .object(["node": .string("n1")]))
        XCTAssertEqual(try JSONDecoder().decode(KeyConfig.self, from: JSONEncoder().encode(key)), key)
        XCTAssertFalse(key.isBlank)
    }

    func testAnOlderKeyHasNoPlugin() throws {
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(KeyConfig(title: "Ancien"))) as! [String: Any]
        old.removeValue(forKey: "plugin")
        XCTAssertNil(try JSONDecoder().decode(KeyConfig.self, from: JSONSerialization.data(withJSONObject: old)).plugin)
    }
}

final class PluginKeyCopyTests: XCTestCase {
    /// Deux touches visibles avec le même identifiant seraient une seule touche pour l'extension.
    func testACopiedExtensionKeyGetsItsOwnContextAndKeepsItsSettings() {
        var original = KeyConfig(title: "GPU")
        original.plugin = PluginBinding(action: "com.example.meteo.temperature", settings: .object(["ville": .string("Lyon")]))
        let copy = original.copiedForPasting()
        XCTAssertNotEqual(copy.plugin?.context, original.plugin?.context)
        XCTAssertEqual(copy.plugin?.action, original.plugin?.action)
        XCTAssertEqual(copy.plugin?.settings, original.plugin?.settings)
        XCTAssertEqual(copy.title, "GPU")
    }

    func testEachPasteGetsADifferentContext() {
        var original = KeyConfig()
        original.plugin = PluginBinding(action: "com.example.meteo.temperature")
        XCTAssertNotEqual(original.copiedForPasting().plugin?.context, original.copiedForPasting().plugin?.context)
    }

    func testAnOrdinaryKeyIsCopiedUnchanged() {
        let original = KeyConfig(title: "Safari", action: .launchApp(path: "/Applications/Safari.app"))
        XCTAssertEqual(original.copiedForPasting(), original)
    }
}

final class PluginInstanceIndexTests: XCTestCase {
    /// Une configuration abîmée (même identifiant sur deux touches) ne doit pas arrêter l'application.
    func testInstancesSharingAContextKeepTheFirstOne() {
        let first = PluginInstance(action: "a", context: "C1", settings: .object([:]), row: 0, column: 0, state: 0)
        let twin = PluginInstance(action: "a", context: "C1", settings: .object([:]), row: 1, column: 2, state: 0)
        let other = PluginInstance(action: "a", context: "C2", settings: .object([:]), row: 2, column: 4, state: 0)
        let index = PluginInstance.byContext([first, twin, other])
        XCTAssertEqual(index.count, 2)
        XCTAssertEqual(index["C1"], first)
        XCTAssertEqual(index["C2"], other)
    }
}
