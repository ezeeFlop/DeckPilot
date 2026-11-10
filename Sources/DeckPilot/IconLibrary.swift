import AppKit
import DeckCore
import ImageIO

/// Charge et garde en mémoire les images des touches : fichiers (GIF animés compris) et icônes d'applications.
@MainActor
final class IconLibrary {
    struct Frames {
        let images: [CGImage]
        let timeline: FrameTimeline
        var isAnimated: Bool { timeline.isAnimated }

        init(images: [CGImage], delays: [Double]) {
            self.images = images
            self.timeline = FrameTimeline(delays: delays)
        }

        func index(at time: TimeInterval) -> Int { min(timeline.index(at: time), images.count - 1) }
    }

    private let store: ConfigStore
    private var files: [String: Frames] = [:]
    private var apps: [String: CGImage] = [:]
    /// Fichiers déjà essayés sans succès, pour ne pas relire le disque à chaque image.
    private var unreadable: Set<String> = []

    init(store: ConfigStore) {
        self.store = store
    }

    func frames(for icon: KeyIcon) -> Frames? {
        switch icon {
        case .image(let name):
            if let cached = files[name] { return cached }
            if unreadable.contains(name) { return nil }
            guard let loaded = Self.load(store.imageURL(named: name)) else {
                unreadable.insert(name)
                return nil
            }
            files[name] = loaded
            return loaded
        case .appIcon(let path):
            if let cached = apps[path] { return Frames(images: [cached], delays: [0]) }
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            // Certaines applications système sont des liens : on prend l'icône de la cible, sans la flèche d'alias.
            let icon = NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
            var rect = CGRect(x: 0, y: 0, width: 256, height: 256)
            guard let image = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
            apps[path] = image
            return Frames(images: [image], delays: [0])
        case .none, .symbol, .emoji:
            return nil
        }
    }

    func image(for icon: KeyIcon, at time: TimeInterval) -> CGImage? {
        guard let frames = frames(for: icon), !frames.images.isEmpty else { return nil }
        return frames.images[frames.index(at: time)]
    }

    private static func load(_ url: URL) -> Frames? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        var images: [CGImage] = []
        var delays: [Double] = []
        for index in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            images.append(image)
            delays.append((gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1)
        }
        return images.isEmpty ? nil : Frames(images: images, delays: delays)
    }
}
