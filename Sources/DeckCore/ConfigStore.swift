import Foundation

/// Rangement de la configuration et des images sur le disque.
public struct ConfigStore: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// `~/Library/Application Support/DeckPilot`.
    public static var standard: ConfigStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ConfigStore(folder: base.appendingPathComponent("DeckPilot", isDirectory: true))
    }

    private var configURL: URL { folder.appendingPathComponent("config.json") }
    private var imagesFolder: URL { folder.appendingPathComponent("images", isDirectory: true) }

    /// Lit la configuration. Sans fichier, rend la configuration de départ. Un fichier illisible est mis de côté,
    /// jamais écrasé.
    public func load() -> DeckConfiguration {
        guard let data = try? Data(contentsOf: configURL) else { return .starter }
        if let config = try? JSONDecoder().decode(DeckConfiguration.self, from: data) { return config }
        let stamp = Int(Date().timeIntervalSince1970)
        try? FileManager.default.moveItem(at: configURL, to: folder.appendingPathComponent("config-illisible-\(stamp).json"))
        return .starter
    }

    public func save(_ config: DeckConfiguration) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: configURL, options: .atomic)
    }

    /// Copie une image dans le dossier de l'application et rend le nom sous lequel la retrouver.
    public func importImage(from source: URL) throws -> String {
        try FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let name = "\(UUID().uuidString).\(ext)"
        try FileManager.default.copyItem(at: source, to: imagesFolder.appendingPathComponent(name))
        return name
    }

    public func imageURL(named name: String) -> URL { imagesFolder.appendingPathComponent(name) }
}
