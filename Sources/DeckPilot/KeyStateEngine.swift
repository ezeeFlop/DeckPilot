import AppKit
import DeckCore

/// Sait, pour chaque touche à deux états de la page affichée, lequel est actif.
/// Les états qui suivent le Mac (son coupé, application ouverte) sont relus chaque seconde,
/// les commandes toutes les cinq secondes.
@MainActor
final class KeyStateEngine: ObservableObject {
    typealias Key = LiveDataEngine.Key

    @Published private(set) var active: Set<Key> = []

    private var toggles = PressToggles()
    private var isMuted = false
    private var runningApps: Set<String> = []
    private var nextSystemRead: TimeInterval = 0
    private var commandResults: [Key: Bool] = [:]
    private var commandNextRun: [Key: TimeInterval] = [:]
    private var commandsRunning: Set<Key> = []
    private lazy var muteScript = NSAppleScript(source: "output muted of (get volume settings)")

    func isActive(page: UUID, slot: Int) -> Bool { active.contains(Key(page: page, slot: slot)) }

    func update(page: Page, clock: TimeInterval) {
        let sources = page.keys.compactMapValues { $0.alternate?.follows }
        if clock >= nextSystemRead {
            nextSystemRead = clock + 1
            if sources.values.contains(.muted) { isMuted = readMuted() }
            if sources.values.contains(where: { if case .appRunning = $0 { return true } else { return false } }) {
                runningApps = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.resolvingSymlinksInPath().path })
            }
        }
        var now: Set<Key> = []
        for (slot, source) in sources {
            let key = Key(page: page.id, slot: slot)
            let on: Bool
            switch source {
            case .press:
                on = toggles.isOn(page: page.id, slot: slot)
            case .muted:
                on = isMuted
            case .appRunning(let path):
                on = runningApps.contains(URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
            case .command(let command):
                on = commandResults[key] ?? false
                if !commandsRunning.contains(key), clock >= commandNextRun[key, default: 0] {
                    commandNextRun[key] = clock + 5
                    run(command, for: key)
                }
            }
            if on { now.insert(key) }
        }
        if now != active { active = now }
    }

    /// À appeler après un appui : bascule la touche si elle suit les appuis, et fait relire les états du Mac
    /// sans attendre, pour que l'aspect suive aussitôt l'action qui vient de partir.
    func pressed(page: UUID, slot: Int, key: KeyConfig) {
        guard let source = key.alternate?.follows else { return }
        if source == .press { toggles.flip(page: page, slot: slot) }
        nextSystemRead = 0
        commandNextRun[Key(page: page, slot: slot)] = 0
    }

    private func readMuted() -> Bool {
        var error: NSDictionary?
        return muteScript?.executeAndReturnError(&error).booleanValue ?? false
    }

    private func run(_ command: String, for key: Key) {
        commandsRunning.insert(key)
        Task { [weak self] in
            let succeeded = await Self.succeeds(command)
            self?.commandsRunning.remove(key)
            self?.commandResults[key] = succeeded
        }
    }

    private nonisolated static func succeeds(_ command: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", command]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                guard (try? process.run()) != nil else {
                    continuation.resume(returning: false)
                    return
                }
                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 4, execute: watchdog)
                process.waitUntilExit()
                watchdog.cancel()
                continuation.resume(returning: process.terminationStatus == 0)
            }
        }
    }
}
