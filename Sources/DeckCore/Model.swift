import Foundation

public struct DeckColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    public var hex: String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    public static let black = DeckColor(red: 0, green: 0, blue: 0)
    public static let white = DeckColor(red: 1, green: 1, blue: 1)
}

public enum KeyIcon: Codable, Hashable, Sendable {
    case none
    /// Nom d'un symbole SF Symbols.
    case symbol(String)
    case emoji(String)
    /// Nom d'un fichier du dossier d'images de l'application (PNG, JPEG, GIF animé…).
    case image(String)
    /// Icône de l'application située à ce chemin.
    case appIcon(String)
}

public enum KeyAnimation: String, Codable, CaseIterable, Sendable {
    case none, pulse, spin, bounce, blink
}

public enum KeyWidget: String, Codable, CaseIterable, Sendable {
    case none, clock, date
}

public enum TitlePosition: String, Codable, CaseIterable, Sendable {
    case top, middle, bottom
}

public enum MediaCommand: String, Codable, CaseIterable, Sendable {
    case playPause, next, previous, volumeUp, volumeDown, mute
}

public enum KeyAction: Codable, Hashable, Sendable {
    case none
    case launchApp(path: String)
    case openURL(String)
    case openFile(path: String)
    case shell(command: String)
    /// `modifiers` suit les drapeaux de `CGEventFlags` ; `display` est le libellé lisible (« ⌘⇧4 »).
    case hotkey(keyCode: UInt16, modifiers: UInt64, display: String)
    case typeText(String)
    case media(MediaCommand)
    case shortcut(name: String)
    case nextPage
    case previousPage
    case goToPage(UUID)
    /// Revient à la page d'où l'on est entré dans un dossier.
    case back
    case brightness(delta: Int)
}

public struct KeyConfig: Codable, Hashable, Sendable {
    public var title: String
    public var titleColor: DeckColor
    public var titleSize: Double
    public var titlePosition: TitlePosition
    public var background: DeckColor
    /// Seconde couleur d'un dégradé vertical ; `nil` pour un fond uni.
    public var backgroundEnd: DeckColor?
    public var icon: KeyIcon
    public var iconColor: DeckColor
    /// Part du côté de la case occupée par l'icône (0,2 à 1).
    public var iconScale: Double
    public var animation: KeyAnimation
    public var widget: KeyWidget
    public var action: KeyAction
    /// Donnée vivante affichée à la place de l'icône ; `nil` pour une case ordinaire.
    public var live: LiveData?
    /// Second état de la touche ; `nil` pour une touche à un seul état.
    public var alternate: KeyAlternate?

    public init(title: String = "", titleColor: DeckColor = .white, titleSize: Double = 15,
                titlePosition: TitlePosition = .bottom, background: DeckColor = .black,
                backgroundEnd: DeckColor? = nil, icon: KeyIcon = .none, iconColor: DeckColor = .white,
                iconScale: Double = 0.55, animation: KeyAnimation = .none, widget: KeyWidget = .none,
                action: KeyAction = .none, live: LiveData? = nil) {
        self.title = title
        self.titleColor = titleColor
        self.titleSize = titleSize
        self.titlePosition = titlePosition
        self.background = background
        self.backgroundEnd = backgroundEnd
        self.icon = icon
        self.iconColor = iconColor
        self.iconScale = iconScale
        self.animation = animation
        self.widget = widget
        self.action = action
        self.live = live
    }

    /// Vrai pour une case que l'utilisateur n'a pas touchée.
    public var isBlank: Bool { self == KeyConfig() }
}

public struct Page: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Cases configurées, par numéro matériel (1 à 18). Une case absente est vide.
    public var keys: [Int: KeyConfig]
    /// Un dossier s'ouvre depuis une touche et reste hors du défilement « page suivante / précédente ».
    public var isFolder: Bool
    /// Identifiants des applications qui font apparaître cette page quand elles passent au premier plan.
    public var apps: [String]

    public init(id: UUID = UUID(), name: String, keys: [Int: KeyConfig] = [:], isFolder: Bool = false, apps: [String] = []) {
        self.id = id
        self.name = name
        self.keys = keys
        self.isFolder = isFolder
        self.apps = apps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        keys = try container.decode([Int: KeyConfig].self, forKey: .keys)
        // Absents des configurations écrites avant la version 0.4.
        isFolder = try container.decodeIfPresent(Bool.self, forKey: .isFolder) ?? false
        apps = try container.decodeIfPresent([String].self, forKey: .apps) ?? []
    }

    public func key(at slot: Int) -> KeyConfig { keys[slot] ?? KeyConfig() }

    public mutating func swapKeys(_ a: Int, _ b: Int) {
        let (first, second) = (keys[a], keys[b])
        keys[a] = second
        keys[b] = first
    }
}

public struct DeckConfiguration: Codable, Hashable, Sendable {
    public var brightness: Int
    public var pages: [Page]
    /// Minutes sans appui avant d'éteindre l'écran ; 0 pour ne jamais l'éteindre.
    public var sleepAfterMinutes: Int

    public init(brightness: Int = 80, pages: [Page], sleepAfterMinutes: Int = 0) {
        self.brightness = brightness
        self.pages = pages
        self.sleepAfterMinutes = sleepAfterMinutes
    }

    /// Page ordinaire suivante, en boucle ; les dossiers sont sautés.
    public func pageIndex(after index: Int) -> Int { ordinaryPageIndex(from: index, step: 1) }

    /// Page ordinaire précédente, en boucle ; les dossiers sont sautés.
    public func pageIndex(before index: Int) -> Int { ordinaryPageIndex(from: index, step: -1) }

    private func ordinaryPageIndex(from index: Int, step: Int) -> Int {
        guard !pages.isEmpty else { return 0 }
        for offset in 1...pages.count {
            let candidate = ((index + step * offset) % pages.count + pages.count) % pages.count
            if !pages[candidate].isFolder { return candidate }
        }
        return index
    }

    public func pageIndex(withID id: UUID) -> Int? { pages.firstIndex { $0.id == id } }

    /// Configuration proposée au premier lancement : quelques touches utiles pour montrer ce qui est possible.
    public static var starter: DeckConfiguration {
        let night = DeckColor(hex: "#14213D")!
        var page = Page(name: String(localized: "Accueil"))
        page.keys[13] = KeyConfig(title: "Safari", background: night, icon: .appIcon("/Applications/Safari.app"), iconScale: 0.8,
                                  action: .launchApp(path: "/Applications/Safari.app"))
        page.keys[10] = KeyConfig(title: "Terminal", background: night,
                                  icon: .appIcon("/System/Applications/Utilities/Terminal.app"), iconScale: 0.8,
                                  action: .launchApp(path: "/System/Applications/Utilities/Terminal.app"))
        page.keys[7] = KeyConfig(title: String(localized: "Réglages"), background: night,
                                 icon: .appIcon("/System/Applications/System Settings.app"), iconScale: 0.8,
                                 action: .launchApp(path: "/System/Applications/System Settings.app"))
        page.keys[15] = KeyConfig(title: String(localized: "Muet"), background: DeckColor(hex: "#3D1A1A")!, icon: .symbol("speaker.slash.fill"),
                                  action: .media(.mute))
        page.keys[12] = KeyConfig(title: "Vol −", background: DeckColor(hex: "#1F2937")!, icon: .symbol("speaker.minus.fill"),
                                  action: .media(.volumeDown))
        page.keys[9] = KeyConfig(title: "Vol +", background: DeckColor(hex: "#1F2937")!, icon: .symbol("speaker.plus.fill"),
                                 action: .media(.volumeUp))
        page.keys[6] = KeyConfig(title: String(localized: "Lecture"), background: DeckColor(hex: "#1F2937")!, icon: .symbol("playpause.fill"),
                                 action: .media(.playPause))
        page.keys[16] = KeyConfig(background: DeckColor(hex: "#0B132B")!, widget: .clock)
        page.keys[17] = KeyConfig(background: DeckColor(hex: "#0B132B")!, widget: .date)
        return DeckConfiguration(pages: [page])
    }
}
