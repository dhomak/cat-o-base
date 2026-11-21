import Foundation

enum Fmt {
    /// "3 y 5 mo", "7 mo", or nil without a birthday.
    static func age(from birthday: Date?, now: Date = .now) -> String? {
        guard let birthday else { return nil }
        let parts = Calendar.current.dateComponents([.year, .month], from: birthday, to: now)
        let years = parts.year ?? 0
        let months = parts.month ?? 0
        if years < 0 || (years == 0 && months < 0) { return nil }
        if years == 0 { return "\(months) mo" }
        return months == 0 ? "\(years) y" : "\(years) y \(months) mo"
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func kg(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2))) + " kg"
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
