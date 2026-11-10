import Combine
import Foundation
import OSLog
import Sparkle

private let updateLog = Logger(subsystem: "com.spongetheory.deckpilot", category: "mise-a-jour")

/// Mises à jour par Sparkle : vérification périodique du flux publié sur GitHub, téléchargement et installation
/// d'une version signée. L'adresse du flux et la clé publique sont dans Info.plist.
@MainActor
final class SoftwareUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController!
    private var observation: AnyCancellable?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
    }

    /// Vérification demandée par l'utilisateur : Sparkle affiche le résultat, qu'il y ait une mise à jour ou non.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    // MARK: SPUUpdaterDelegate — journal, pour savoir ce que la vérification a donné

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateLog.notice("mise à jour trouvée : \(item.displayVersionString, privacy: .public)")
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        updateLog.notice("aucune mise à jour")
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        updateLog.error("vérification interrompue : \(error.localizedDescription, privacy: .public)")
    }
}
