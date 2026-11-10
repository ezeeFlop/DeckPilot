import Foundation

/// D'où vient la donnée affichée sur une case.
public enum LiveSource: Codable, Hashable, Sendable {
    case none
    /// Une mesure du Mac lui-même.
    case system(SystemMetric)
    /// Requête GET. `jsonPath` désigne le champ à lire (« data.items[0].value ») ; vide, tout le corps est lu.
    /// `headers` contient un en-tête par ligne, sous la forme « Nom: valeur ».
    case http(url: String, jsonPath: String, headers: String)
    /// Commande lancée par zsh ; sa sortie standard est lue.
    case command(String)
}

public enum SystemMetric: String, Codable, CaseIterable, Sendable {
    case cpu, memory, disk, battery
}

public enum LiveStyle: String, Codable, CaseIterable, Sendable {
    case value, ring, bar, sparkline
}

public enum LiveLevel: Sendable {
    case normal, warning, critical
}

/// Réglages de la donnée vivante d'une case : sa source, son rythme et sa mise en forme.
public struct LiveData: Codable, Hashable, Sendable {
    public var source: LiveSource
    /// Secondes entre deux lectures.
    public var interval: Double
    public var style: LiveStyle
    public var minimum: Double
    public var maximum: Double
    /// Texte accolé à la valeur, tel que saisi (« % », «  °C »).
    public var unit: String
    public var decimals: Int
    public var warning: Double?
    public var critical: Double?
    /// Vrai quand ce sont les valeurs basses qui alertent (batterie, espace libre).
    public var alertsWhenBelow: Bool

    public init(source: LiveSource = .none, interval: Double = 30, style: LiveStyle = .value, minimum: Double = 0,
                maximum: Double = 100, unit: String = "", decimals: Int = 0, warning: Double? = nil,
                critical: Double? = nil, alertsWhenBelow: Bool = false) {
        self.source = source
        self.interval = interval
        self.style = style
        self.minimum = minimum
        self.maximum = maximum
        self.unit = unit
        self.decimals = decimals
        self.warning = warning
        self.critical = critical
        self.alertsWhenBelow = alertsWhenBelow
    }

    /// Position de la valeur entre le minimum et le maximum, de 0 à 1.
    public func fraction(of value: Double) -> Double {
        guard maximum > minimum else { return 0 }
        return min(max((value - minimum) / (maximum - minimum), 0), 1)
    }

    public func level(of value: Double) -> LiveLevel {
        func reached(_ threshold: Double?) -> Bool {
            guard let threshold else { return false }
            return alertsWhenBelow ? value <= threshold : value >= threshold
        }
        if reached(critical) { return .critical }
        if reached(warning) { return .warning }
        return .normal
    }

    public func format(_ value: Double, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = max(decimals, 0)
        formatter.maximumFractionDigits = max(decimals, 0)
        return (formatter.string(from: NSNumber(value: value)) ?? "\(value)") + unit
    }
}

/// Une valeur lue : son texte, et le nombre qu'il contient s'il y en a un.
public struct LiveValue: Equatable, Sendable {
    public let text: String
    public let number: Double?

    public init(number: Double) {
        self.number = number
        self.text = number == number.rounded() && abs(number) < 1e15 ? String(Int64(number)) : String(number)
    }

    /// Garde la première ligne du texte et y cherche le premier nombre (« CPU: 63.4% » donne 63,4).
    public init(text raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = trimmed.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if let range = text.range(of: #"-?\d+(?:[.,]\d+)?"#, options: .regularExpression) {
            number = Double(text[range].replacingOccurrences(of: ",", with: "."))
        } else {
            number = nil
        }
    }
}

/// Lecture d'un champ dans une réponse JSON, par un chemin du type « data.items[0].value ».
public enum JSONPath {
    public static func extract(_ path: String, from data: Data) -> LiveValue? {
        let trimmedPath = path.trimmingCharacters(in: .whitespaces)
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            // Pas du JSON : sans chemin, on lit le texte brut.
            guard trimmedPath.isEmpty, let body = String(data: data, encoding: .utf8) else { return nil }
            let value = LiveValue(text: body)
            return value.text.isEmpty ? nil : value
        }
        var current: Any = root
        for step in steps(of: trimmedPath) {
            switch step {
            case .key(let key):
                guard let object = current as? [String: Any], let next = object[key] else { return nil }
                current = next
            case .index(let index):
                guard let array = current as? [Any], array.indices.contains(index) else { return nil }
                current = array[index]
            }
        }
        return leaf(current)
    }

    private enum Step {
        case key(String)
        case index(Int)
    }

    private static func steps(of path: String) -> [Step] {
        var steps: [Step] = []
        for part in path.split(separator: ".") {
            var key = ""
            var index = ""
            var inBrackets = false
            for character in part {
                switch character {
                case "[":
                    if !key.isEmpty { steps.append(.key(key)); key = "" }
                    inBrackets = true
                case "]":
                    if let number = Int(index) { steps.append(.index(number)) }
                    index = ""
                    inBrackets = false
                default:
                    if inBrackets { index.append(character) } else { key.append(character) }
                }
            }
            if !key.isEmpty { steps.append(.key(key)) }
        }
        return steps
    }

    private static func leaf(_ value: Any) -> LiveValue? {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return LiveValue(text: number.boolValue ? "true" : "false") }
            return LiveValue(number: number.doubleValue)
        case let string as String:
            return LiveValue(text: string)
        case let array as [Any]:
            return LiveValue(number: Double(array.count))
        case let object as [String: Any]:
            return LiveValue(number: Double(object.count))
        default:
            return nil
        }
    }
}

/// Les dernières valeurs lues, pour tracer une courbe.
public struct LiveHistory: Equatable, Sendable {
    public let capacity: Int
    public private(set) var values: [Double] = []

    public init(capacity: Int = 40) {
        self.capacity = capacity
    }

    public mutating func append(_ value: Double) {
        values.append(value)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }
}

/// Passage en douceur d'une valeur à la suivante : départ vif, arrivée ralentie.
public struct LiveTransition: Equatable, Sendable {
    public let from: Double
    public let to: Double
    public let startedAt: TimeInterval
    public let duration: TimeInterval

    public init(from: Double, to: Double, startedAt: TimeInterval, duration: TimeInterval = 0.6) {
        self.from = from
        self.to = to
        self.startedAt = startedAt
        self.duration = duration
    }

    public func value(at time: TimeInterval) -> Double {
        guard duration > 0 else { return to }
        let progress = min(max((time - startedAt) / duration, 0), 1)
        let eased = 1 - pow(1 - progress, 3)
        return from + (to - from) * eased
    }

    public func isRunning(at time: TimeInterval) -> Bool {
        time >= startedAt && time < startedAt + duration
    }
}
