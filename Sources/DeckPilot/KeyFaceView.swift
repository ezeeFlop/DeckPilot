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
    /// Valeur à montrer quand la case porte une donnée vivante.
    var live: LiveDisplay?
    /// Image et titre fournis par une extension, quand la touche lui appartient.
    var plugin: PluginDisplay?

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
        if let plugin {
            pluginContent(plugin)
        } else if let live {
            LiveContent(display: live, title: config.title, titleSize: config.titleSize, titleColor: config.titleColor.color,
                        accent: config.iconColor.color, unit: unit)
        } else {
            staticContent
        }
    }

    /// Une touche d'extension : son image occupe toute la case, son titre vient par-dessus.
    /// Un titre saisi par l'utilisateur passe avant celui de l'extension.
    @ViewBuilder private func pluginContent(_ plugin: PluginDisplay) -> some View {
        ZStack {
            if let image = plugin.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: side, height: side)
            } else {
                Image(systemName: plugin.isMissing ? "puzzlepiece.extension" : "hourglass")
                    .font(.system(size: 30 * unit))
                    .foregroundStyle(.white.opacity(0.45))
            }
            let text = config.title.isEmpty ? (plugin.title ?? "") : config.title
            if !text.isEmpty {
                VStack {
                    if config.titlePosition != .top { Spacer(minLength: 0) }
                    Text(text)
                        .font(.system(size: config.titleSize * unit, weight: .semibold, design: .rounded))
                        .foregroundStyle(config.titleColor.color)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                        .shadow(color: .black.opacity(0.8), radius: 2 * unit)
                    if config.titlePosition != .bottom { Spacer(minLength: 0) }
                }
                .padding(5 * unit)
            }
            if let flash = plugin.flash {
                Color.black.opacity(0.55)
                Image(systemName: flash == .ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 44 * unit))
                    .foregroundStyle(flash == .ok ? Color.green : Color.yellow)
            }
        }
    }

    @ViewBuilder private var staticContent: some View {
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

/// Ce qu'une extension montre sur sa touche.
struct PluginDisplay {
    var image: CGImage?
    var title: String?
    var flash: PluginFace.Flash?
    /// Vrai quand l'extension de cette touche n'est pas installée.
    var isMissing: Bool
}

/// Le dessin d'une donnée vivante : valeur seule, anneau, barre ou courbe.
private struct LiveContent: View {
    let display: LiveDisplay
    let title: String
    let titleSize: Double
    let titleColor: Color
    let accent: Color
    let unit: CGFloat

    private var color: Color {
        switch display.level {
        case .normal: return accent
        case .warning: return Color(red: 0.96, green: 0.62, blue: 0.04)
        case .critical: return Color(red: 0.94, green: 0.27, blue: 0.27)
        }
    }

    private var valueColor: Color { display.level == .normal ? titleColor : color }

    var body: some View {
        switch display.style {
        case .value: valueOnly
        case .ring: ring
        case .bar: bar
        case .sparkline: sparkline
        }
    }

    private func value(_ size: CGFloat) -> some View {
        Text(display.text)
            .font(.system(size: size * unit, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(valueColor)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .opacity(display.isPlaceholder ? 0.5 : 1)
    }

    @ViewBuilder private var label: some View {
        if !title.isEmpty {
            Text(title)
                .font(.system(size: min(titleSize, 15) * unit, weight: .semibold, design: .rounded))
                .foregroundStyle(titleColor.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var valueOnly: some View {
        VStack(spacing: 2 * unit) {
            value(30)
            label
        }
        .padding(.horizontal, 6 * unit)
    }

    private var ring: some View {
        let width = 9 * unit
        return VStack(spacing: 1 * unit) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: 0.75 * max(display.fraction, 0.001))
                    .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(135))
                value(19)
                    .padding(.horizontal, width + 5 * unit)
            }
            .padding(width / 2)
            .aspectRatio(1, contentMode: .fit)
            label
                .padding(.top, -9 * unit)
        }
        .padding(.horizontal, 8 * unit)
        .padding(.vertical, 7 * unit)
    }

    private var bar: some View {
        VStack(spacing: 5 * unit) {
            label
            value(26)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.16))
                    Capsule().fill(color).frame(width: max(proxy.size.width * display.fraction, proxy.size.height))
                }
            }
            .frame(height: 9 * unit)
        }
        .padding(.horizontal, 10 * unit)
    }

    private var sparkline: some View {
        VStack(alignment: .leading, spacing: 2 * unit) {
            HStack(alignment: .firstTextBaseline, spacing: 4 * unit) {
                value(20)
                label
            }
            GeometryReader { proxy in
                let points = Self.points(display.history, in: proxy.size)
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.45), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5 * unit, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .padding(.horizontal, 8 * unit)
        .padding(.vertical, 9 * unit)
    }

    /// Place les valeurs de gauche à droite, la plus basse en bas et la plus haute en haut de la zone.
    private static func points(_ values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let low = values.min(), let high = values.max() else { return [] }
        let span = max(high - low, 0.0001)
        return values.enumerated().map { index, value in
            CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: size.height * (1 - CGFloat((value - low) / span) * 0.9 - 0.05))
        }
    }
}
