import Foundation
import SwiftData
import SwiftUI

// MARK: - Due status

enum DueStatus: Int, Comparable {
    case overdue, soon, later

    /// Within this many days counts as "soon".
    static let soonDays = 14

    init(_ date: Date, now: Date = .now) {
        let days = DueStatus.days(until: date, now: now)
        if days < 0 {
            self = .overdue
        } else if days <= DueStatus.soonDays {
            self = .soon
        } else {
            self = .later
        }
    }

    /// Whole calendar days from today to `date` (negative when in the past).
    static func days(until date: Date, now: Date = .now) -> Int {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: now)
        let to = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    var color: Color {
        switch self {
        case .overdue: return .red
        case .soon: return .orange
        case .later: return .secondary
        }
    }

    static func < (lhs: DueStatus, rhs: DueStatus) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Due items

enum DueKind {
    case vaccination, treatment

    var label: String {
        switch self {
        case .vaccination: return String(localized: "Vaccination")
        case .treatment: return String(localized: "Treatment")
        }
    }

    var systemImage: String {
        switch self {
        case .vaccination: return "syringe"
        case .treatment: return "pills"
        }
    }
}

/// Something with a due date: the current record of a vaccine, or an active treatment.
struct DueItem: Identifiable {
    let id: PersistentIdentifier
    let kind: DueKind
    let cat: Cat
    let title: String
    let date: Date
    let vaccination: Vaccination?
    let treatment: Treatment?

    var status: DueStatus { DueStatus(date) }
}

extension Cat {
    /// Upcoming and overdue items for this cat, soonest first.
    var dueItems: [DueItem] {
        var items: [DueItem] = []
        let vaccines = vaccinations ?? []
        for vaccine in vaccines {
            guard let due = vaccine.nextDue, vaccine.isCurrent(among: vaccines) else { continue }
            items.append(DueItem(id: vaccine.persistentModelID, kind: .vaccination, cat: self,
                                 title: vaccine.name, date: due, vaccination: vaccine, treatment: nil))
        }
        for treatment in treatments ?? [] where treatment.active {
            guard let due = treatment.nextDue else { continue }
            if let end = treatment.endDate, end < due { continue }
            items.append(DueItem(id: treatment.persistentModelID, kind: .treatment, cat: self,
                                 title: treatment.name, date: due, vaccination: nil, treatment: treatment))
        }
        return items.sorted { $0.date < $1.date }
    }

    /// The most urgent status among this cat's due items, if any are overdue or soon.
    var worstDueStatus: DueStatus? {
        dueItems.map(\.status).filter { $0 != .later }.min()
    }
}

// MARK: - Vaccinations

extension Vaccination {
    /// False when a newer dose of the same vaccine exists; its due date no longer matters.
    func isCurrent(among all: [Vaccination]) -> Bool {
        let key = name.trimmed.lowercased()
        let given = dateGiven ?? .distantPast
        return !all.contains { other in
            other !== self
                && other.name.trimmed.lowercased() == key
                && (other.dateGiven ?? .distantPast) > given
        }
    }

    /// The repeat interval implied by this record, rounded to whole months.
    var repeatMonths: Int? {
        guard let given = dateGiven, let due = nextDue, due > given else { return nil }
        let days = Double(Calendar.current.dateComponents([.day], from: given, to: due).day ?? 0)
        let months = Int((days / 30.44).rounded())
        return months > 0 ? months : nil
    }

    /// Records a new dose given on `date`, repeating on the same interval. Returns the new record.
    @discardableResult
    func recordNextDose(on date: Date = .now, in context: ModelContext) -> Vaccination {
        let dose = Vaccination(name: name)
        dose.dateGiven = date
        dose.vet = vet
        if let months = repeatMonths {
            dose.nextDue = Calendar.current.date(byAdding: .month, value: months, to: date)
        }
        context.insert(dose)
        dose.cat = cat
        return dose
    }
}

// MARK: - Treatments

extension Treatment {
    /// Marks the treatment as given and moves the next due date forward.
    func markGiven(on date: Date = .now) {
        lastGiven = date
        if let days = intervalDays, days > 0 {
            nextDue = Calendar.current.date(byAdding: .day, value: days, to: date)
        } else {
            nextDue = nil
        }
    }

    /// "½ tablet · twice daily · every 90 days"
    var summary: String {
        var parts: [String] = []
        if !dose.trimmed.isEmpty { parts.append(dose) }
        if !schedule.trimmed.isEmpty { parts.append(schedule) }
        if let days = intervalDays, days > 0 { parts.append(Fmt.interval(days: days)) }
        return parts.joined(separator: " · ")
    }
}

enum DueActions {
    /// "Given today" for anything on the due list.
    static func markGiven(_ item: DueItem, in context: ModelContext) {
        if let treatment = item.treatment {
            treatment.markGiven()
        } else if let vaccination = item.vaccination {
            vaccination.recordNextDose(in: context)
        }
        try? context.save()
    }
}
