import DeckCore
import SwiftUI
import UniformTypeIdentifiers

/// Le panneau de droite : tout ce qui se règle sur la case sélectionnée.
struct KeyInspector: View {
    @EnvironmentObject private var controller: DeckController

    var body: some View {
        if let slot = controller.selectedSlot {
            KeyEditor(slot: slot, key: controller.keyBinding(slot), pressable: controller.layout.isPressable(slot: slot))
                .id("\(controller.currentPage.id)-\(slot)")
        } else {
            VStack(spacing: 10) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 34))
                    .foregroundStyle(.tertiary)
                Text("Choisis une touche")
                    .font(.title3.weight(.semibold))
                Text("Clique sur une touche du boîtier pour régler son apparence et ce qu'elle déclenche.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct KeyEditor: View {
    @EnvironmentObject private var controller: DeckController
    let slot: Int
    @Binding var key: KeyConfig
    let pressable: Bool

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    SlotFace(slot: slot, side: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(pressable ? "Touche \(slot)" : "Case d'affichage \(slot)")
                            .font(.headline)
                        Text(pressable ? "S'enfonce et déclenche une action." : "Affiche seulement, ne s'enfonce pas.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Titre") {
                TextField("Texte", text: $key.title, prompt: Text("Aucun"))
                ColorPicker("Couleur", selection: color(\.titleColor), supportsOpacity: false)
                LabeledContent("Taille") { Slider(value: $key.titleSize, in: 9...30) }
                Picker("Position", selection: $key.titlePosition) {
                    Text("Haut").tag(TitlePosition.top)
                    Text("Milieu").tag(TitlePosition.middle)
                    Text("Bas").tag(TitlePosition.bottom)
                }
                .pickerStyle(.segmented)
            }

            // Une case qui montre une donnée, l'heure ou la date n'affiche pas d'icône : sa section est masquée.
            if !showsLiveContent {
                Section("Icône") {
                    IconEditor(key: $key)
                    if key.icon != .none {
                        LabeledContent("Taille") { Slider(value: $key.iconScale, in: 0.2...1) }
                        Picker("Animation", selection: Binding(get: { key.animation }, set: { key.animation = $0 })) {
                            Text("Aucune").tag(KeyAnimation.none)
                            Text("Pulsation").tag(KeyAnimation.pulse)
                            Text("Rotation").tag(KeyAnimation.spin)
                            Text("Rebond").tag(KeyAnimation.bounce)
                            Text("Clignotement").tag(KeyAnimation.blink)
                        }
                    }
                }
            }

            Section("Contenu vivant") {
                LiveEditor(key: $key, slot: slot)
            }

            Section("Fond") {
                ColorPicker("Couleur", selection: color(\.background), supportsOpacity: false)
                Toggle("Dégradé", isOn: Binding(
                    get: { key.backgroundEnd != nil },
                    set: { key.backgroundEnd = $0 ? DeckColor(red: key.background.red * 0.35, green: key.background.green * 0.35,
                                                                 blue: key.background.blue * 0.35) : nil }
                ))
                if key.backgroundEnd != nil {
                    ColorPicker("Couleur du bas", selection: Binding(
                        get: { (key.backgroundEnd ?? .black).color },
                        set: { key.backgroundEnd = DeckColor($0) }
                    ), supportsOpacity: false)
                }
            }

            if pressable {
                Section("Action") {
                    ActionEditor(action: $key.action)
                    Button("Essayer maintenant") { controller.perform(key.action) }
                        .disabled(key.action == .none)
                }
            }

            Section {
                Button("Vider cette case", role: .destructive) { controller.clearKey(slot) }
                    .disabled(key.isBlank)
            }
        }
        .formStyle(.grouped)
    }

    private var showsLiveContent: Bool {
        key.widget != .none || (key.live.map { $0.source != .none } ?? false)
    }

    private func color(_ path: WritableKeyPath<KeyConfig, DeckColor>) -> Binding<Color> {
        Binding(get: { key[keyPath: path].color }, set: { key[keyPath: path] = DeckColor($0) })
    }
}

// MARK: Icône

private enum IconKind: String, CaseIterable, Identifiable {
    case none, symbol, emoji, image, app
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return String(localized: "Aucune")
        case .symbol: return String(localized: "Symbole")
        case .emoji: return String(localized: "Emoji")
        case .image: return String(localized: "Image ou GIF")
        case .app: return String(localized: "Icône d'application")
        }
    }

    init(_ icon: KeyIcon) {
        switch icon {
        case .none: self = .none
        case .symbol: self = .symbol
        case .emoji: self = .emoji
        case .image: self = .image
        case .appIcon: self = .app
        }
    }
}

private struct IconEditor: View {
    @EnvironmentObject private var controller: DeckController
    @Binding var key: KeyConfig
    @State private var showsSymbols = false

    var body: some View {
        Picker("Type", selection: Binding(get: { IconKind(key.icon) }, set: { change(to: $0) })) {
            ForEach(IconKind.allCases) { Text($0.label).tag($0) }
        }
        switch key.icon {
        case .none:
            EmptyView()
        case .symbol(let name):
            LabeledContent("Symbole") {
                Button {
                    showsSymbols = true
                } label: {
                    Label(name, systemImage: name).lineLimit(1)
                }
                .popover(isPresented: $showsSymbols, arrowEdge: .leading) {
                    SymbolPicker(selection: name) { key.icon = .symbol($0) }
                }
            }
            ColorPicker("Couleur", selection: Binding(get: { key.iconColor.color }, set: { key.iconColor = DeckColor($0) }),
                        supportsOpacity: false)
        case .emoji(let text):
            LabeledContent("Emoji") {
                HStack {
                    TextField("", text: Binding(get: { text }, set: { key.icon = .emoji(String($0.suffix(1))) }))
                        .frame(width: 44)
                        .multilineTextAlignment(.center)
                    Button("Choisir…") { NSApp.orderFrontCharacterPalette(nil) }
                }
            }
        case .image:
            Button("Choisir une autre image…") { chooseImage() }
        case .appIcon(let path):
            LabeledContent("Application") {
                Button(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent) { chooseApp() }
            }
        }
    }

    private func change(to kind: IconKind) {
        switch kind {
        case .none: key.icon = .none
        case .symbol: key.icon = .symbol("star.fill")
        case .emoji: key.icon = .emoji("🚀")
        case .image: chooseImage()
        case .app: chooseApp()
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = String(localized: "Choisis une image ou un GIF animé pour cette case.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            key.icon = .image(try controller.store.importImage(from: url))
            key.iconScale = 1
        } catch {
            controller.message = String(localized: "Image non copiée : \(error.localizedDescription)")
        }
    }

    private func chooseApp() {
        guard let url = Panels.chooseApplication() else { return }
        key.icon = .appIcon(url.path)
        key.iconScale = 0.8
    }
}

enum Panels {
    @MainActor static func chooseApplication() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor static func chooseFileOrFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

private struct SymbolPicker: View {
    let selection: String
    let choose: (String) -> Void
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var matches: [String] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return query.isEmpty ? SymbolCatalog.names : SymbolCatalog.names.filter { $0.contains(query) }
    }

    var body: some View {
        VStack(spacing: 10) {
            TextField("Rechercher ou saisir un nom SF Symbols", text: $search)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    let name = search.trimmingCharacters(in: .whitespaces)
                    if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
                        choose(name)
                        dismiss()
                    }
                }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 6), count: 7), spacing: 6) {
                    ForEach(matches, id: \.self) { name in
                        Button {
                            choose(name)
                            dismiss()
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 18))
                                .frame(width: 40, height: 40)
                                .background(name == selection ? Color.accentColor.opacity(0.25) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
            }
            .frame(height: 280)
        }
        .padding(12)
        .frame(width: 350)
    }
}

// MARK: Contenu vivant

private enum LiveKind: String, CaseIterable, Identifiable {
    case none, clock, date, system, http, command
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return String(localized: "Rien de particulier")
        case .clock: return String(localized: "L'heure")
        case .date: return String(localized: "La date")
        case .system: return String(localized: "Une mesure du Mac")
        case .http: return String(localized: "Une donnée lue sur le web")
        case .command: return String(localized: "Le résultat d'une commande")
        }
    }

    init(_ key: KeyConfig) {
        switch key.live?.source {
        case .system: self = .system
        case .http: self = .http
        case .command: self = .command
        case .some(.none), nil:
            switch key.widget {
            case .clock: self = .clock
            case .date: self = .date
            case .none: self = .none
            }
        }
    }
}

private struct LiveEditor: View {
    @EnvironmentObject private var controller: DeckController
    @Binding var key: KeyConfig
    let slot: Int

    private var live: Binding<LiveData> {
        Binding(get: { key.live ?? LiveData() }, set: { key.live = $0 })
    }

    var body: some View {
        Picker("Afficher", selection: Binding(get: { LiveKind(key) }, set: { change(to: $0) })) {
            ForEach(LiveKind.allCases) { Text($0.label).tag($0) }
        }
        if let settings = key.live, settings.source != .none {
            source(settings.source)
            Picker("Rythme", selection: live.interval) {
                Text("Toutes les 2 s").tag(2.0)
                Text("Toutes les 5 s").tag(5.0)
                Text("Toutes les 15 s").tag(15.0)
                Text("Toutes les 30 s").tag(30.0)
                Text("Chaque minute").tag(60.0)
                Text("Toutes les 5 min").tag(300.0)
                Text("Toutes les 15 min").tag(900.0)
            }
            Picker("Forme", selection: live.style) {
                Text("Valeur").tag(LiveStyle.value)
                Text("Anneau").tag(LiveStyle.ring)
                Text("Barre").tag(LiveStyle.bar)
                Text("Courbe").tag(LiveStyle.sparkline)
            }
            if settings.style == .ring || settings.style == .bar {
                LabeledContent("De") {
                    HStack {
                        TextField("", value: live.minimum, format: .number).frame(width: 70)
                        Text("à")
                        TextField("", value: live.maximum, format: .number).frame(width: 70)
                    }
                }
            }
            TextField("Unité", text: live.unit, prompt: Text("%"))
            Stepper("Décimales : \(settings.decimals)", value: live.decimals, in: 0...3)
            ColorPicker("Couleur", selection: Binding(get: { key.iconColor.color }, set: { key.iconColor = DeckColor($0) }),
                        supportsOpacity: false)
            LabeledContent("Orange à partir de") {
                TextField("", value: live.warning, format: .number, prompt: Text("aucun")).frame(width: 90)
            }
            LabeledContent("Rouge à partir de") {
                TextField("", value: live.critical, format: .number, prompt: Text("aucun")).frame(width: 90)
            }
            Toggle("Alerter quand la valeur est basse", isOn: live.alertsWhenBelow)
            LiveStatus(engine: controller.live, key: .init(page: controller.currentPage.id, slot: slot))
        }
    }

    @ViewBuilder private func source(_ source: LiveSource) -> some View {
        switch source {
        case .none:
            EmptyView()
        case .system(let metric):
            Picker("Mesure", selection: Binding(get: { metric }, set: { apply(preset: $0) })) {
                Text("Processeur").tag(SystemMetric.cpu)
                Text("Mémoire").tag(SystemMetric.memory)
                Text("Disque").tag(SystemMetric.disk)
                Text("Batterie").tag(SystemMetric.battery)
            }
        case .http(let url, let path, let headers):
            TextField("Adresse", text: Binding(get: { url }, set: { live.wrappedValue.source = .http(url: $0, jsonPath: path, headers: headers) }),
                      prompt: Text("api.exemple.fr/etat"))
            TextField("Champ JSON", text: Binding(get: { path }, set: { live.wrappedValue.source = .http(url: url, jsonPath: $0, headers: headers) }),
                      prompt: Text("data.items[0].valeur"))
                .font(.system(.body, design: .monospaced))
            TextField("En-têtes", text: Binding(get: { headers }, set: { live.wrappedValue.source = .http(url: url, jsonPath: path, headers: $0) }),
                      prompt: Text("Authorization: Bearer …"), axis: .vertical)
                .lineLimit(1...3)
                .font(.system(.body, design: .monospaced))
                .help("Un en-tête par ligne. Ils sont enregistrés en clair dans le fichier de réglages.")
        case .command(let command):
            TextField("Commande", text: Binding(get: { command }, set: { live.wrappedValue.source = .command($0) }),
                      prompt: Text("date +%S"), axis: .vertical)
                .lineLimit(1...4)
                .font(.system(.body, design: .monospaced))
        }
    }

    private func change(to kind: LiveKind) {
        guard kind != LiveKind(key) else { return }
        switch kind {
        case .none:
            key.widget = .none
            key.live = nil
        case .clock, .date:
            key.widget = kind == .clock ? .clock : .date
            key.live = nil
        case .system:
            key.widget = .none
            apply(preset: .cpu)
        case .http:
            key.widget = .none
            key.live = LiveData(source: .http(url: "", jsonPath: "", headers: ""), interval: 60)
        case .command:
            key.widget = .none
            key.live = LiveData(source: .command(""), interval: 30)
        }
    }

    /// Réglages de départ adaptés à chaque mesure du Mac ; le titre suit tant qu'il n'a pas été personnalisé.
    private func apply(preset metric: SystemMetric) {
        let titles: [SystemMetric: String] = [
            .cpu: String(localized: "CPU"), .memory: String(localized: "Mémoire"),
            .disk: String(localized: "Disque"), .battery: String(localized: "Batterie"),
        ]
        if key.title.isEmpty || titles.values.contains(key.title) { key.title = titles[metric] ?? "" }
        switch metric {
        case .cpu:
            key.live = LiveData(source: .system(.cpu), interval: 2, style: .ring, unit: "%", warning: 75, critical: 90)
        case .memory:
            key.live = LiveData(source: .system(.memory), interval: 5, style: .ring, unit: "%", warning: 80, critical: 92)
        case .disk:
            key.live = LiveData(source: .system(.disk), interval: 60, style: .bar, unit: "%", warning: 85, critical: 95)
        case .battery:
            key.live = LiveData(source: .system(.battery), interval: 60, style: .ring, unit: "%", warning: 30, critical: 15,
                                alertsWhenBelow: true)
        }
    }
}

/// Dernière valeur lue ou dernière erreur, pour savoir si la source répond.
private struct LiveStatus: View {
    @ObservedObject var engine: LiveDataEngine
    let key: LiveDataEngine.Key

    var body: some View {
        if let status = engine.status(for: key) {
            LabeledContent(status.isError ? "Dernière erreur" : "Dernière lecture") {
                Text(status.text)
                    .foregroundStyle(status.isError ? Color.red : Color.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

// MARK: Action

private enum ActionKind: String, CaseIterable, Identifiable {
    case none, launchApp, openURL, openFile, shell, hotkey, typeText, media, shortcut, nextPage, previousPage, goToPage, brightness
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return String(localized: "Aucune")
        case .launchApp: return String(localized: "Ouvrir une application")
        case .openURL: return String(localized: "Ouvrir un site")
        case .openFile: return String(localized: "Ouvrir un fichier ou un dossier")
        case .shell: return String(localized: "Lancer une commande")
        case .hotkey: return String(localized: "Raccourci clavier")
        case .typeText: return String(localized: "Saisir un texte")
        case .media: return String(localized: "Son et lecture")
        case .shortcut: return String(localized: "Lancer un raccourci de l'app Raccourcis")
        case .nextPage: return String(localized: "Page suivante")
        case .previousPage: return String(localized: "Page précédente")
        case .goToPage: return String(localized: "Aller à une page")
        case .brightness: return String(localized: "Luminosité du boîtier")
        }
    }

    init(_ action: KeyAction) {
        switch action {
        case .none: self = .none
        case .launchApp: self = .launchApp
        case .openURL: self = .openURL
        case .openFile: self = .openFile
        case .shell: self = .shell
        case .hotkey: self = .hotkey
        case .typeText: self = .typeText
        case .media: self = .media
        case .shortcut: self = .shortcut
        case .nextPage: self = .nextPage
        case .previousPage: self = .previousPage
        case .goToPage: self = .goToPage
        case .brightness: self = .brightness
        }
    }
}

private struct ActionEditor: View {
    @EnvironmentObject private var controller: DeckController
    @Binding var action: KeyAction

    var body: some View {
        Picker("Quand j'appuie", selection: Binding(get: { ActionKind(action) }, set: { change(to: $0) })) {
            ForEach(ActionKind.allCases) { Text($0.label).tag($0) }
        }
        switch action {
        case .none, .nextPage, .previousPage:
            EmptyView()
        case .launchApp(let path):
            LabeledContent("Application") {
                Button(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent) {
                    if let url = Panels.chooseApplication() { action = .launchApp(path: url.path) }
                }
            }
        case .openURL(let text):
            TextField("Adresse", text: Binding(get: { text }, set: { action = .openURL($0) }), prompt: Text("exemple.fr"))
        case .openFile(let path):
            LabeledContent("Élément") {
                Button(path.isEmpty ? String(localized: "Choisir…") : URL(fileURLWithPath: path).lastPathComponent) {
                    if let url = Panels.chooseFileOrFolder() { action = .openFile(path: url.path) }
                }
            }
        case .shell(let command):
            TextField("Commande", text: Binding(get: { command }, set: { action = .shell(command: $0) }),
                      prompt: Text("say bonjour"), axis: .vertical)
                .lineLimit(1...4)
                .font(.system(.body, design: .monospaced))
        case .hotkey(_, _, let display):
            LabeledContent("Raccourci") {
                HotkeyRecorder(display: display) { keyCode, modifiers, display in
                    action = .hotkey(keyCode: keyCode, modifiers: modifiers, display: display)
                }
            }
        case .typeText(let text):
            TextField("Texte", text: Binding(get: { text }, set: { action = .typeText($0) }), axis: .vertical)
                .lineLimit(1...4)
        case .media(let command):
            Picker("Commande", selection: Binding(get: { command }, set: { action = .media($0) })) {
                Text("Lecture / pause").tag(MediaCommand.playPause)
                Text("Piste suivante").tag(MediaCommand.next)
                Text("Piste précédente").tag(MediaCommand.previous)
                Text("Monter le son").tag(MediaCommand.volumeUp)
                Text("Baisser le son").tag(MediaCommand.volumeDown)
                Text("Couper le son").tag(MediaCommand.mute)
            }
        case .shortcut(let name):
            TextField("Nom du raccourci", text: Binding(get: { name }, set: { action = .shortcut(name: $0) }))
        case .goToPage(let id):
            Picker("Page", selection: Binding(get: { id }, set: { action = .goToPage($0) })) {
                ForEach(controller.config.pages) { Text($0.name).tag($0.id) }
            }
        case .brightness(let delta):
            Picker("Variation", selection: Binding(get: { delta }, set: { action = .brightness(delta: $0) })) {
                Text("Plus lumineux").tag(20)
                Text("Moins lumineux").tag(-20)
            }
        }
    }

    private func change(to kind: ActionKind) {
        guard kind != ActionKind(action) else { return }
        switch kind {
        case .none: action = .none
        case .launchApp:
            if let url = Panels.chooseApplication() { action = .launchApp(path: url.path) }
        case .openURL: action = .openURL("")
        case .openFile:
            if let url = Panels.chooseFileOrFolder() { action = .openFile(path: url.path) }
        case .shell: action = .shell(command: "")
        case .hotkey: action = .hotkey(keyCode: 0, modifiers: 0, display: "")
        case .typeText: action = .typeText("")
        case .media: action = .media(.playPause)
        case .shortcut: action = .shortcut(name: "")
        case .nextPage: action = .nextPage
        case .previousPage: action = .previousPage
        case .goToPage: action = .goToPage(controller.currentPage.id)
        case .brightness: action = .brightness(delta: 20)
        }
    }
}

/// Bouton qui écoute la prochaine combinaison de touches tapée au clavier.
private struct HotkeyRecorder: View {
    let display: String
    let record: (UInt16, UInt64, String) -> Void
    @State private var monitor: Any?

    var body: some View {
        Button(monitor != nil ? String(localized: "Tape le raccourci…") : (display.isEmpty ? String(localized: "Enregistrer") : display)) {
            monitor == nil ? start() : stop()
        }
        .onDisappear { stop() }
    }

    private func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .shift, .control, .option])
            record(event.keyCode, UInt64(flags.rawValue), Self.describe(event, flags))
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static let named: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: String(localized: "Espace"), 51: "⌫", 53: "⎋", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]

    private static func describe(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + (named[event.keyCode] ?? (event.charactersIgnoringModifiers ?? "?").uppercased())
    }
}
