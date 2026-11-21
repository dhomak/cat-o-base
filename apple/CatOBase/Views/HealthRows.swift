import SwiftUI

/// One line on the Due list or the cat's "Coming up" section.
struct DueRow: View {
    let item: DueItem
    var showCat: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            if showCat {
                CatAvatar(cat: item.cat, size: 40)
            } else {
                Image(systemName: item.kind.systemImage)
                    .foregroundStyle(item.status.color)
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.medium))
                Text(showCat ? "\(item.cat.displayName) · \(item.kind.label)" : item.kind.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.date(item.date))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(item.status == .later ? Color.primary : item.status.color)
                Text(Fmt.relativeDue(item.date))
                    .font(.caption)
                    .foregroundStyle(item.status == .later ? Color.secondary : item.status.color)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct VaccinationRow: View {
    let vaccination: Vaccination
    /// False for older doses that a newer record has replaced.
    let isCurrent: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(vaccination.name).font(.body.weight(.medium))
                Text("Given \(Fmt.date(vaccination.dateGiven))" + (vaccination.vet.isEmpty ? "" : " · \(vaccination.vet)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let due = vaccination.nextDue {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.date(due))
                        .font(.subheadline)
                        .foregroundStyle(dueColor(due))
                    Text(isCurrent ? Fmt.relativeDue(due) : "replaced")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .opacity(isCurrent ? 1 : 0.55)
        .contentShape(Rectangle())
        .help(isCurrent ? "" : "A newer dose of this vaccine has been recorded")
    }

    private func dueColor(_ date: Date) -> Color {
        guard isCurrent else { return .secondary }
        let status = DueStatus(date)
        return status == .later ? .primary : status.color
    }
}

struct TreatmentRow: View {
    let treatment: Treatment
    let onGiven: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Pill(treatment.kind.label, tint: .accentColor)
                    Text(treatment.name).font(.body.weight(.medium))
                }
                if !treatment.summary.isEmpty {
                    Text(treatment.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            Spacer(minLength: 8)
            if treatment.active {
                Button("Given", systemImage: "checkmark", action: onGiven)
                    .help("Mark as given today and move the next due date forward")
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.green)
            }
        }
        .opacity(treatment.active ? 1 : 0.55)
        .contentShape(Rectangle())
    }

    private var statusLine: String {
        if !treatment.active { return "Stopped" }
        var parts: [String] = []
        if let last = treatment.lastGiven { parts.append("Last \(Fmt.date(last))") }
        if let due = treatment.nextDue { parts.append("next \(Fmt.date(due)) (\(Fmt.relativeDue(due)))") }
        if let end = treatment.endDate { parts.append("until \(Fmt.date(end))") }
        return parts.isEmpty ? "No dates set" : parts.joined(separator: " · ")
    }

    private var statusColor: Color {
        guard treatment.active, let due = treatment.nextDue else { return .secondary }
        let status = DueStatus(due)
        return status == .later ? .secondary : status.color
    }
}
