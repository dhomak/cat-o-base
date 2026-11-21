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

    /// "today", "tomorrow", "in 6 days", "yesterday", "5 days overdue"
    static func relativeDue(_ date: Date, now: Date = .now) -> String {
        let days = DueStatus.days(until: date, now: now)
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "1 day overdue"
        case ..<0: return "\(-days) days overdue"
        default: return "in \(days) days"
        }
    }

    /// "daily", "weekly", "every 90 days"
    static func interval(days: Int) -> String {
        switch days {
        case 1: return "daily"
        case 7: return "weekly"
        case 14: return "every 2 weeks"
        default: return "every \(days) days"
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
