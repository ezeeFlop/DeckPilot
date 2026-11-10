import Foundation

/// Le chemin suivi pour entrer dans des dossiers, afin d'en ressortir un niveau à la fois.
public struct PageHistory: Sendable {
    private var trail: [UUID] = []

    public init() {}

    /// À appeler en ouvrant un dossier, avec la page que l'on quitte.
    public mutating func enter(from page: UUID) { trail.append(page) }

    /// La page à laquelle revenir, ou `nil` si l'on n'est entré nulle part.
    public mutating func back() -> UUID? { trail.popLast() }

    public mutating func forget(_ page: UUID) { trail.removeAll { $0 == page } }
}

/// Changement de page selon l'application au premier plan : une application qui a sa page la fait apparaître,
/// et la quitter pour une application sans page ramène à la page où l'on était.
public struct AutoSwitcher: Sendable {
    private let ignored: Set<String>
    /// La page à rétablir quand on quittera les applications qui ont la leur.
    private var returnPage: UUID?

    /// - Parameter ignoring: applications dont le passage au premier plan ne change rien (DeckPilot lui-même,
    ///   pour que la page ne saute pas pendant qu'on la règle).
    public init(ignoring: Set<String> = []) {
        ignored = ignoring
    }

    /// Rend la page à afficher, ou `nil` s'il n'y a rien à changer.
    public mutating func frontmostChanged(to bundleID: String?, pages: [Page], current: UUID) -> UUID? {
        if let bundleID, ignored.contains(bundleID) { return nil }
        if let bundleID, let target = pages.first(where: { $0.apps.contains(bundleID) }) {
            guard target.id != current else { return nil }
            if returnPage == nil { returnPage = current }
            return target.id
        }
        guard let home = returnPage else { return nil }
        returnPage = nil
        return pages.contains { $0.id == home } && home != current ? home : nil
    }
}
