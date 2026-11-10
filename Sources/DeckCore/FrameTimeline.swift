import Foundation

/// Calendrier d'une image animée : quelle image montrer à quel instant, en boucle.
public struct FrameTimeline: Sendable {
    /// Instant de fin de chaque image, en secondes depuis le début de la boucle.
    private let ends: [Double]

    /// Les délais inférieurs à 20 ms sont portés à 100 ms, comme le font les navigateurs.
    public init(delays: [Double]) {
        var clock = 0.0
        ends = delays.map { delay in
            clock += delay < 0.02 ? 0.1 : delay
            return clock
        }
    }

    public var duration: Double { ends.last ?? 0 }

    public var isAnimated: Bool { ends.count > 1 }

    public func index(at time: TimeInterval) -> Int {
        guard isAnimated, duration > 0 else { return 0 }
        let moment = time.truncatingRemainder(dividingBy: duration)
        return ends.firstIndex { moment < $0 } ?? 0
    }
}
