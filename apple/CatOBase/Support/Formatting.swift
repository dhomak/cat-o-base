import Foundation

enum Fmt {
    /// "3 y 5 mo", "7 mo", or nil without a birthday.
    static func age(from birthday: Date?, now: Date = .now) -> String? {
        guard let birthday else { return nil }
        let parts = Calendar.current.dateComponents([.year, .month], from: birthday, to: now)
        let years = parts.year ?? 0
        let months = parts.month ?? 0
        if years < 0 || (years == 0 && months < 0) { return nil }
        let monthsText = String(localized: "\(months) mo", comment: "Age in months, abbreviated")
        if years == 0 { return monthsText }
        let yearsText = String(localized: "\(years) y", comment: "Age in years, abbreviated")
        return months == 0 ? yearsText : yearsText + " " + monthsText
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func kg(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2))) + " " + WeightUnit.kg.symbol
    }

    /// "today", "tomorrow", "in 6 days", "yesterday", "5 days overdue"
    static func relativeDue(_ date: Date, now: Date = .now) -> String {
        let days = DueStatus.days(until: date, now: now)
        switch days {
        case 0: return String(localized: "today")
        case 1: return String(localized: "tomorrow")
        case ..<0:
            let overdue = -days
            return String(localized: "\(overdue) days overdue")
        default: return String(localized: "in \(days) days")
        }
    }

    /// "12.5%"
    static func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    /// "+3.1%", "−12.5%"
    static func signedPercent(_ value: Double) -> String {
        let magnitude = percent(abs(value))
        if value > 0 { return "+" + magnitude }
        if value < 0 { return "−" + magnitude }
        return magnitude
    }

    /// "daily", "weekly", "every 90 days"
    static func interval(days: Int) -> String {
        switch days {
        case 1: return String(localized: "daily")
        case 7: return String(localized: "weekly")
        case 14: return String(localized: "every 2 weeks")
        default: return String(localized: "every \(days) days")
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
