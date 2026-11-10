import Foundation

/// Ce qui fait passer une touche dans son second état.
public enum StateSource: Codable, Hashable, Sendable {
    /// Chaque appui bascule d'un état à l'autre.
    case press
    /// Second état tant que la sortie son du Mac est coupée.
    case muted
    /// Second état tant que l'application située à ce chemin est ouverte.
    case appRunning(path: String)
    /// Second état tant que la commande réussit (code de sortie 0).
    case command(String)
}

/// Le second état d'une touche : son propre aspect et sa propre action.
public struct KeyAlternate: Codable, Hashable, Sendable {
    public var follows: StateSource
    public var title: String
    public var titleColor: DeckColor
    public var titleSize: Double
    public var titlePosition: TitlePosition
    public var background: DeckColor
    public var backgroundEnd: DeckColor?
    public var icon: KeyIcon
    public var iconColor: DeckColor
    public var iconScale: Double
    public var animation: KeyAnimation
    public var action: KeyAction

    /// Un second état part d'une copie de la touche : on ne modifie ensuite que ce qui doit changer.
    public init(follows: StateSource, from key: KeyConfig) {
        self.follows = follows
        title = key.title
        titleColor = key.titleColor
        titleSize = key.titleSize
        titlePosition = key.titlePosition
        background = key.background
        backgroundEnd = key.backgroundEnd
        icon = key.icon
        iconColor = key.iconColor
        iconScale = key.iconScale
        animation = key.animation
        action = key.action
    }

    fileprivate mutating func take(from key: KeyConfig) {
        self = KeyAlternate(follows: follows, from: key)
    }
}

extension KeyConfig {
    /// La touche telle qu'elle se présente dans l'état demandé : aspect et action du second état s'il est actif.
    /// Le contenu vivant est commun aux deux états.
    public func resolved(active: Bool) -> KeyConfig {
        guard active, let alternate else { return self }
        var key = self
        key.title = alternate.title
        key.titleColor = alternate.titleColor
        key.titleSize = alternate.titleSize
        key.titlePosition = alternate.titlePosition
        key.background = alternate.background
        key.backgroundEnd = alternate.backgroundEnd
        key.icon = alternate.icon
        key.iconColor = alternate.iconColor
        key.iconScale = alternate.iconScale
        key.animation = alternate.animation
        key.action = alternate.action
        return key
    }

    /// Range dans le second état l'aspect et l'action d'une touche modifiée, sans toucher au premier état.
    public mutating func updateAlternate(from edited: KeyConfig) {
        alternate?.take(from: edited)
    }
}

/// Mémoire des touches qui basculent à chaque appui.
public struct PressToggles: Sendable {
    private struct Key: Hashable {
        let page: UUID
        let slot: Int
    }

    private var on: Set<Key> = []

    public init() {}

    public func isOn(page: UUID, slot: Int) -> Bool { on.contains(Key(page: page, slot: slot)) }

    public mutating func flip(page: UUID, slot: Int) {
        let key = Key(page: page, slot: slot)
        if on.contains(key) { on.remove(key) } else { on.insert(key) }
    }
}
