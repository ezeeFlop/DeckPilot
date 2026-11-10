import Foundation

/// Exécute une suite d'actions : chaque étape à son tour, une pause entre deux étapes.
/// L'exécution réelle et l'attente sont fournies par l'appelant, ce qui laisse la logique vérifiable.
public enum SequenceRunner {
    /// - Parameters:
    ///   - perform: exécute une étape et dit si elle a réussi ; un échec arrête la suite, pour ne pas agir
    ///     sur un état qui n'est pas celui attendu.
    ///   - sleep: attend le nombre de secondes donné.
    /// - Returns: vrai si toutes les étapes ont été exécutées.
    @discardableResult
    public static func run(_ steps: [KeyAction], pause: Double,
                           perform: (KeyAction) async -> Bool,
                           sleep: (Double) async -> Void) async -> Bool {
        for (index, step) in steps.enumerated() {
            if index > 0, pause > 0 { await sleep(pause) }
            if Task.isCancelled { return false }
            guard await perform(step) else { return false }
        }
        return true
    }
}
