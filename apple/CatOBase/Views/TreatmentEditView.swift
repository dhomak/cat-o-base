import SwiftData
import SwiftUI

struct TreatmentEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let cat: Cat
    let treatment: Treatment?

    @State private var kind: TreatmentKind
    @State private var name: String
    @State private var dose: String
    @State private var schedule: String
    @State private var repeats: Bool
    @State private var intervalDays: Int
    @State private var lastGiven: Date?
    @State private var manualDue: Date?
    @State private var endDate: Date?
    @State private var active: Bool
    @State private var notes: String
    @State private var confirmingDelete = false

    private static let presets: [(String, Int)] = [("Daily", 1), ("Weekly", 7), ("Monthly", 30), ("3 months", 90)]

    init(cat: Cat, treatment: Treatment?) {
        self.cat = cat
        self.treatment = treatment
        _kind = State(initialValue: treatment?.kind ?? .medication)
        _name = State(initialValue: treatment?.name ?? "")
        _dose = State(initialValue: treatment?.dose ?? "")
        _schedule = State(initialValue: treatment?.schedule ?? "")
        _repeats = State(initialValue: (treatment?.intervalDays ?? 0) > 0)
        _intervalDays = State(initialValue: treatment?.intervalDays ?? 30)
        _lastGiven = State(initialValue: treatment == nil ? Date() : treatment?.lastGiven)
        _manualDue = State(initialValue: treatment?.nextDue)
        _endDate = State(initialValue: treatment?.endDate)
        _active = State(initialValue: treatment?.active ?? true)
        _notes = State(initialValue: treatment?.notes ?? "")
    }

    /// Repeating with a last-given date: computed. Otherwise: the date picked by hand.
    private var computedNextDue: Date? {
        if repeats, let lastGiven {
            return Calendar.current.date(byAdding: .day, value: intervalDays, to: lastGiven)
        }
        return manualDue
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(TreatmentKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    TextField("Name", text: $name, prompt: Text("e.g. Bravecto, Milbemax"))
                    TextField("Dose", text: $dose, prompt: Text("e.g. ½ tablet"))
                    TextField("Schedule", text: $schedule, prompt: Text("e.g. twice daily with food"))
                }

                Section("Repeats") {
                    Toggle("Repeats on a schedule", isOn: $repeats)
                    if repeats {
                        Stepper(value: $intervalDays, in: 1...730) {
                            Text(Fmt.interval(days: intervalDays).capitalizedFirst)
                        }
                        HStack {
                            ForEach(Self.presets, id: \.1) { preset in
                                Button(preset.0) { intervalDays = preset.1 }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .tint(intervalDays == preset.1 ? .accentColor : .secondary)
                            }
                        }
                    }
                }

                Section("Dates") {
                    OptionalDatePicker("Last given", date: $lastGiven)
                    if repeats && lastGiven != nil {
                        LabeledContent("Next due", value: Fmt.date(computedNextDue))
                    } else {
                        OptionalFutureDatePicker(repeats ? "First due" : "Due on", date: $manualDue)
                    }
                    OptionalFutureDatePicker("Course ends", date: $endDate)
                }

                Section {
                    TextField("Notes", text: $notes, prompt: Text("How to give it, side effects to watch…"),
                              axis: .vertical)
                        .lineLimit(2...6)
                    if treatment != nil {
                        Toggle("Active", isOn: $active)
                    }
                }

                if treatment != nil {
                    Section {
                        Button("Delete Treatment", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(treatment == nil ? "New Treatment" : "Edit Treatment")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmed.isEmpty)
                }
            }
            .confirmationDialog("Delete this treatment?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let treatment { context.delete(treatment) }
                    try? context.save()
                    dismiss()
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    private func save() {
        let target: Treatment
        if let treatment {
            target = treatment
        } else {
            target = Treatment()
            context.insert(target)
            target.cat = cat
        }
        target.kind = kind
        target.name = name.trimmed
        target.dose = dose.trimmed
        target.schedule = schedule.trimmed
        target.intervalDays = repeats ? intervalDays : nil
        target.lastGiven = lastGiven
        target.nextDue = computedNextDue
        target.endDate = endDate
        target.active = active
        target.notes = notes.trimmed
        try? context.save()
        dismiss()
    }
}

/// Like OptionalDatePicker, but allows future dates.
struct OptionalFutureDatePicker: View {
    let title: String
    @Binding var date: Date?

    init(_ title: String, date: Binding<Date?>) {
        self.title = title
        self._date = date
    }

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { date != nil },
            set: { isOn in date = isOn ? (date ?? Date()) : nil }
        ))
        if date != nil {
            DatePicker(
                "Date",
                selection: Binding(get: { date ?? Date() }, set: { date = $0 }),
                displayedComponents: .date
            )
        }
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

#Preview {
    TreatmentEditView(cat: PreviewData.murka, treatment: nil)
        .modelContainer(PreviewData.container)
}
