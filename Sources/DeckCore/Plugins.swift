import Foundation

// Accueil des extensions au format du kit Stream Deck d'Elgato : lecture du manifeste et messages échangés
// par WebSocket. Les formes suivent les définitions du paquet officiel @elgato/streamdeck (version 3).

/// Le fichier `manifest.json` d'une extension.
public struct PluginManifest: Equatable, Sendable {
    public struct State: Equatable, Sendable {
        public let image: String
        public let title: String?
    }

    public struct Action: Equatable, Sendable, Identifiable {
        public let uuid: String
        public let name: String
        public let icon: String?
        public let tooltip: String?
        public let propertyInspectorPath: String?
        public let states: [State]
        public let controllers: [String]?
        public var id: String { uuid }
    }

    public enum ManifestError: Error {
        case unreadable
        case missing(String)
    }

    public let name: String
    public let uuid: String
    public let version: String
    public let author: String?
    public let description: String?
    public let icon: String?
    /// Programme à lancer, relatif au dossier de l'extension. Le chemin propre au Mac passe avant le chemin commun.
    public let codePath: String
    public let runsOnNode: Bool
    public let actions: [Action]
    private let pluginPropertyInspectorPath: String?

    public init(json: Data) throws {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { throw ManifestError.unreadable }
        guard let name = root["Name"] as? String else { throw ManifestError.missing("Name") }
        guard let uuid = root["UUID"] as? String else { throw ManifestError.missing("UUID") }
        guard let codePath = (root["CodePathMac"] as? String) ?? (root["CodePath"] as? String) else {
            throw ManifestError.missing("CodePath")
        }
        self.name = name
        self.uuid = uuid
        self.codePath = codePath
        version = root["Version"] as? String ?? "0"
        author = root["Author"] as? String
        description = root["Description"] as? String
        icon = root["Icon"] as? String
        pluginPropertyInspectorPath = root["PropertyInspectorPath"] as? String
        let scripts = [".js", ".mjs", ".cjs"]
        runsOnNode = root["Nodejs"] != nil || scripts.contains { codePath.lowercased().hasSuffix($0) }
        actions = (root["Actions"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let uuid = entry["UUID"] as? String else { return nil }
            let states = (entry["States"] as? [[String: Any]] ?? []).map {
                State(image: $0["Image"] as? String ?? "", title: $0["Title"] as? String)
            }
            return Action(uuid: uuid, name: entry["Name"] as? String ?? uuid, icon: entry["Icon"] as? String,
                          tooltip: entry["Tooltip"] as? String, propertyInspectorPath: entry["PropertyInspectorPath"] as? String,
                          states: states, controllers: entry["Controllers"] as? [String])
        }
    }

    /// Les actions utilisables sur une touche (les molettes et bandes tactiles sont propres au matériel Elgato).
    public var keyActions: [Action] {
        actions.filter { $0.controllers?.contains("Keypad") ?? true }
    }

    /// La page de réglage d'une action : la sienne, sinon celle de l'extension.
    public func propertyInspectorPath(for action: Action) -> String? {
        action.propertyInspectorPath ?? pluginPropertyInspectorPath
    }
}

/// Le lien entre une touche et une action d'extension.
public struct PluginBinding: Codable, Hashable, Sendable {
    /// Identifiant de l'action dans le manifeste de l'extension.
    public var action: String
    /// Identifiant de cette touche-ci auprès de l'extension ; il ne change pas quand la touche est déplacée.
    public var context: String
    /// Réglages de la touche, tenus par l'extension.
    public var settings: JSONValue

    public init(action: String, context: String = UUID().uuidString, settings: JSONValue = .object([:])) {
        self.action = action
        self.context = context
        self.settings = settings
    }
}

/// Une touche d'extension telle qu'elle est décrite à l'extension.
public struct PluginInstance: Equatable, Sendable {
    public var action: String
    public var context: String
    public var settings: JSONValue
    public var row: Int
    public var column: Int
    public var state: Int

    public init(action: String, context: String, settings: JSONValue, row: Int, column: Int, state: Int) {
        self.action = action
        self.context = context
        self.settings = settings
        self.row = row
        self.column = column
        self.state = state
    }
}

/// Ce qu'une extension, ou sa page de réglage, demande à l'hôte.
public enum PluginCommand: Equatable, Sendable {
    case register(event: String, uuid: String)
    case setTitle(context: String, title: String?)
    case setImage(context: String, image: String?)
    case setState(context: String, state: Int)
    case showOk(context: String)
    case showAlert(context: String)
    case setSettings(context: String, settings: JSONValue)
    case getSettings(context: String, id: String?)
    case setGlobalSettings(context: String, settings: JSONValue)
    case getGlobalSettings(context: String, id: String?)
    case sendToPropertyInspector(context: String, payload: JSONValue)
    case sendToPlugin(context: String, payload: JSONValue)
    case openURL(String)
    case log(String)
    /// Commande connue du protocole mais sans objet ici (molettes, profils…).
    case unsupported(String)

    public init?(json text: String) {
        guard let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let event = root["event"] as? String else { return nil }
        let context = root["context"] as? String ?? ""
        let payload = root["payload"] as? [String: Any] ?? [:]
        let id = root["id"] as? String
        switch event {
        case "registerPlugin", "registerPropertyInspector":
            guard let uuid = root["uuid"] as? String else { return nil }
            self = .register(event: event, uuid: uuid)
        case "setTitle": self = .setTitle(context: context, title: payload["title"] as? String)
        case "setImage": self = .setImage(context: context, image: payload["image"] as? String)
        case "setState": self = .setState(context: context, state: payload["state"] as? Int ?? 0)
        case "showOk": self = .showOk(context: context)
        case "showAlert": self = .showAlert(context: context)
        case "setSettings": self = .setSettings(context: context, settings: JSONValue(any: payload))
        case "getSettings": self = .getSettings(context: context, id: id)
        case "setGlobalSettings": self = .setGlobalSettings(context: context, settings: JSONValue(any: payload))
        case "getGlobalSettings": self = .getGlobalSettings(context: context, id: id)
        case "sendToPropertyInspector":
            self = .sendToPropertyInspector(context: context, payload: JSONValue(any: root["payload"] ?? NSNull()))
        case "sendToPlugin":
            self = .sendToPlugin(context: context, payload: JSONValue(any: root["payload"] ?? NSNull()))
        case "openUrl":
            guard let url = payload["url"] as? String else { return nil }
            self = .openURL(url)
        case "logMessage": self = .log(payload["message"] as? String ?? "")
        default: self = .unsupported(event)
        }
    }
}

/// Ce que l'hôte envoie à une extension ou à sa page de réglage, en texte JSON.
public enum PluginEvent {
    /// Version du logiciel Stream Deck dont l'hôte reproduit le comportement.
    public static let emulatedVersion = "7.1.0"

    public static func willAppear(_ instance: PluginInstance, device: String) -> String { action("willAppear", instance, device) }
    public static func willDisappear(_ instance: PluginInstance, device: String) -> String { action("willDisappear", instance, device) }
    public static func keyDown(_ instance: PluginInstance, device: String) -> String { action("keyDown", instance, device) }
    public static func keyUp(_ instance: PluginInstance, device: String) -> String { action("keyUp", instance, device) }

    public static func didReceiveSettings(_ instance: PluginInstance, device: String, id: String?) -> String {
        action("didReceiveSettings", instance, device, id: id)
    }

    public static func didReceiveGlobalSettings(_ settings: JSONValue, id: String?) -> String {
        var message: [String: Any] = ["event": "didReceiveGlobalSettings", "payload": ["settings": settings.any]]
        if let id { message["id"] = id }
        return text(message)
    }

    public static func deviceDidConnect(device: String, name: String, columns: Int, rows: Int) -> String {
        text(["event": "deviceDidConnect", "device": device, "deviceInfo": deviceInfo(name: name, columns: columns, rows: rows)])
    }

    public static func propertyInspectorDidAppear(action: String, context: String, device: String) -> String {
        text(["event": "propertyInspectorDidAppear", "action": action, "context": context, "device": device])
    }

    public static func propertyInspectorDidDisappear(action: String, context: String, device: String) -> String {
        text(["event": "propertyInspectorDidDisappear", "action": action, "context": context, "device": device])
    }

    /// Message de la page de réglage, relayé à l'extension.
    public static func sendToPlugin(action: String, context: String, payload: JSONValue) -> String {
        text(["event": "sendToPlugin", "action": action, "context": context, "payload": payload.any])
    }

    /// Message de l'extension, relayé à la page de réglage.
    public static func sendToPropertyInspector(action: String, context: String, payload: JSONValue) -> String {
        text(["event": "sendToPropertyInspector", "action": action, "context": context, "payload": payload.any])
    }

    /// L'argument `-info` passé à l'extension au lancement.
    public static func registrationInfo(pluginUUID: String, pluginVersion: String, device: String, deviceName: String,
                                        columns: Int, rows: Int, language: String) -> String {
        var entry = deviceInfo(name: deviceName, columns: columns, rows: rows)
        entry["id"] = device
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return text([
            "application": [
                "font": ".AppleSystemUIFont", "language": language, "platform": "mac",
                "platformVersion": "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                "version": emulatedVersion,
            ],
            "colors": [
                "buttonMouseOverBackgroundColor": "#464646FF", "buttonPressedBackgroundColor": "#303030FF",
                "buttonPressedBorderColor": "#646464FF", "buttonPressedTextColor": "#969696FF", "highlightColor": "#0078FFFF",
            ],
            "devicePixelRatio": 2,
            "devices": [entry],
            "plugin": ["uuid": pluginUUID, "version": pluginVersion],
        ])
    }

    /// La description de la touche passée à la page de réglage.
    public static func actionInfo(_ instance: PluginInstance, device: String) -> String {
        text(["action": instance.action, "context": instance.context, "device": device, "payload": payload(instance)])
    }

    private static func action(_ event: String, _ instance: PluginInstance, _ device: String, id: String? = nil) -> String {
        var message: [String: Any] = [
            "event": event, "action": instance.action, "context": instance.context, "device": device, "payload": payload(instance),
        ]
        if let id { message["id"] = id }
        return text(message)
    }

    private static func payload(_ instance: PluginInstance) -> [String: Any] {
        [
            "settings": instance.settings.any, "coordinates": ["column": instance.column, "row": instance.row],
            "controller": "Keypad", "isInMultiAction": false, "state": instance.state, "resources": [String: Any](),
        ]
    }

    /// Le boîtier est présenté comme un Stream Deck classique (type 0) : une grille de touches, sans molette.
    private static func deviceInfo(name: String, columns: Int, rows: Int) -> [String: Any] {
        ["name": name, "type": 0, "size": ["columns": columns, "rows": rows]]
    }

    private static func text(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

/// Lecture d'une image envoyée « en ligne » par une extension (`data:image/png;base64,…`).
public enum DataURL {
    public static func decode(_ text: String) -> (mimeType: String, data: Data)? {
        guard text.hasPrefix("data:"), let comma = text.firstIndex(of: ",") else { return nil }
        let header = text[text.index(text.startIndex, offsetBy: 5)..<comma]
        let body = String(text[text.index(after: comma)...])
        let parts = header.split(separator: ";").map(String.init)
        let mimeType = parts.first ?? "text/plain"
        if parts.contains("base64") {
            guard let data = Data(base64Encoded: body, options: [.ignoreUnknownCharacters]), !data.isEmpty || body.isEmpty,
                  body.allSatisfy({ $0.isLetter || $0.isNumber || "+/=\n\r ".contains($0) }) else { return nil }
            return (mimeType, data)
        }
        return (mimeType, Data((body.removingPercentEncoding ?? body).utf8))
    }
}
