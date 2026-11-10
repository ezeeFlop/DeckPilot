import AppKit
import DeckCore

/// Exécute les actions qui agissent sur le Mac. Les actions qui concernent le boîtier lui-même
/// (pages, luminosité) sont traitées par `DeckController`.
@MainActor
enum ActionRunner {
    /// Rend un message d'erreur lisible, ou `nil` si l'action est partie.
    static func run(_ action: KeyAction) -> String? {
        switch action {
        case .none, .nextPage, .previousPage, .goToPage, .brightness:
            return nil
        case .launchApp(let path):
            guard FileManager.default.fileExists(atPath: path) else { return "Application introuvable : \(path)" }
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
            return nil
        case .openURL(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let withScheme = trimmed.contains("://") || trimmed.hasPrefix("mailto:") ? trimmed : "https://" + trimmed
            guard let url = URL(string: withScheme) else { return "Adresse invalide : \(text)" }
            NSWorkspace.shared.open(url)
            return nil
        case .openFile(let path):
            guard FileManager.default.fileExists(atPath: path) else { return "Fichier introuvable : \(path)" }
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return nil
        case .shell(let command):
            return launch("/bin/zsh", ["-lc", command])
        case .shortcut(let name):
            return launch("/usr/bin/shortcuts", ["run", name])
        case .hotkey(let keyCode, let modifiers, _):
            guard canPostEvents() else { return accessibilityMessage }
            let flags = CGEventFlags(rawValue: modifiers)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down)
                event?.flags = flags
                event?.post(tap: .cghidEventTap)
            }
            return nil
        case .typeText(let text):
            guard canPostEvents() else { return accessibilityMessage }
            for character in text {
                let units = Array(String(character).utf16)
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
                    event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                    event?.post(tap: .cghidEventTap)
                }
            }
            return nil
        case .media(let command):
            return media(command)
        }
    }

    private static let accessibilityMessage =
        "Autorise DeckPilot dans Réglages Système › Confidentialité et sécurité › Accessibilité, puis réessaie."

    private static func canPostEvents() -> Bool {
        if CGPreflightPostEventAccess() { return true }
        CGRequestPostEventAccess()
        return false
    }

    private static func launch(_ tool: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return nil
        } catch {
            return "Lancement impossible : \(error.localizedDescription)"
        }
    }

    private static func media(_ command: MediaCommand) -> String? {
        switch command {
        case .volumeUp:
            return appleScript("set volume output volume ((output volume of (get volume settings)) + 6)")
        case .volumeDown:
            return appleScript("set volume output volume ((output volume of (get volume settings)) - 6)")
        case .mute:
            return appleScript("set volume output muted (not (output muted of (get volume settings)))")
        case .playPause: return mediaKey(16)
        case .next: return mediaKey(17)
        case .previous: return mediaKey(18)
        }
    }

    private static func appleScript(_ source: String) -> String? {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error.map { "Commande refusée : \($0[NSAppleScript.errorMessage] ?? "erreur inconnue")" }
    }

    /// Touche multimédia du clavier (codes `NX_KEYTYPE_*`).
    private static func mediaKey(_ key: Int) -> String? {
        guard canPostEvents() else { return accessibilityMessage }
        for (state, flags) in [(0xA, 0xA00), (0xB, 0xB00)] {
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                data1: (key << 16) | (state << 8), data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        return nil
    }
}
