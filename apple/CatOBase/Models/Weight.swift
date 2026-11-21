import Foundation

/// The current weight and how it has changed.
struct WeightTrend {
    let latest: WeightEntry
    /// Change since the previous weigh-in, in kg.
    let changeSincePrevious: Double?
    /// Percent change against a reference about six months back (or the first entry).
    let percentChange: Double?
    let referenceDate: Date?

    /// A loss of 10% or more is worth a vet visit.
    static let warningPercent = -10.0

    var isWarning: Bool {
        guard let percentChange else { return false }
        return percentChange <= WeightTrend.warningPercent
    }
}

extension Cat {
    /// Weigh-ins, newest first.
    var weightsNewestFirst: [WeightEntry] {
        (weights ?? []).sorted { $0.date > $1.date }
    }

    var weightTrend: WeightTrend? {
        let entries = weightsNewestFirst
        guard let latest = entries.first else { return nil }

        let previous = entries.dropFirst().first
        let change = previous.map { latest.kg - $0.kg }

        // Reference: the newest weigh-in at least ~6 months before the latest,
        // or the oldest one if the history is shorter than that.
        let cutoff = Calendar.current.date(byAdding: .day, value: -183, to: latest.date) ?? latest.date
        let reference = entries.first(where: { $0.date <= cutoff }) ?? (entries.count > 1 ? entries.last : nil)

        var percent: Double?
        if let reference, reference.kg > 0 {
            percent = (latest.kg - reference.kg) / reference.kg * 100
        }
        return WeightTrend(latest: latest, changeSincePrevious: change,
                           percentChange: percent, referenceDate: reference?.date)
    }
}
