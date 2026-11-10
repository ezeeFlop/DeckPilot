import ServiceManagement
import SwiftUI

@main
struct DeckPilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var controller = DeckController()
    @StateObject private var updater = SoftwareUpdater()

    var body: some Scene {
        Window("DeckPilot", id: "main") {
            MainView()
                .environmentObject(controller)
                .frame(minWidth: 980, minHeight: 600)
                .onAppear { delegate.controller = controller }
        }
        .defaultSize(width: 1180, height: 700)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Rechercher les mises à jour…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }

        MenuBarExtra("DeckPilot", systemImage: "square.grid.3x2.fill") {
            MenuContent()
                .environmentObject(controller)
                .environmentObject(updater)
                .onAppear { delegate.controller = controller }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: DeckController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Avant macOS 26, le système ne découpe pas l'icône : on montre dans le Dock la version aux coins arrondis.
        if #unavailable(macOS 26), let url = Bundle.main.url(forResource: "AppIcon-legacy", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { controller?.shutdown() }
    }
}

/// Le menu de la barre des menus : le boîtier continue de fonctionner fenêtre fermée.
private struct MenuContent: View {
    @EnvironmentObject private var controller: DeckController
    @EnvironmentObject private var updater: SoftwareUpdater
    @Environment(\.openWindow) private var openWindow
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Text(controller.isConnected ? "Boîtier connecté" : "Boîtier non branché")
        Divider()
        Button("Configurer les touches…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Menu("Page") {
            ForEach(Array(controller.config.pages.enumerated()), id: \.element.id) { index, page in
                Button {
                    controller.goToPage(index)
                } label: {
                    if index == controller.currentPageIndex { Label(page.name, systemImage: "checkmark") } else { Text(page.name) }
                }
            }
        }
        Menu("Luminosité") {
            ForEach([20, 40, 60, 80, 100], id: \.self) { percent in
                Button("\(percent) %") { controller.setBrightness(percent) }
            }
        }
        Divider()
        Toggle("Ouvrir à l'ouverture de session", isOn: $launchesAtLogin)
            .onChange(of: launchesAtLogin) { _, enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    controller.message = String(localized: "Réglage non appliqué : \(error.localizedDescription)")
                    launchesAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
        Button("Rechercher les mises à jour…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
        Toggle("Vérifier les mises à jour automatiquement", isOn: Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
        ))
        Divider()
        Button("Quitter DeckPilot") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
