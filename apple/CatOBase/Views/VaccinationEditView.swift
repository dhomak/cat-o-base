import SwiftData
import SwiftUI

enum VaccineRepeat: String, CaseIterable, Identifiable {
    case none, oneMonth, sixMonths, oneYear, threeYears, custom

    var id: String { rawValue }

    var months: Int? {
        switch self {
        case .oneMonth: return 1
        case .sixMonths: return 6
        case .oneYear: return 12
        case .threeYears: return 36
        case .none, .custom: return nil
        }
    }

    var label: String {
        switch self {
        case .none: return "Doesn't repeat"
        case .oneMonth: return "Booster in 1 month"
        case .sixMonths: return "Every 6 months"
        case .oneYear: return "Every year"
        case .threeYears: return "Every 3 years"
        case .custom: return "Pick a date"
        }
    }

    static func matching(months: Int?) -> VaccineRepeat? {
        allCases.first { $0.months != nil && $0.months == months }
    }
}

struct VaccinationEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let cat: Cat
    let vaccination: Vaccination?

    @State private var name: String
    @State private var dateGiven: Date?
    @State private var repeatChoice: VaccineRepeat
    @State private var customDue: Date
    @State private var vet: String
    @State private var notes: String
    @State private var confirmingDelete = false

    private static let suggestions = ["Rabies", "FVRCP (tricat)", "FeLV", "Chlamydia", "FIP"]

    init(cat: Cat, vaccination: Vaccination?) {
        self.cat = cat
        self.vaccination = vaccination
        _name = State(initialValue: vaccination?.name ?? "")
        _vet = State(initialValue: vaccination?.vet ?? "")
        _notes = State(initialValue: vaccination?.notes ?? "")
        if let vaccination {
            _dateGiven = State(initialValue: vaccination.dateGiven)
            _customDue = State(initialValue: vaccination.nextDue ?? Date())
            if let match = VaccineRepeat.matching(months: vaccination.repeatMonths) {
                _repeatChoice = State(initialValue: match)
            } else {
                _repeatChoice = State(initialValue: vaccination.nextDue == nil ? .none : .custom)
            }
        } else {
            _dateGiven = State(initialValue: Date())
            _customDue = State(initialValue: Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date())
            _repeatChoice = State(initialValue: .oneYear)
        }
    }

    private var computedNextDue: Date? {
        switch repeatChoice {
        case .none:
            return nil
        case .custom:
            return customDue
        default:
            guard let months = repeatChoice.months, let given = dateGiven else { return nil }
            return Calendar.current.date(byAdding: .month, value: months, to: given)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Vaccine", text: $name, prompt: Text("e.g. Rabies"))
                    SuggestionChips(suggestions: Self.suggestions) { name = $0 }
                }

                Section("When") {
                    OptionalDatePicker("Date given", date: $dateGiven)
                    Picker("Repeats", selection: $repeatChoice) {
                        ForEach(VaccineRepeat.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    if repeatChoice == .custom {
                        DatePicker("Next due", selection: $customDue, displayedComponents: .date)
                    } else {
                        LabeledContent("Next due", value: Fmt.date(computedNextDue))
                    }
                    if repeatChoice.months != nil && dateGiven == nil {
                        Text("Set the date given to work out the next due date.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField("Vet / clinic", text: $vet)
                    TextField("Notes", text: $notes, prompt: Text("Batch number, reaction…"), axis: .vertical)
                }

                if vaccination != nil {
                    Section {
                        Button("Delete Vaccination", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(vaccination == nil ? "New Vaccination" : "Edit Vaccination")
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
            .confirmationDialog("Delete this vaccination?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let vaccination { context.delete(vaccination) }
                    try? context.save()
                    dismiss()
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 460)
        #endif
    }

    private func save() {
        let target: Vaccination
        if let vaccination {
            target = vaccination
        } else {
            target = Vaccination()
            context.insert(target)
            target.cat = cat
        }
        target.name = name.trimmed
        target.dateGiven = dateGiven
        target.nextDue = computedNextDue
        target.vet = vet.trimmed
        target.notes = notes.trimmed
        try? context.save()
        dismiss()
    }
}

/// A horizontal row of quick-fill buttons.
struct SuggestionChips: View {
    let suggestions: [String]
    let pick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) { pick(suggestion) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }
}

#Preview {
    VaccinationEditView(cat: PreviewData.murka, vaccination: nil)
        .modelContainer(PreviewData.container)
}
