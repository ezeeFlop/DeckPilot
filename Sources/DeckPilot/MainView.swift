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
        if !controller.isConnected { return "Branche le boîtier : tes réglages y apparaîtront aussitôt." }
        return "Dépose une application, un fichier ou une image sur une touche. Fais glisser une touche pour la déplacer."
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
                                Text(page.name.isEmpty ? "Sans nom" : page.name)
                            }
                        }
                        .tag(page.id)
                        .contextMenu {
                            Button("Renommer") { rename(page.id) }
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
