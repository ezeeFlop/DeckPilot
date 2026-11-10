import DeckCore
import StreamDockKit
import SwiftUI
import UniformTypeIdentifiers

/// Le boîtier dessiné à l'échelle : coque claire, quinze touches, bande d'affichage à droite.
struct DeckView: View {
    @EnvironmentObject private var controller: DeckController

    // Mesures relevées sur le boîtier, dans un repère de 900 × 560.
    private let design = CGSize(width: 900, height: 560)
    private let keySide: CGFloat = 108
    private let pitch: CGFloat = 129
    private let origin = CGPoint(x: 92, y: 96)
    private let stripX: CGFloat = 752
    private let stripWidth: CGFloat = 86

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / design.width, proxy.size.height / design.height)
            ZStack(alignment: .topLeading) {
                shell
                Text(controller.currentPage.name)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.56))
                    .frame(width: design.width, height: 44)
                    .offset(y: 30)
                ForEach(0..<controller.layout.rows, id: \.self) { row in
                    ForEach(0..<5, id: \.self) { column in
                        let slot = controller.layout.slot(row: row, column: column)
                        KeyWell(slot: slot, side: keySide)
                            .offset(x: origin.x + CGFloat(column) * pitch, y: origin.y + CGFloat(row) * pitch)
                    }
                }
                strip
            }
            .frame(width: design.width, height: design.height, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: design.width * scale, height: design.height * scale, alignment: .topLeading)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(design.width / design.height, contentMode: .fit)
    }

    private var shell: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.945, blue: 0.93), Color(red: 0.88, green: 0.875, blue: 0.86)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
            .frame(width: design.width, height: design.height)
    }

    /// La bande de droite : une seule vitre noire, trois cases qui affichent sans s'enfoncer.
    private var strip: some View {
        let top = origin.y + 6
        let height = 2 * pitch + keySide - 12
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(white: 0.03))
                .frame(width: stripWidth, height: height)
            ForEach(0..<controller.layout.rows, id: \.self) { row in
                StripCell(slot: controller.layout.slot(row: row, column: 5), width: stripWidth)
                    .offset(y: CGFloat(row) * pitch + (keySide - 12 - StripCell.height(forWidth: stripWidth)) / 2)
            }
        }
        .offset(x: stripX, y: top)
    }
}

/// Une touche : puits noir, écran au fond, cadre de sélection.
private struct KeyWell: View {
    @EnvironmentObject private var controller: DeckController
    let slot: Int
    let side: CGFloat

    var body: some View {
        let selected = controller.selectedSlot == slot
        let pressed = controller.pressedSlots.contains(slot)
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(white: 0.05))
                .shadow(color: .black.opacity(0.35), radius: pressed ? 1 : 4, y: pressed ? 1 : 3)
            SlotFace(slot: slot, side: side - 18)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.13), .clear], startPoint: .top, endPoint: .center))
                .allowsHitTesting(false)
        }
        .frame(width: side, height: side)
        .scaleEffect(pressed ? 0.96 : 1)
        .animation(.easeOut(duration: 0.08), value: pressed)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: selected ? 4 : 0)
                .padding(-5)
        )
        .modifier(SlotInteractions(slot: slot))
    }
}

/// Une case de la bande. La vitre montre les 82 pixels de droite de l'image de 96, puis 7 pixels noirs.
private struct StripCell: View {
    @EnvironmentObject private var controller: DeckController
    let slot: Int
    let width: CGFloat

    private static let visible: CGFloat = 82
    private static let glass: CGFloat = 89

    static func height(forWidth width: CGFloat) -> CGFloat { width * 96 / glass }

    var body: some View {
        let side = Self.height(forWidth: width)
        let selected = controller.selectedSlot == slot
        SlotFace(slot: slot, side: side)
            .frame(width: width * Self.visible / Self.glass, height: side, alignment: .trailing)
            .clipped()
            .frame(width: width, height: side, alignment: .leading)
            .overlay(
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: selected ? 4 : 0)
                    .padding(-5)
            )
            .modifier(SlotInteractions(slot: slot))
    }
}

/// Le dessin vivant d'une case. Une case animée suit l'horloge commune ; les autres ne se redessinent
/// que lorsque leur réglage change.
struct SlotFace: View {
    @EnvironmentObject private var controller: DeckController
    let slot: Int
    let side: CGFloat
    /// Force l'état montré (pour l'aperçu du panneau de réglage) ; `nil` montre l'état réel.
    var showingSecondState: Bool?

    var body: some View {
        let key = showingSecondState.map { controller.key(at: slot).resolved(active: $0) } ?? controller.shownKey(at: slot)
        if let settings = key.live, settings.source != .none {
            LiveFace(engine: controller.live, clock: controller.animation) {
                face(key, time: 0, live: controller.liveDisplay(slot: slot, key: key))
            }
        } else if controller.isAnimated(key) {
            AnimatedFace(clock: controller.animation) { time in face(key, time: time) }
        } else {
            face(key, time: 0)
        }
    }

    private func face(_ key: KeyConfig, time: TimeInterval, live: LiveDisplay? = nil) -> KeyFaceView {
        KeyFaceView(config: key, side: side, iconImage: controller.icons.image(for: key.icon, at: time),
                    time: time, now: controller.now, pressed: controller.pressedSlots.contains(slot),
                    leadingInset: CGFloat(controller.layout.contentLeadingInset(ofSlot: slot)) / CGFloat(controller.layout.imageSide),
                    live: live)
    }
}

/// Une case vivante se redessine quand une lecture aboutit et pendant le glissement d'une valeur à l'autre.
private struct LiveFace: View {
    @ObservedObject var engine: LiveDataEngine
    @ObservedObject var clock: AnimationClock
    let content: () -> KeyFaceView

    var body: some View { content() }
}

private struct AnimatedFace: View {
    @ObservedObject var clock: AnimationClock
    let content: (TimeInterval) -> KeyFaceView

    var body: some View { content(clock.time) }
}

/// Sélection, glisser-déposer et menu contextuel, communs aux touches et aux cases de la bande.
private struct SlotInteractions: ViewModifier {
    @EnvironmentObject private var controller: DeckController
    let slot: Int
    private static let prefix = "deckpilot-slot:"

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { controller.selectedSlot = slot }
            .onDrag { NSItemProvider(object: "\(Self.prefix)\(slot)" as NSString) }
            .onDrop(of: [.fileURL, .plainText], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in controller.assign(fileURL: url, to: slot) }
                    }
                    return true
                }
                _ = provider.loadObject(ofClass: NSString.self) { text, _ in
                    guard let text = text as? String, text.hasPrefix(Self.prefix),
                          let source = Int(text.dropFirst(Self.prefix.count)) else { return }
                    Task { @MainActor in controller.swapKeys(source, slot) }
                }
                return true
            }
            .contextMenu {
                Button("Copier") { controller.copyKey(slot) }
                Button("Coller") { controller.pasteKey(slot) }.disabled(!controller.canPaste)
                if controller.layout.isPressable(slot: slot) {
                    Button("Créer un dossier ici") { controller.createFolder(at: slot) }
                }
                Divider()
                Button("Vider", role: .destructive) { controller.clearKey(slot) }
            }
            .accessibilityLabel(controller.layout.isPressable(slot: slot) ? "Touche \(slot)" : "Case d'affichage \(slot)")
    }
}
