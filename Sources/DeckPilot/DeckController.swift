import AppKit
import Combine
import DeckCore
import OSLog
import StreamDockKit
import SwiftUI

/// L'horloge des animations. Seules les vues qui l'observent se redessinent quand elle avance.
@MainActor
final class AnimationClock: ObservableObject {
    @Published var time: TimeInterval = 0
}

/// Le cœur de l'application : relie la configuration, le boîtier et l'interface.
@MainActor
final class DeckController: ObservableObject {
    @Published var config: DeckConfiguration {
        didSet { if config != oldValue { scheduleSave() } }
    }
    @Published var currentPageIndex = 0
    @Published var selectedSlot: Int?
    @Published private(set) var isConnected = false
    @Published private(set) var serialNumber: String?
    @Published private(set) var pressedSlots: Set<Int> = []
    @Published var message: String?
    /// Horloge des animations, partagée entre l'écran du Mac et le boîtier. Elle est tenue à part
    /// pour que seules les cases animées se redessinent à chaque image, pas toute la fenêtre.
    let animation = AnimationClock()
    let live = LiveDataEngine()
    let states = KeyStateEngine()
    let plugins = PluginHost()
    private var stateObservation: AnyCancellable?
    private var pluginObservation: AnyCancellable?
    /// Touches d'extension actuellement enfoncées, pour leur annoncer le relâchement même si le boîtier l'oublie.
    private var pluginKeysDown: [Int: String] = [:]
    private var wasAnimating = false
    private var time: TimeInterval { animation.time }
    private var clock: TimeInterval = 0
    @Published private(set) var now = Date()

    let layout = DeckLayout.streamDock293SV3
    let store: ConfigStore
    let icons: IconLibrary

    private let deck = HIDDeck()
    private var sent: [Int: Int] = [:]
    private var ticker: Timer?
    private var saveTask: Task<Void, Never>?
    private var clipboard: KeyConfig?
    private var lastActivity = Date()
    private var isAsleep = false
    private var presses = PressTracker()
    private var history = PageHistory()
    private var switcher = AutoSwitcher(ignoring: [Bundle.main.bundleIdentifier ?? "com.spongetheory.deckpilot"])
    private var renderer: ImageRenderer<KeyFaceView>?
    private var observers: [NSObjectProtocol] = []
    private let start = Date()
    private static let framesPerSecond = 12.0
    private static let log = Logger(subsystem: "com.spongetheory.deckpilot", category: "boitier")

    init(store: ConfigStore = .forLaunch()) {
        self.store = store
        self.icons = IconLibrary(store: store)
        self.config = store.load()
        if config.pages.isEmpty { config.pages = [Page(name: String(localized: "Accueil"))] }

        deck.onConnect = { [weak self] in
            Self.log.notice("boîtier branché")
            self?.deckDidConnect()
        }
        deck.onDisconnect = { [weak self] in
            Self.log.notice("boîtier débranché")
            self?.isConnected = false
            self?.sent.removeAll()
        }
        deck.onInput = { [weak self] input in self?.handle(input) }
        deck.onSendError = { [weak self] code in
            Self.log.error("envoi refusé, code \(String(format: "0x%08X", UInt32(bitPattern: code)), privacy: .public)")
            self?.sent.removeAll()
        }
        deck.start()
        // Un changement d'état d'une touche doit redessiner la fenêtre comme un changement de réglage.
        stateObservation = states.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        pluginObservation = plugins.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        plugins.onSettingsChanged = { [weak self] context, settings in self?.storePluginSettings(settings, for: context) }
        plugins.start(store: store)
        // `-select 13` au lancement ouvre directement le réglage de cette case.
        let requested = UserDefaults.standard.integer(forKey: "select")
        if layout.slots.contains(requested) { selectedSlot = requested }

        let timer = Timer(timeInterval: 1 / Self.framesPerSecond, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleepDeck() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.wakeDeck() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            Task { @MainActor in self?.frontmostChanged(to: bundleID) }
        })
    }

    // MARK: Pages et touches

    var currentPage: Page {
        get { config.pages[min(currentPageIndex, config.pages.count - 1)] }
        set { config.pages[min(currentPageIndex, config.pages.count - 1)] = newValue }
    }

    /// La touche telle qu'elle est réglée (premier état).
    func key(at slot: Int) -> KeyConfig { currentPage.key(at: slot) }

    /// La touche telle qu'elle se présente maintenant, second état compris.
    func shownKey(at slot: Int) -> KeyConfig {
        key(at: slot).resolved(active: states.isActive(page: currentPage.id, slot: slot))
    }

    func setKey(_ key: KeyConfig, at slot: Int) {
        currentPage.keys[slot] = key.isBlank ? nil : key
    }

    func keyBinding(_ slot: Int) -> Binding<KeyConfig> {
        Binding(get: { self.key(at: slot) }, set: { self.setKey($0, at: slot) })
    }

    func goToPage(_ index: Int) {
        guard config.pages.indices.contains(index) else { return }
        currentPageIndex = index
    }

    func addPage() {
        config.pages.append(Page(name: String(localized: "Page \(config.pages.count + 1)")))
        currentPageIndex = config.pages.count - 1
        selectedSlot = nil
    }

    /// Une application vient de passer au premier plan : montre sa page si elle en a une,
    /// ou reviens à la page précédente si on quitte une application qui avait la sienne.
    private func frontmostChanged(to bundleID: String?) {
        guard let target = switcher.frontmostChanged(to: bundleID, pages: config.pages, current: currentPage.id),
              let index = config.pageIndex(withID: target) else { return }
        Self.log.notice("page « \(self.config.pages[index].name, privacy: .public) » affichée pour \(bundleID ?? "?", privacy: .public)")
        goToPage(index)
    }

    /// Transforme une touche en porte d'entrée d'un nouveau dossier, qui contient déjà sa touche « Retour ».
    func createFolder(at slot: Int) {
        var key = self.key(at: slot)
        if key.title.isEmpty { key.title = String(localized: "Dossier") }
        if key.icon == .none { key.icon = .symbol("folder.fill") }
        var folder = Page(name: key.title, isFolder: true)
        folder.keys[layout.slot(row: 0, column: 0)] = KeyConfig(
            title: String(localized: "Retour"), background: DeckColor(hex: "#1F2937")!, icon: .symbol("chevron.backward"),
            action: .back)
        key.action = .goToPage(folder.id)
        setKey(key, at: slot)
        config.pages.append(folder)
    }

    func deletePage(_ id: UUID) {
        guard config.pages.count > 1, let index = config.pageIndex(withID: id) else { return }
        history.forget(id)
        config.pages.remove(at: index)
        currentPageIndex = min(currentPageIndex, config.pages.count - 1)
    }

    func movePages(from source: IndexSet, to destination: Int) {
        let currentID = currentPage.id
        config.pages.move(fromOffsets: source, toOffset: destination)
        currentPageIndex = config.pageIndex(withID: currentID) ?? 0
    }

    func swapKeys(_ a: Int, _ b: Int) {
        guard a != b else { return }
        // Une case d'affichage seul ne peut pas porter d'action.
        var page = currentPage
        page.swapKeys(a, b)
        for slot in [a, b] where !layout.isPressable(slot: slot) {
            if let key = page.keys[slot] { page.keys[slot] = displayOnly(key) }
        }
        currentPage = page
        selectedSlot = b
    }

    /// Une case d'affichage ne s'enfonce pas : ni action, ni bascule à l'appui.
    private func displayOnly(_ key: KeyConfig) -> KeyConfig {
        var key = key
        key.action = .none
        key.alternate?.action = .none
        if key.alternate?.follows == .press { key.alternate = nil }
        return key
    }

    func copyKey(_ slot: Int) { clipboard = key(at: slot) }

    var canPaste: Bool { clipboard != nil }

    func pasteKey(_ slot: Int) {
        guard let key = clipboard else { return }
        setKey(layout.isPressable(slot: slot) ? key : displayOnly(key), at: slot)
    }

    func clearKey(_ slot: Int) { setKey(KeyConfig(), at: slot) }

    /// Pose un fichier déposé sur une case : une application la lance, une image devient l'icône,
    /// tout autre fichier s'ouvre.
    func assign(fileURL url: URL, to slot: Int) {
        var key = self.key(at: slot)
        let pressable = layout.isPressable(slot: slot)
        let imageTypes = ["png", "jpg", "jpeg", "gif", "heic", "tiff", "webp", "bmp", "icns"]
        if url.pathExtension == "app" {
            key.icon = .appIcon(url.path)
            key.iconScale = 0.8
            if key.title.isEmpty { key.title = url.deletingPathExtension().lastPathComponent }
            if pressable { key.action = .launchApp(path: url.path) }
        } else if imageTypes.contains(url.pathExtension.lowercased()) {
            do {
                key.icon = .image(try store.importImage(from: url))
                key.iconScale = 1
            } catch {
                message = String(localized: "Image non copiée : \(error.localizedDescription)")
                return
            }
        } else {
            key.icon = .appIcon(url.path)
            if key.title.isEmpty { key.title = url.deletingPathExtension().lastPathComponent }
            if pressable { key.action = .openFile(path: url.path) }
        }
        setKey(key, at: slot)
        selectedSlot = slot
    }

    // MARK: Boîtier

    func setBrightness(_ percent: Int) {
        config.brightness = min(max(percent, 0), 100)
        deck.send(.brightness(config.brightness))
    }

    /// Éteint proprement l'affichage avant de quitter.
    func shutdown() {
        saveNow()
        plugins.stop()
        guard isConnected else { return }
        deck.send(.disconnect)
        deck.drain()
    }

    private func deckDidConnect() {
        isConnected = true
        serialNumber = deck.serialNumber
        isAsleep = false
        lastActivity = Date()
        sent.removeAll()
        deck.send(.wake)
        deck.send(.brightness(config.brightness))
        deck.send(.clearAll)
        pushFrames()
    }

    private func handle(_ input: DeckInput) {
        lastActivity = Date()
        if isAsleep {
            if input.pressed { wakeDeck() }
            return
        }
        Self.log.notice("touche \(input.key, privacy: .public) \(input.pressed ? "enfoncée" : "relâchée", privacy: .public)")
        guard input.pressed else {
            presses.release(input.key)
            pressedSlots = presses.held(at: clock)
            return
        }
        clock = Date().timeIntervalSince(start)
        presses.press(input.key, at: clock)
        pressedSlots = presses.held(at: clock)
        if let binding = key(at: input.key).plugin {
            // Une touche d'extension ne déclenche rien ici : c'est l'extension qui décide quoi faire de l'appui.
            pluginKeysDown[input.key] = binding.context
            plugins.keyDown(binding.context)
            return
        }
        perform(shownKey(at: input.key).action)
        states.pressed(page: currentPage.id, slot: input.key, key: key(at: input.key))
    }

    func perform(_ action: KeyAction) {
        switch action {
        case .nextPage: goToPage(config.pageIndex(after: currentPageIndex))
        case .previousPage: goToPage(config.pageIndex(before: currentPageIndex))
        case .goToPage(let id):
            guard let index = config.pageIndex(withID: id) else {
                message = String(localized: "Cette page n'existe plus.")
                return
            }
            // On retient d'où l'on vient pour que « Revenir en arrière » nous y ramène.
            if config.pages[index].isFolder, index != currentPageIndex { history.enter(from: currentPage.id) }
            goToPage(index)
        case .back:
            if let origin = history.back(), let index = config.pageIndex(withID: origin) {
                goToPage(index)
            } else if currentPage.isFolder {
                goToPage(config.pageIndex(after: currentPageIndex))
            }
        case .brightness(let delta): setBrightness(config.brightness + delta)
        default:
            if let failure = ActionRunner.run(action) { message = failure }
        }
    }

    private func sleepDeck() {
        guard isConnected, !isAsleep else { return }
        isAsleep = true
        deck.send(.sleep)
    }

    private func wakeDeck() {
        isAsleep = false
        lastActivity = Date()
        guard isConnected else { return }
        sent.removeAll()
        deck.send(.wake)
        deck.send(.brightness(config.brightness))
        pushFrames()
    }

    private func tick() {
        clock = Date().timeIntervalSince(start)
        live.update(page: currentPage, clock: clock)
        states.update(page: currentPage, clock: clock)
        syncPlugins()
        // Un battement de plus après la fin d'une animation, pour que la dernière image montre la valeur d'arrivée.
        let animating = layout.slots.contains { isAnimated(shownKey(at: $0)) } || live.hasRunningTransition(clock: clock)
        if animating || wasAnimating { animation.time = clock }
        wasAnimating = animating
        let held = presses.held(at: clock)
        if held != pressedSlots { pressedSlots = held }
        let date = Date()
        if Calendar.current.component(.minute, from: date) != Calendar.current.component(.minute, from: now) { now = date }
        if config.sleepAfterMinutes > 0, !isAsleep,
           date.timeIntervalSince(lastActivity) > Double(config.sleepAfterMinutes) * 60 {
            sleepDeck()
        }
        pushFrames()
    }

    /// Envoie au boîtier les cases dont le dessin a changé depuis le dernier envoi.
    private func pushFrames() {
        guard isConnected, !isAsleep, !deck.isBusy else { return }
        var changed = false
        for slot in layout.slots {
            let key = shownKey(at: slot)
            let signature = signature(of: key, slot: slot)
            guard sent[slot] != signature else { continue }
            sent[slot] = signature
            guard let image = render(key, slot: slot) else { continue }
            let jpeg = KeyImageEncoder.jpeg(from: image, side: layout.imageSide,
                                            quarterTurnsCounterClockwise: layout.quarterTurnsCounterClockwise)
            deck.setImage(jpeg: jpeg, slot: slot)
            changed = true
        }
        if changed { deck.send(.refresh) }
    }

    // MARK: Extensions

    /// Ce que l'extension d'une touche veut y montrer ; `nil` pour une touche sans extension.
    func pluginDisplay(key: KeyConfig) -> PluginDisplay? {
        guard let binding = key.plugin else { return nil }
        let face = plugins.faces[binding.context]
        return PluginDisplay(image: face?.image ?? plugins.defaultImage(action: binding.action, state: face?.state ?? 0),
                             title: face?.title, flash: face?.flash, isMissing: plugins.action(binding.action) == nil)
    }

    /// Annonce aux extensions les touches qui leur appartiennent sur la page affichée,
    /// et relâche celles dont le boîtier n'a pas signalé le relâchement.
    private func syncPlugins() {
        var visible: [PluginInstance] = []
        for slot in layout.slots where layout.isPressable(slot: slot) {
            guard let binding = key(at: slot).plugin, let position = layout.position(ofSlot: slot) else { continue }
            visible.append(PluginInstance(action: binding.action, context: binding.context, settings: binding.settings,
                                          row: position.row, column: position.column,
                                          state: plugins.faces[binding.context]?.state ?? 0))
        }
        plugins.sync(visible)
        for (slot, context) in pluginKeysDown where !pressedSlots.contains(slot) {
            plugins.keyUp(context)
            pluginKeysDown[slot] = nil
        }
    }

    /// Une extension a changé les réglages d'une de ses touches : on les range dans la configuration.
    private func storePluginSettings(_ settings: JSONValue, for context: String) {
        for pageIndex in config.pages.indices {
            for (slot, key) in config.pages[pageIndex].keys where key.plugin?.context == context && key.plugin?.settings != settings {
                config.pages[pageIndex].keys[slot]?.plugin?.settings = settings
            }
        }
    }

    /// Ce que la donnée vivante d'une case doit montrer maintenant ; `nil` pour une case ordinaire.
    func liveDisplay(slot: Int, key: KeyConfig) -> LiveDisplay? {
        guard let settings = key.live, settings.source != .none else { return nil }
        return live.display(for: .init(page: currentPage.id, slot: slot), clock: time)
            ?? LiveDisplay(text: "…", fraction: 0, level: .normal, history: [], style: settings.style, isPlaceholder: true)
    }

    func isAnimated(_ key: KeyConfig) -> Bool {
        guard key.widget == .none, key.icon != .none else { return false }
        return key.animation != .none || icons.frames(for: key.icon)?.isAnimated == true
    }

    /// Résume tout ce qui détermine le dessin d'une case à cet instant.
    private func signature(of key: KeyConfig, slot: Int) -> Int {
        var hasher = Hasher()
        hasher.combine(key)
        hasher.combine(pressedSlots.contains(slot))
        if let binding = key.plugin {
            hasher.combine(plugins.faces[binding.context]?.revision)
            hasher.combine(plugins.action(binding.action) != nil)
            return hasher.finalize()
        }
        if let display = liveDisplay(slot: slot, key: key) {
            hasher.combine(display)
            return hasher.finalize()
        }
        if key.widget != .none { hasher.combine(now) }
        if key.widget == .none {
            if key.animation != .none, key.icon != .none { hasher.combine(Int(time * Self.framesPerSecond)) }
            if let frames = icons.frames(for: key.icon), frames.isAnimated { hasher.combine(frames.index(at: time)) }
        }
        return hasher.finalize()
    }

    private func render(_ key: KeyConfig, slot: Int) -> CGImage? {
        let side = CGFloat(layout.imageSide)
        let view = KeyFaceView(config: key, side: side, iconImage: icons.image(for: key.icon, at: time), time: time,
                               now: now, pressed: pressedSlots.contains(slot),
                               leadingInset: CGFloat(layout.contentLeadingInset(ofSlot: slot)) / side,
                               live: liveDisplay(slot: slot, key: key), plugin: pluginDisplay(key: key))
        // Un seul moteur de rendu, réutilisé : en créer un par image coûte cher en mémoire et en temps.
        if let renderer {
            renderer.content = view
        } else {
            let fresh = ImageRenderer(content: view)
            fresh.scale = 1
            fresh.isOpaque = true
            renderer = fresh
        }
        return autoreleasepool { renderer?.cgImage }
    }

    // MARK: Enregistrement

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        do {
            try store.save(config)
        } catch {
            message = String(localized: "Configuration non enregistrée : \(error.localizedDescription)")
        }
    }
}
