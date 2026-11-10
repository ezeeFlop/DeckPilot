import Foundation

/// Commandes du StreamDock 293SV3, telles que lues dans `libtransport.dylib` (voir docs/protocol-notes.md).
public enum DeckCommand: Equatable {
    case wake
    case brightness(Int)
    case imageHeader(byteCount: Int, slot: UInt8)
    case refresh
    case clear(slot: UInt8)
    case clearAll
    case sleep
    case heartbeat
    case disconnect

    private static let prefix: [UInt8] = Array("CRT".utf8) + [0, 0]

    /// Octets utiles de la commande, avant complétion à la taille du rapport.
    public var payload: [UInt8] {
        func command(_ name: String, _ tail: [UInt8] = []) -> [UInt8] {
            Self.prefix + Array(name.utf8) + tail
        }
        switch self {
        case .wake: return command("DIS")
        case .brightness(let percent): return command("LIG", [0, 0, UInt8(min(max(percent, 0), 100))])
        case .imageHeader(let byteCount, let slot):
            let n = UInt32(byteCount)
            return command("BAT", [UInt8(n >> 24), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF), slot])
        case .refresh: return command("STP")
        case .clear(let slot): return command("CLE", [0, 0, 0, slot])
        case .clearAll: return command("CLE", [0, 0, 0, 0xFF])
        case .sleep: return command("HAN")
        case .heartbeat: return command("CONNECT")
        case .disconnect: return command("CLE", [0, 0] + Array("DC".utf8))
        }
    }
}

/// Découpage en rapports de sortie de taille fixe, complétés par des zéros.
public enum DeckReports {
    public static let outputSize = 1024
    public static let inputSize = 512

    public static func split(_ payload: [UInt8], reportSize: Int = outputSize) -> [[UInt8]] {
        stride(from: 0, to: max(payload.count, 1), by: reportSize).map { start in
            let chunk = Array(payload[start..<min(start + reportSize, payload.count)])
            return chunk + [UInt8](repeating: 0, count: reportSize - chunk.count)
        }
    }

    public static func imageUpload(jpeg: [UInt8], slot: UInt8, reportSize: Int = outputSize) -> [[UInt8]] {
        split(DeckCommand.imageHeader(byteCount: jpeg.count, slot: slot).payload, reportSize: reportSize)
            + split(jpeg, reportSize: reportSize)
    }
}

/// Un appui ou un relâchement, lu dans un rapport d'entrée.
public struct DeckInput: Equatable, Sendable {
    public let key: Int
    public let pressed: Bool

    public init(key: Int, pressed: Bool) {
        self.key = key
        self.pressed = pressed
    }

    public init?(report: [UInt8]) {
        guard report.count >= 11,
              report[0] == 0x41, report[1] == 0x43, report[2] == 0x4B,  // ACK
              report[5] == 0x4F, report[6] == 0x4B,  // OK
              report[9] != 0xFF, report[9] != 0, report[10] <= 1
        else { return nil }
        self.init(key: Int(report[9]), pressed: report[10] == 1)
    }
}
