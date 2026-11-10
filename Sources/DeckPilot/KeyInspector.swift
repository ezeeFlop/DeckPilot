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

            Section("Contenu vivant") {
                Picker("Afficher", selection: $key.widget) {
                    Text("Rien de particulier").tag(KeyWidget.none)
                    Text("L'heure").tag(KeyWidget.clock)
                    Text("La date").tag(KeyWidget.date)
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
        case .none: return "Aucune"
        case .symbol: return "Symbole"
        case .emoji: return "Emoji"
        case .image: return "Image ou GIF"
        case .app: return "Icône d'application"
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
        panel.message = "Choisis une image ou un GIF animé pour cette case."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            key.icon = .image(try controller.store.importImage(from: url))
            key.iconScale = 1
        } catch {
            controller.message = "Image non copiée : \(error.localizedDescription)"
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

// MARK: Action

private enum ActionKind: String, CaseIterable, Identifiable {
    case none, launchApp, openURL, openFile, shell, hotkey, typeText, media, shortcut, nextPage, previousPage, goToPage, brightness
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Aucune"
        case .launchApp: return "Ouvrir une application"
        case .openURL: return "Ouvrir un site"
        case .openFile: return "Ouvrir un fichier ou un dossier"
        case .shell: return "Lancer une commande"
        case .hotkey: return "Raccourci clavier"
        case .typeText: return "Saisir un texte"
        case .media: return "Son et lecture"
        case .shortcut: return "Lancer un raccourci de l'app Raccourcis"
        case .nextPage: return "Page suivante"
        case .previousPage: return "Page précédente"
        case .goToPage: return "Aller à une page"
        case .brightness: return "Luminosité du boîtier"
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
                Button(path.isEmpty ? "Choisir…" : URL(fileURLWithPath: path).lastPathComponent) {
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
        Button(monitor != nil ? "Tape le raccourci…" : (display.isEmpty ? "Enregistrer" : display)) {
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
        36: "↩", 48: "⇥", 49: "Espace", 51: "⌫", 53: "⎋", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
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
