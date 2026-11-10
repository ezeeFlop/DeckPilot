import Foundation

/// Retient quelles touches sont enfoncées. Le boîtier n'annonce pas toujours le relâchement :
/// un appui sans relâchement est donc oublié après `holdLimit` secondes.
public struct PressTracker: Sendable {
    public let holdLimit: TimeInterval
    private var pressedAt: [Int: TimeInterval] = [:]

    public init(holdLimit: TimeInterval = 0.3) {
        self.holdLimit = holdLimit
    }

    public mutating func press(_ key: Int, at time: TimeInterval) { pressedAt[key] = time }

    public mutating func release(_ key: Int) { pressedAt[key] = nil }

    public func held(at time: TimeInterval) -> Set<Int> {
        Set(pressedAt.filter { time - $0.value < holdLimit }.keys)
    }
}
