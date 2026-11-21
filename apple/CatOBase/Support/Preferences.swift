import Foundation

/// Keys for @AppStorage, in one place.
enum PrefKey {
    static let catSort = "catSort"
    static let weightUnit = "weightUnit"
    static let remindersEnabled = "remindersEnabled"
    static let reminderMinutes = "reminderMinutes"
    static let remindDayBefore = "remindDayBefore"
    static let badgeOverdue = "badgeOverdue"
}

enum PrefDefault {
    /// 09:00
    static let reminderMinutes = 9 * 60
}

enum CatSort: String, CaseIterable, Identifiable {
    case name, oldestFirst, youngestFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return "Name"
        case .oldestFirst: return "Age, oldest first"
        case .youngestFirst: return "Age, youngest first"
        }
    }

    /// Cats without a birthday go last when sorting by age, ordered by name.
    func sorted(_ cats: [Cat]) -> [Cat] {
        let byName: (Cat, Cat) -> Bool = {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        switch self {
        case .name:
            return cats.sorted(by: byName)
        case .oldestFirst, .youngestFirst:
            return cats.sorted { lhs, rhs in
                switch (lhs.birthday, rhs.birthday) {
                case let (l?, r?):
                    if l == r { return byName(lhs, rhs) }
                    return self == .oldestFirst ? l < r : l > r
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return byName(lhs, rhs)
                }
            }
        }
    }
}

enum WeightUnit: String, CaseIterable, Identifiable {
    case kg, lb

    var id: String { rawValue }
    static let poundsPerKilogram = 2.2046226218

    var label: String {
        switch self {
        case .kg: return "Kilograms (kg)"
        case .lb: return "Pounds (lb)"
        }
    }

    func fromKilograms(_ kg: Double) -> Double {
        self == .kg ? kg : kg * WeightUnit.poundsPerKilogram
    }

    func toKilograms(_ value: Double) -> Double {
        self == .kg ? value : value / WeightUnit.poundsPerKilogram
    }

    /// "4.2 kg", "9.26 lb"
    func format(kilograms kg: Double) -> String {
        let value = fromKilograms(kg)
        return value.formatted(.number.precision(.fractionLength(0...2))) + " " + rawValue
    }

    /// "+0.2 kg", "−0.15 lb"
    func formatChange(kilograms kg: Double) -> String {
        let value = fromKilograms(kg)
        let magnitude = abs(value).formatted(.number.precision(.fractionLength(0...2)))
        if value > 0 { return "+\(magnitude) \(rawValue)" }
        if value < 0 { return "−\(magnitude) \(rawValue)" }
        return "no change"
    }

    /// Parses user input, accepting either "," or "." as the decimal separator.
    static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value > 0, value < 100 else { return nil }
        return value
    }
}
