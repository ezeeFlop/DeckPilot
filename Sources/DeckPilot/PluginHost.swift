import AppKit
import DeckCore
import OSLog

private let pluginLog = Logger(subsystem: "com.spongetheory.deckpilot", category: "extensions")

/// Ce qu'une extension a demandé d'afficher sur une touche.
struct PluginFace: Equatable {
    enum Flash: Equatable {
        case ok, alert
    }

    var image: CGImage?
    var title: String?
    var state = 0
    var flash: Flash?
    /// Augmente à chaque changement, pour savoir quand redessiner.
    var revision = 0

    static func == (a: PluginFace, b: PluginFace) -> Bool { a.revision == b.revision }
}

/// Accueille les extensions au format Stream Deck : les lance, leur transmet les appuis
/// et applique ce qu'elles demandent d'afficher.
@MainActor
final class PluginHost: ObservableObject {
    struct Plugin: Identifiable {
        let manifest: PluginManifest
        let folder: URL
        /// Identifiant donné à l'extension pour ce lancement.
        let sessionID = UUID().uuidString
        var process: Process?
        var connection: WebSocketServer.ConnectionID?
        var problem: String?
        var restarts = 0
        var id: String { manifest.uuid }
    }

    @Published private(set) var plugins: [Plugin] = []
    @Published private(set) var faces: [String: PluginFace] = [:]
    private(set) var port: UInt16 = 0

    /// Appelé quand une extension (ou sa page de réglage) change les réglages d'une touche.
    var onSettingsChanged: ((_ context: String, _ settings: JSONValue) -> Void)?

    let deviceID = "deckpilot-streamdock-293sv3"
    private let server = WebSocketServer()
    private var store: ConfigStore?
    private var globalSettings: [String: JSONValue] = [:]
    private var instances: [String: PluginInstance] = [:]
    private var appeared: [String: Set<String>] = [:]
    private var inspectors: [String: WebSocketServer.ConnectionID] = [:]
    private var images: [String: CGImage] = [:]
    private var isStopping = false
    private var flashTimers: [String: Timer] = [:]

    // MARK: Démarrage

    func start(store: ConfigStore) {
        self.store = store
        globalSettings = store.loadPluginSettings()
        server.onMessage = { [weak self] id, text in MainActor.assumeIsolated { self?.receive(text, from: id) } }
        server.onClose = { [weak self] id in MainActor.assumeIsolated { self?.connectionClosed(id) } }
        do {
            try server.start { [weak self] port in
                MainActor.assumeIsolated {
                    self?.port = port
                    self?.reload()
                }
            }
        } catch {
            pluginLog.error("serveur des extensions indisponible : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Relit le dossier des extensions et lance celles qui ne tournent pas encore.
    func reload() {
        guard let store, port != 0 else { return }
        let folders = (try? FileManager.default.contentsOfDirectory(at: store.pluginsFolder, includingPropertiesForKeys: nil)) ?? []
        for folder in folders where folder.pathExtension == "sdPlugin" {
            let resolved = folder.resolvingSymlinksInPath()
            guard let data = try? Data(contentsOf: resolved.appendingPathComponent("manifest.json")),
                  let manifest = try? PluginManifest(json: data) else {
                pluginLog.error("manifeste illisible : \(folder.lastPathComponent, privacy: .public)")
                continue
            }
            guard !plugins.contains(where: { $0.manifest.uuid == manifest.uuid }) else { continue }
            plugins.append(Plugin(manifest: manifest, folder: resolved))
            launch(manifest.uuid)
        }
    }

    func stop() {
        isStopping = true
        for plugin in plugins { plugin.process?.terminate() }
        server.stop()
    }

    /// Installe une extension (dossier `.sdPlugin` ou archive `.streamDeckPlugin`) dans le dossier des extensions.
    func install(from source: URL) throws {
        guard let store else { return }
        let destination = store.pluginsFolder
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        if source.pathExtension == "sdPlugin" {
            let target = destination.appendingPathComponent(source.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: source, to: target)
        } else {
            // Une archive .streamDeckPlugin est un zip qui contient le dossier .sdPlugin.
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", source.path, destination.path]
            try unzip.run()
            unzip.waitUntilExit()
            guard unzip.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
        }
        reload()
    }

    // MARK: Ce que l'application demande

    func action(_ uuid: String) -> (plugin: Plugin, action: PluginManifest.Action)? {
        for plugin in plugins {
            if let action = plugin.manifest.actions.first(where: { $0.uuid == uuid }) { return (plugin, action) }
        }
        return nil
    }

    /// Les touches d'extension visibles en ce moment : annonce aux extensions celles qui apparaissent et disparaissent.
    func sync(_ visible: [PluginInstance]) {
        let wanted = PluginInstance.byContext(visible)
        for (context, instance) in instances where wanted[context] == nil {
            send(PluginEvent.willDisappear(instance, device: deviceID), toPluginOf: instance.action, context: context, appearing: false)
            instances[context] = nil
            faces[context] = nil
        }
        for (context, instance) in wanted {
            let known = instances[context]
            instances[context] = instance
            if known == nil {
                faces[context] = PluginFace(state: instance.state)
                send(PluginEvent.willAppear(instance, device: deviceID), toPluginOf: instance.action, context: context, appearing: true)
            } else if known?.settings != instance.settings {
                send(PluginEvent.didReceiveSettings(instance, device: deviceID, id: nil), toPluginOf: instance.action)
            }
        }
    }

    func keyDown(_ context: String) {
        guard let instance = instances[context] else { return }
        send(PluginEvent.keyDown(instance, device: deviceID), toPluginOf: instance.action)
    }

    func keyUp(_ context: String) {
        guard let instance = instances[context] else { return }
        send(PluginEvent.keyUp(instance, device: deviceID), toPluginOf: instance.action)
    }

    /// Image de repos d'une action dans un état donné, telle que la fournit le manifeste.
    func defaultImage(action uuid: String, state: Int) -> CGImage? {
        guard let (plugin, action) = action(uuid), !action.states.isEmpty else { return nil }
        let path = action.states[min(max(state, 0), action.states.count - 1)].image
        return image(atPluginPath: path, in: plugin.folder)
    }

    /// Informations à passer à une page de réglage pour qu'elle se connecte.
    func inspectorParameters(for context: String) -> (url: URL, folder: URL, info: String, actionInfo: String)? {
        guard let instance = instances[context], let (plugin, action) = action(instance.action),
              let path = plugin.manifest.propertyInspectorPath(for: action) else { return nil }
        return (plugin.folder.appendingPathComponent(path), plugin.folder, registrationInfo(for: plugin),
                PluginEvent.actionInfo(instance, device: deviceID))
    }

    // MARK: Lancement

    private func registrationInfo(for plugin: Plugin) -> String {
        PluginEvent.registrationInfo(pluginUUID: plugin.manifest.uuid, pluginVersion: plugin.manifest.version, device: deviceID,
                                     deviceName: "StreamDock 293SV3", columns: 5, rows: 3,
                                     language: Locale.current.language.languageCode?.identifier ?? "en")
    }

    private func launch(_ uuid: String) {
        guard let index = plugins.firstIndex(where: { $0.id == uuid }) else { return }
        let plugin = plugins[index]
        let entry = plugin.folder.appendingPathComponent(plugin.manifest.codePath)
        let process = Process()
        var arguments = ["-port", String(port), "-pluginUUID", plugin.sessionID, "-registerEvent", "registerPlugin",
                         "-info", registrationInfo(for: plugin)]
        if plugin.manifest.runsOnNode {
            guard let node = Self.findNode() else {
                plugins[index].problem = String(localized: "Node.js est introuvable sur ce Mac ; cette extension en a besoin.")
                return
            }
            process.executableURL = node
            arguments.insert(entry.path, at: 0)
        } else if entry.pathExtension.lowercased() == "html" {
            plugins[index].problem = String(localized: "Les extensions écrites en HTML ne sont pas prises en charge.")
            return
        } else {
            process.executableURL = entry
        }
        process.arguments = arguments
        process.currentDirectoryURL = plugin.folder
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.pluginExited(uuid) }
        }
        do {
            try process.run()
            plugins[index].process = process
            plugins[index].problem = nil
            pluginLog.notice("extension lancée : \(plugin.manifest.name, privacy: .public)")
        } catch {
            plugins[index].problem = error.localizedDescription
        }
    }

    /// Une extension qui s'arrête est relancée, cinq fois au plus, pour ne pas tourner en boucle sur une panne.
    private func pluginExited(_ uuid: String) {
        guard !isStopping, let index = plugins.firstIndex(where: { $0.id == uuid }) else { return }
        plugins[index].process = nil
        plugins[index].connection = nil
        appeared[uuid] = nil
        guard plugins[index].restarts < 5 else {
            plugins[index].problem = String(localized: "L'extension s'arrête dès son lancement.")
            return
        }
        plugins[index].restarts += 1
        pluginLog.notice("extension arrêtée, relance : \(self.plugins[index].manifest.name, privacy: .public)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.launch(uuid) }
    }

    private static func findNode() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "\(home)/.volta/bin/node", "/usr/bin/node"]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return URL(fileURLWithPath: found) }
        // Installations par nvm, asdf, etc. : on demande au shell de l'utilisateur.
        let shell = Process()
        let output = Pipe()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-lc", "command -v node"]
        shell.standardOutput = output
        shell.standardError = FileHandle.nullDevice
        guard (try? shell.run()) != nil else { return nil }
        shell.waitUntilExit()
        let path = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return FileManager.default.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    // MARK: Messages reçus

    private func receive(_ text: String, from connection: WebSocketServer.ConnectionID) {
        guard let command = PluginCommand(json: text) else { return }
        switch command {
        case .register(let event, let uuid):
            if event == "registerPlugin", let index = plugins.firstIndex(where: { $0.sessionID == uuid }) {
                plugins[index].connection = connection
                pluginConnected(plugins[index])
            } else if event == "registerPropertyInspector" {
                inspectors[uuid] = connection
                if let instance = instances[uuid] {
                    send(PluginEvent.propertyInspectorDidAppear(action: instance.action, context: uuid, device: deviceID),
                         toPluginOf: instance.action)
                }
            }
        case .setTitle(let context, let title):
            update(context) { $0.title = title }
        case .setImage(let context, let image):
            let decoded = image.flatMap { decodeImage($0, context: context) }
            update(context) { $0.image = decoded }
        case .setState(let context, let state):
            update(context) { $0.state = state }
            instances[context]?.state = state
        case .showOk(let context):
            flash(.ok, on: context)
        case .showAlert(let context):
            flash(.alert, on: context)
        case .setSettings(let context, let settings):
            guard var instance = instances[context] else { return }
            instance.settings = settings
            instances[context] = instance
            onSettingsChanged?(context, settings)
            // Celui qui n'a pas écrit les réglages en est informé : l'extension si la page a écrit, et inversement.
            if inspectors[context] == connection {
                send(PluginEvent.didReceiveSettings(instance, device: deviceID, id: nil), toPluginOf: instance.action)
            } else if let inspector = inspectors[context] {
                server.send(PluginEvent.didReceiveSettings(instance, device: deviceID, id: nil), to: inspector)
            }
        case .getSettings(let context, let id):
            guard let instance = instances[context] else { return }
            server.send(PluginEvent.didReceiveSettings(instance, device: deviceID, id: id), to: connection)
        case .setGlobalSettings(_, let settings):
            guard let plugin = plugin(of: connection) else { return }
            globalSettings[plugin.manifest.uuid] = settings
            try? store?.savePluginSettings(globalSettings)
            let event = PluginEvent.didReceiveGlobalSettings(settings, id: nil)
            if plugin.connection == connection {
                for (context, inspector) in inspectors where instances[context].flatMap({ action($0.action)?.plugin.id }) == plugin.id {
                    server.send(event, to: inspector)
                }
            } else if let pluginConnection = plugin.connection {
                server.send(event, to: pluginConnection)
            }
        case .getGlobalSettings(_, let id):
            guard let plugin = plugin(of: connection) else { return }
            server.send(PluginEvent.didReceiveGlobalSettings(globalSettings[plugin.manifest.uuid] ?? .object([:]), id: id), to: connection)
        case .sendToPropertyInspector(let context, let payload):
            guard let instance = instances[context], let inspector = inspectors[context] else { return }
            server.send(PluginEvent.sendToPropertyInspector(action: instance.action, context: context, payload: payload), to: inspector)
        case .sendToPlugin(let context, let payload):
            guard let instance = instances[context] else { return }
            send(PluginEvent.sendToPlugin(action: instance.action, context: context, payload: payload), toPluginOf: instance.action)
        case .openURL(let text):
            if let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        case .log(let message):
            pluginLog.notice("\(self.plugin(of: connection)?.manifest.name ?? "?", privacy: .public) : \(message, privacy: .public)")
        case .unsupported(let event):
            pluginLog.debug("commande sans objet ici : \(event, privacy: .public)")
        }
    }

    /// L'extension vient de se connecter : on lui présente le boîtier et les touches déjà visibles.
    private func pluginConnected(_ plugin: Plugin) {
        guard let connection = plugin.connection else { return }
        pluginLog.notice("extension connectée : \(plugin.manifest.name, privacy: .public)")
        server.send(PluginEvent.deviceDidConnect(device: deviceID, name: "StreamDock 293SV3", columns: 5, rows: 3), to: connection)
        appeared[plugin.id] = []
        for instance in instances.values where action(instance.action)?.plugin.id == plugin.id {
            server.send(PluginEvent.willAppear(instance, device: deviceID), to: connection)
            appeared[plugin.id]?.insert(instance.context)
        }
    }

    private func connectionClosed(_ connection: WebSocketServer.ConnectionID) {
        for (context, inspector) in inspectors where inspector == connection {
            inspectors[context] = nil
            if let instance = instances[context] {
                send(PluginEvent.propertyInspectorDidDisappear(action: instance.action, context: context, device: deviceID),
                     toPluginOf: instance.action)
            }
        }
        if let index = plugins.firstIndex(where: { $0.connection == connection }) { plugins[index].connection = nil }
    }

    private func plugin(of connection: WebSocketServer.ConnectionID) -> Plugin? {
        if let plugin = plugins.first(where: { $0.connection == connection }) { return plugin }
        guard let context = inspectors.first(where: { $0.value == connection })?.key, let instance = instances[context] else { return nil }
        return action(instance.action)?.plugin
    }

    /// Envoie un événement à l'extension qui possède cette action, si elle est connectée.
    /// Les apparitions sont retenues pour ne pas être annoncées deux fois à la connexion.
    private func send(_ event: String, toPluginOf actionUUID: String, context: String? = nil, appearing: Bool? = nil) {
        guard let plugin = action(actionUUID)?.plugin else { return }
        if let context, let appearing {
            if appearing { appeared[plugin.id, default: []].insert(context) } else { appeared[plugin.id]?.remove(context) }
        }
        guard let connection = plugin.connection else { return }
        server.send(event, to: connection)
    }

    // MARK: Affichage

    private func update(_ context: String, _ change: (inout PluginFace) -> Void) {
        guard instances[context] != nil else { return }
        var face = faces[context] ?? PluginFace()
        change(&face)
        face.revision += 1
        faces[context] = face
    }

    private func flash(_ kind: PluginFace.Flash, on context: String) {
        update(context) { $0.flash = kind }
        flashTimers[context]?.invalidate()
        flashTimers[context] = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.update(context) { $0.flash = nil } }
        }
    }

    /// Une image arrive soit « en ligne » (PNG, JPEG ou SVG), soit comme chemin dans le dossier de l'extension.
    private func decodeImage(_ text: String, context: String) -> CGImage? {
        if let decoded = DataURL.decode(text) { return Self.cgImage(from: decoded.data) }
        guard let instance = instances[context], let plugin = action(instance.action)?.plugin else { return nil }
        return image(atPluginPath: text, in: plugin.folder)
    }

    private func image(atPluginPath path: String, in folder: URL) -> CGImage? {
        let key = folder.path + "|" + path
        if let cached = images[key] { return cached }
        let base = folder.appendingPathComponent(path)
        let candidates = base.pathExtension.isEmpty
            ? ["@2x.png", ".png", ".svg", ".jpg", ".gif"].map { URL(fileURLWithPath: base.path + $0) } : [base]
        for url in candidates {
            if let data = try? Data(contentsOf: url), let image = Self.cgImage(from: data) {
                images[key] = image
                return image
            }
        }
        return nil
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let image = NSImage(data: data) else { return nil }
        // Les SVG n'ont pas de pixels : on les rend à la taille d'une touche en haute définition.
        var rect = CGRect(x: 0, y: 0, width: 288, height: 288)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
