import DeckCore
import SwiftUI

extension DeckColor {
    var color: Color { Color(red: red, green: green, blue: blue) }

    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(red: Double(c.redComponent), green: Double(c.greenComponent), blue: Double(c.blueComponent))
    }
}

/// Le dessin d'une case, identique à l'écran du Mac et sur le boîtier.
/// Toutes les mesures sont proportionnelles à `side` ; les tailles de la configuration valent pour un côté de 96.
struct KeyFaceView: View {
    let config: KeyConfig
    let side: CGFloat
    /// Image déjà résolue pour une icône de type fichier ou application.
    var iconImage: CGImage?
    /// Temps écoulé, qui fait avancer les animations.
    var time: TimeInterval = 0
    var now: Date = Date()
    var pressed = false
    /// Marge gauche inutilisable (cases de la bande d'affichage), en proportion du côté.
    var leadingInset: CGFloat = 0

    private var unit: CGFloat { side / 96 }
    private var hasTitle: Bool { !config.title.isEmpty }
    private var hasIcon: Bool { config.icon != .none }

    var body: some View {
        ZStack {
            background
            content
                .padding(.leading, side * leadingInset)
            if pressed { Color.white.opacity(0.28) }
        }
        .frame(width: side, height: side)
        .clipped()
    }

    @ViewBuilder private var background: some View {
        if let end = config.backgroundEnd {
            LinearGradient(colors: [config.background.color, end.color], startPoint: .top, endPoint: .bottom)
        } else {
            config.background.color
        }
    }

    @ViewBuilder private var content: some View {
        switch config.widget {
        case .clock: clock
        case .date: date
        case .none: iconAndTitle
        }
    }

    @ViewBuilder private var iconAndTitle: some View {
        if config.titlePosition == .middle || !hasIcon || !hasTitle {
            ZStack {
                icon
                title.shadow(color: .black.opacity(hasIcon ? 0.8 : 0), radius: 2 * unit)
            }
        } else {
            VStack(spacing: 2 * unit) {
                if config.titlePosition == .top { title }
                icon.frame(maxHeight: .infinity)
                if config.titlePosition == .bottom { title }
            }
            .padding(.vertical, 6 * unit)
        }
    }

    @ViewBuilder private var title: some View {
        if hasTitle {
            Text(config.title)
                .font(.system(size: config.titleSize * unit, weight: .semibold, design: .rounded))
                .foregroundStyle(config.titleColor.color)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 4 * unit)
        }
    }

    @ViewBuilder private var icon: some View {
        let stacked = hasTitle && config.titlePosition != .middle
        let extent = side * config.iconScale * (stacked ? 0.82 : 1)
        Group {
            switch config.icon {
            case .none:
                EmptyView()
            case .symbol(let name):
                Image(systemName: name)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(config.iconColor.color)
                    .frame(width: extent, height: extent)
            case .emoji(let text):
                Text(text)
                    .font(.system(size: extent * 0.86))
                    .frame(width: extent * 1.2, height: extent * 1.2)
            case .image, .appIcon:
                if let iconImage {
                    Image(decorative: iconImage, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: extent, height: extent)
                } else {
                    Image(systemName: "questionmark.square.dashed")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: extent * 0.7, height: extent * 0.7)
                }
            }
        }
        .modifier(IconMotion(animation: config.animation, time: time, side: side))
    }

    private var clock: some View {
        VStack(spacing: 0) {
            Text(now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                .font(.system(size: 27 * unit, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 5 * unit)
            if hasTitle { title }
        }
        .foregroundStyle(config.titleColor.color)
    }

    private var date: some View {
        VStack(spacing: -2 * unit) {
            Text(now, format: .dateTime.weekday(.abbreviated))
                .font(.system(size: 15 * unit, weight: .semibold, design: .rounded))
                .opacity(0.75)
            Text(now, format: .dateTime.day())
                .font(.system(size: 38 * unit, weight: .bold, design: .rounded))
            Text(now, format: .dateTime.month(.abbreviated))
                .font(.system(size: 14 * unit, weight: .semibold, design: .rounded))
                .opacity(0.75)
        }
        .foregroundStyle(config.titleColor.color)
    }
}

/// Mouvement appliqué à l'icône selon l'animation choisie.
private struct IconMotion: ViewModifier {
    let animation: KeyAnimation
    let time: TimeInterval
    let side: CGFloat

    private func phase(_ period: Double) -> Double { time.truncatingRemainder(dividingBy: period) / period }

    func body(content: Content) -> some View {
        switch animation {
        case .none:
            content
        case .pulse:
            content.scaleEffect(1 + 0.13 * sin(2 * .pi * phase(1.6)))
        case .spin:
            content.rotationEffect(.degrees(360 * phase(3)))
        case .bounce:
            content.offset(y: -abs(sin(.pi * phase(0.9))) * side * 0.12)
        case .blink:
            content.opacity(phase(1.2) < 0.5 ? 1 : 0.2)
        }
    }
}
