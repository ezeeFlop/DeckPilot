import DeckCore
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var controller: DeckController

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            HStack(spacing: 0) {
                stage
                Divider()
                KeyInspector()
                    .frame(width: 320)
            }
        }
        .navigationTitle(controller.currentPage.name)
    }

    private var stage: some View {
        VStack(spacing: 18) {
            DeckView()
                .frame(maxWidth: 900)
            Text(hint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color(nsColor: .underPageBackgroundColor)
                .ignoresSafeArea()
                .onTapGesture { controller.selectedSlot = nil }
        }
        .overlay(alignment: .bottom) {
            if let message = controller.message {
                MessageBanner(text: message) { controller.message = nil }
                    .padding(16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: controller.message)
    }

    private var hint: String {
        if !controller.isConnected { return String(localized: "Branche le boîtier : tes réglages y apparaîtront aussitôt.") }
        return String(localized: "Dépose une application, un fichier ou une image sur une touche. Fais glisser une touche pour la déplacer.")
    }
}

private struct MessageBanner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button("Fermer", action: dismiss).buttonStyle(.borderless)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .frame(maxWidth: 560)
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var controller: DeckController
    @State private var renaming: UUID?
    @State private var editingApps: UUID?
    @FocusState private var nameFieldFocused: Bool

    private func rename(_ id: UUID) {
        renaming = id
        DispatchQueue.main.async { nameFieldFocused = true }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { controller.currentPage.id },
                set: { id in if let id, let index = controller.config.pageIndex(withID: id) { controller.goToPage(index) } }
            )) {
                Section("Pages") {
                    ForEach($controller.config.pages) { $page in
                        Group {
                            if renaming == page.id {
                                TextField("Nom de la page", text: $page.name)
                                    .focused($nameFieldFocused)
                                    .onSubmit { renaming = nil }
                                    .onChange(of: nameFieldFocused) { _, focused in if !focused { renaming = nil } }
                            } else {
                                HStack(spacing: 6) {
                                    Label(page.name.isEmpty ? String(localized: "Sans nom") : page.name,
                                          systemImage: page.isFolder ? "folder" : "square.grid.3x2")
                                    Spacer(minLength: 0)
                                    if !page.apps.isEmpty {
                                        Image(systemName: "macwindow.badge.plus")
                                            .foregroundStyle(.secondary)
                                            .help("S'affiche d'elle-même quand ses applications passent au premier plan")
                                    }
                                }
                            }
                        }
                        .tag(page.id)
                        .popover(isPresented: Binding(get: { editingApps == page.id }, set: { if !$0 { editingApps = nil } }),
                                 arrowEdge: .trailing) {
                            PageAppsEditor(page: $page)
                        }
                        .contextMenu {
                            Button("Renommer") { rename(page.id) }
                            Button("Applications associées…") { editingApps = page.id }
                            Button(page.isFolder ? "En faire une page ordinaire" : "En faire un dossier") { page.isFolder.toggle() }
                            Button("Supprimer la page", role: .destructive) { controller.deletePage(page.id) }
                                .disabled(controller.config.pages.count < 2)
                        }
                    }
                    .onMove { controller.movePages(from: $0, to: $1) }
                }
            }
            Button {
                controller.addPage()
                rename(controller.currentPage.id)
            } label: {
                Label("Ajouter une page", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
            deviceSettings
        }
    }

    private var deviceSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle()
                    .fill(controller.isConnected ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(controller.isConnected ? "Boîtier connecté" : "Boîtier non branché")
                    .font(.callout.weight(.medium))
            }
            HStack(spacing: 8) {
                Image(systemName: "sun.min").foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { Double(controller.config.brightness) },
                    set: { controller.setBrightness(Int($0)) }
                ), in: 5...100)
                Image(systemName: "sun.max").foregroundStyle(.secondary)
            }
            .help("Luminosité des écrans du boîtier")
            Picker("Mise en veille", selection: $controller.config.sleepAfterMinutes) {
                Text("Jamais").tag(0)
                Text("Après 5 min").tag(5)
                Text("Après 15 min").tag(15)
                Text("Après 1 h").tag(60)
            }
            .font(.callout)
            .help("Éteint les écrans du boîtier quand aucune touche n'a été pressée depuis ce délai")
        }
        .padding(14)
    }
}

/// Les applications qui font apparaître une page d'elles-mêmes en passant au premier plan.
private struct PageAppsEditor: View {
    @Binding var page: Page

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Afficher « \(page.name) » quand l'une de ces applications passe au premier plan")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if page.apps.isEmpty {
                Text("Aucune application pour l'instant.")
                    .foregroundStyle(.secondary)
            }
            ForEach(page.apps, id: \.self) { bundleID in
                HStack(spacing: 8) {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 22, height: 22)
                        Text(url.deletingPathExtension().lastPathComponent)
                    } else {
                        Image(systemName: "questionmark.app")
                            .frame(width: 22, height: 22)
                        Text(bundleID)
                    }
                    Spacer()
                    Button("Retirer") { page.apps.removeAll { $0 == bundleID } }
                        .buttonStyle(.borderless)
                }
            }
            Button("Ajouter une application…") {
                guard let url = Panels.chooseApplication(), let bundleID = Bundle(url: url)?.bundleIdentifier,
                      !page.apps.contains(bundleID) else { return }
                page.apps.append(bundleID)
            }
            Text("En quittant ces applications, le boîtier revient à la page où il était.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 340)
    }
}
