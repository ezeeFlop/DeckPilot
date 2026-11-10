import Foundation

/// Géométrie d'un boîtier : où se trouve chaque case, et lesquelles s'enfoncent.
public struct DeckLayout: Sendable {
    public struct Position: Hashable, Sendable {
        public let row: Int
        public let column: Int
        public init(row: Int, column: Int) {
            self.row = row
            self.column = column
        }
    }

    public let columns: Int
    public let rows: Int
    /// Côté d'une image de case, en pixels.
    public let imageSide: Int
    /// Rotation à appliquer avant envoi, en quarts de tour dans le sens inverse des aiguilles d'une montre.
    public let quarterTurnsCounterClockwise: Int
    private let pressableSlots: Set<Int>
    private let hiddenLeadingPixels: Int
    private let glassBeyondImage: Int
    private let slotByPosition: [Position: Int]
    private let positionBySlot: [Int: Position]

    /// MiraBox StreamDock 293SV3 : 5 colonnes de 3 touches numérotées de haut en bas en partant de la droite
    /// (1 à 15), puis une colonne de 3 cases d'affichage seul (16 à 18).
    public static let streamDock293SV3: DeckLayout = {
        var map: [Position: Int] = [:]
        for row in 0..<3 {
            for column in 0..<5 { map[Position(row: row, column: column)] = (4 - column) * 3 + row + 1 }
            map[Position(row: row, column: 5)] = 16 + row
        }
        return DeckLayout(columns: 6, rows: 3, imageSide: 96, quarterTurnsCounterClockwise: 1,
                          pressableSlots: Set(1...15), hiddenLeadingPixels: 14, glassBeyondImage: 7, slotByPosition: map)
    }()

    init(columns: Int, rows: Int, imageSide: Int, quarterTurnsCounterClockwise: Int,
         pressableSlots: Set<Int>, hiddenLeadingPixels: Int, glassBeyondImage: Int,
         slotByPosition: [Position: Int]) {
        self.columns = columns
        self.rows = rows
        self.imageSide = imageSide
        self.quarterTurnsCounterClockwise = quarterTurnsCounterClockwise
        self.pressableSlots = pressableSlots
        self.hiddenLeadingPixels = hiddenLeadingPixels
        self.glassBeyondImage = glassBeyondImage
        self.slotByPosition = slotByPosition
        self.positionBySlot = Dictionary(uniqueKeysWithValues: slotByPosition.map { ($1, $0) })
    }

    public var slots: [Int] { positionBySlot.keys.sorted() }

    public var slotsInReadingOrder: [Int] {
        (0..<rows).flatMap { row in (0..<columns).map { slot(row: row, column: $0) } }
    }

    public func slot(row: Int, column: Int) -> Int {
        slotByPosition[Position(row: row, column: column)] ?? 0
    }

    public func position(ofSlot slot: Int) -> Position? { positionBySlot[slot] }

    public func isPressable(slot: Int) -> Bool { pressableSlots.contains(slot) }

    /// Largeur, en pixels, de la bande gauche de l'image que la case ne montre pas.
    /// Les cases de la bande d'affichage sont plus étroites que leur image : le bord gauche est masqué.
    public func leadingInset(ofSlot slot: Int) -> Int {
        isPressable(slot: slot) ? 0 : hiddenLeadingPixels
    }

    /// Largeur de vitre noire visible à droite de l'image, en pixels d'image (mesurée sur photo : 7 pour la bande).
    public func trailingGlass(ofSlot slot: Int) -> Int {
        isPressable(slot: slot) ? 0 : glassBeyondImage
    }

    /// Marge gauche à laisser au contenu pour qu'il paraisse centré dans la vitre :
    /// la partie masquée, plus de quoi équilibrer la vitre noire de droite.
    public func contentLeadingInset(ofSlot slot: Int) -> Int {
        leadingInset(ofSlot: slot) + trailingGlass(ofSlot: slot)
    }
}
