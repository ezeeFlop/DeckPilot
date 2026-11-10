import DeckCore
import Foundation
import OSLog

private let liveLog = Logger(subsystem: "com.spongetheory.deckpilot", category: "donnees")

/// Ce qu'une case vivante doit montrer à un instant donné.
struct LiveDisplay: Hashable {
    var text: String
    var fraction: Double
    var level: LiveLevel
    var history: [Double]
    var style: LiveStyle
    /// Vrai tant qu'aucune valeur n'a été lue, ou après une lecture en échec.
    var isPlaceholder: Bool
}

/// Lit les données vivantes des cases de la page affichée, chacune à son rythme, et garde leur dernier état.
@MainActor
final class LiveDataEngine: ObservableObject {
    struct Key: Hashable {
        let page: UUID
        let slot: Int
    }

    struct State {
        var settings: LiveData
        var value: LiveValue?
        var history = LiveHistory()
        var transition: LiveTransition?
        var error: String?
        var nextRead: TimeInterval = 0
        var isReading = false
    }

    @Published private(set) var states: [Key: State] = [:]
    private let metrics = SystemMetrics()
    /// Heure du dernier battement : une lecture qui aboutit démarre sa transition à cet instant.
    private var clock: TimeInterval = 0

    /// À appeler à chaque battement : lance les lectures arrivées à échéance pour la page affichée
    /// et oublie les cases qui ne sont plus vivantes.
    func update(page: Page, clock: TimeInterval) {
        self.clock = clock
        var wanted: Set<Key> = []
        for (slot, config) in page.keys {
            guard let settings = config.live, settings.source != .none else { continue }
            let key = Key(page: page.id, slot: slot)
            wanted.insert(key)
            if states[key]?.settings.source != settings.source {
                states[key] = State(settings: settings)
            } else if states[key]?.settings != settings {
                states[key]?.settings = settings
            }
            guard let state = states[key], !state.isReading, clock >= state.nextRead else { continue }
            states[key]?.isReading = true
            states[key]?.nextRead = clock + max(settings.interval, 2)
            read(settings.source, for: key)
        }
        for key in states.keys where !wanted.contains(key) { states[key] = nil }
    }

    func display(for key: Key, clock: TimeInterval) -> LiveDisplay? {
        guard let state = states[key] else { return nil }
        let settings = state.settings
        guard let value = state.value else {
            return LiveDisplay(text: state.error == nil ? "…" : "!", fraction: 0, level: state.error == nil ? .normal : .critical,
                               history: [], style: settings.style, isPlaceholder: true)
        }
        guard let target = value.number else {
            return LiveDisplay(text: value.text, fraction: 0, level: .normal, history: [], style: .value, isPlaceholder: false)
        }
        let shown = state.transition?.value(at: clock) ?? target
        return LiveDisplay(text: settings.format(shown), fraction: settings.fraction(of: shown), level: settings.level(of: target),
                           history: state.history.values, style: settings.style, isPlaceholder: false)
    }

    func isTransitioning(_ key: Key, clock: TimeInterval) -> Bool {
        states[key]?.transition?.isRunning(at: clock) ?? false
    }

    func hasRunningTransition(clock: TimeInterval) -> Bool {
        states.values.contains { $0.transition?.isRunning(at: clock) ?? false }
    }

    /// Dernier résultat lisible, pour le panneau de réglage.
    func status(for key: Key) -> (text: String, isError: Bool)? {
        guard let state = states[key] else { return nil }
        if let error = state.error { return (error, true) }
        guard let value = state.value else { return nil }
        return (value.number.map { state.settings.format($0) } ?? value.text, false)
    }

    // MARK: Lectures

    private func read(_ source: LiveSource, for key: Key) {
        switch source {
        case .none:
            break
        case .system(let metric):
            if let percent = metrics.read(metric) {
                finish(key, .success(LiveValue(number: percent)))
            } else {
                finish(key, .failure(.message(String(localized: "Mesure indisponible sur ce Mac"))))
            }
        case .http(let url, let jsonPath, let headers):
            Task { [weak self] in
                let result = await Self.fetch(url: url, jsonPath: jsonPath, headers: headers)
                self?.finish(key, result)
            }
        case .command(let command):
            Task { [weak self] in
                let result = await Self.run(command: command)
                self?.finish(key, result)
            }
        }
    }

    private func finish(_ key: Key, _ result: Result<LiveValue, ReadError>) {
        guard var state = states[key] else { return }
        state.isReading = false
        switch result {
        case .success(let value):
            if let number = value.number {
                let from = state.transition?.value(at: clock) ?? state.value?.number ?? number
                state.transition = LiveTransition(from: from, to: number, startedAt: clock)
                state.history.append(number)
            } else {
                state.transition = nil
            }
            state.value = value
            state.error = nil
        case .failure(let error):
            state.error = error.text
            liveLog.notice("lecture en échec, case \(key.slot, privacy: .public) : \(error.text, privacy: .public)")
        }
        states[key] = state
    }

    enum ReadError: Error {
        case message(String)
        var text: String {
            switch self {
            case .message(let text): return text
            }
        }
    }

    private nonisolated static func fetch(url text: String, jsonPath: String, headers: String) async -> Result<LiveValue, ReadError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed), url.host != nil else {
            return .failure(.message(String(localized: "Adresse invalide")))
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/json, text/plain;q=0.9, */*;q=0.5", forHTTPHeaderField: "Accept")
        for line in headers.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            request.setValue(parts[1].trimmingCharacters(in: .whitespaces),
                             forHTTPHeaderField: parts[0].trimmingCharacters(in: .whitespaces))
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .failure(.message(String(localized: "Réponse HTTP \(http.statusCode)")))
            }
            guard let value = JSONPath.extract(jsonPath, from: data) else {
                return .failure(.message(String(localized: "Champ introuvable dans la réponse")))
            }
            return .success(value)
        } catch {
            return .failure(.message(error.localizedDescription))
        }
    }

    private nonisolated static func run(command: String) async -> Result<LiveValue, ReadError> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", command]
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: .failure(.message(error.localizedDescription)))
                    return
                }
                // Une commande qui ne rend pas la main est arrêtée au bout de dix secondes.
                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: watchdog)
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()
                let value = LiveValue(text: String(data: data, encoding: .utf8) ?? "")
                if value.text.isEmpty {
                    continuation.resume(returning: .failure(.message(String(localized: "La commande n'a rien affiché"))))
                } else {
                    continuation.resume(returning: .success(value))
                }
            }
        }
    }
}
