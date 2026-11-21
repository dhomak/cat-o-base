import SwiftData
import SwiftUI

struct CatDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let cat: Cat

    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var healthSheet: HealthSheet?

    enum HealthSheet: Identifiable, Hashable {
        case newVaccination, editVaccination(Vaccination)
        case newTreatment, editTreatment(Treatment)
        var id: Self { self }
    }

    private var sortedVaccinations: [Vaccination] {
        (cat.vaccinations ?? []).sorted { ($0.dateGiven ?? .distantPast) > ($1.dateGiven ?? .distantPast) }
    }

    private var sortedTreatments: [Treatment] {
        (cat.treatments ?? []).sorted { lhs, rhs in
            if lhs.active != rhs.active { return lhs.active }
            return (lhs.nextDue ?? .distantFuture) < (rhs.nextDue ?? .distantFuture)
        }
    }

    var body: some View {
        List {
            header

            if hasCallouts {
                Section {
                    if !cat.specialNeeds.trimmed.isEmpty {
                        CalloutRow(title: "Special needs", text: cat.specialNeeds,
                                   systemImage: "exclamationmark.triangle.fill")
                    }
                    if !cat.allergies.trimmed.isEmpty {
                        CalloutRow(title: "Allergies / intolerances", text: cat.allergies,
                                   systemImage: "allergens")
                    }
                }
            }

            comingUpSection

            Section("Details") {
                LabeledContent("Sex", value: sexText)
                LabeledContent("Born", value: bornText)
                LabeledContent("Gotcha day", value: Fmt.date(cat.adoptionDate))
                LabeledContent("Weight", value: cat.latestWeight.map { Fmt.kg($0.kg) } ?? "—")
                if !cat.breed.trimmed.isEmpty { LabeledContent("Breed", value: cat.breed) }
                if !cat.markings.trimmed.isEmpty { LabeledContent("Markings", value: cat.markings) }
                if !cat.microchip.trimmed.isEmpty {
                    LabeledContent("Microchip") {
                        Text(cat.microchip).monospaced().textSelection(.enabled)
                    }
                }
            }

            vaccinationsSection
            treatmentsSection

            Section("Food") {
                if hasFood {
                    if !cat.foodBrand.trimmed.isEmpty { LabeledContent("Food", value: cat.foodBrand) }
                    if !cat.foodPortion.trimmed.isEmpty { LabeledContent("Portion", value: cat.foodPortion) }
                    if !cat.foodSchedule.trimmed.isEmpty { LabeledContent("Schedule", value: cat.foodSchedule) }
                    if !cat.foodNotes.trimmed.isEmpty { Text(cat.foodNotes).textSelection(.enabled) }
                } else {
                    Text("No food details yet.").foregroundStyle(.secondary)
                }
            }

            if !cat.notes.trimmed.isEmpty {
                Section("Notes") {
                    Text(cat.notes).textSelection(.enabled)
                }
            }
        }
        .navigationTitle(cat.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = true }
                    .keyboardShortcut("e", modifiers: .command)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    cat.archived.toggle()
                } label: {
                    Label(cat.archived ? "Unarchive" : "Archive",
                          systemImage: cat.archived ? "tray.and.arrow.up" : "archivebox")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete Cat", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $editing) {
            CatEditView(cat: cat)
        }
        .sheet(item: $healthSheet) { sheet in
            switch sheet {
            case .newVaccination:
                VaccinationEditView(cat: cat, vaccination: nil)
            case .editVaccination(let vaccination):
                VaccinationEditView(cat: cat, vaccination: vaccination)
            case .newTreatment:
                TreatmentEditView(cat: cat, treatment: nil)
            case .editTreatment(let treatment):
                TreatmentEditView(cat: cat, treatment: treatment)
            }
        }
        .confirmationDialog("Delete \(cat.displayName)?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete Cat and All Records", role: .destructive, action: deleteCat)
        } message: {
            Text("This permanently deletes every record and photo for this cat. Archiving hides the cat but keeps everything.")
        }
    }

    @ViewBuilder
    private var comingUpSection: some View {
        let due = cat.dueItems
        if !due.isEmpty {
            Section("Coming up") {
                ForEach(due) { item in
                    DueRow(item: item, showCat: false)
                        .swipeActions(edge: .leading) {
                            Button {
                                withAnimation { DueActions.markGiven(item, in: context) }
                            } label: {
                                Label("Given today", systemImage: "checkmark")
                            }
                            .tint(.green)
                        }
                }
            }
        }
    }

    private var vaccinationsSection: some View {
        Section("Vaccinations") {
            let all = sortedVaccinations
            ForEach(all) { vaccination in
                VaccinationRow(vaccination: vaccination, isCurrent: vaccination.isCurrent(among: all))
                    .onTapGesture { healthSheet = .editVaccination(vaccination) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            context.delete(vaccination)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button("Edit") { healthSheet = .editVaccination(vaccination) }
                        if vaccination.isCurrent(among: all) {
                            Button("Record Next Dose Today") {
                                vaccination.recordNextDose(in: context)
                            }
                        }
                        Button("Delete", role: .destructive) { context.delete(vaccination) }
                    }
            }
            Button {
                healthSheet = .newVaccination
            } label: {
                Label("Add Vaccination", systemImage: "plus")
            }
        }
    }

    private var treatmentsSection: some View {
        Section("Medications & treatments") {
            ForEach(sortedTreatments) { treatment in
                TreatmentRow(treatment: treatment) {
                    withAnimation { treatment.markGiven() }
                }
                .onTapGesture { healthSheet = .editTreatment(treatment) }
                .swipeActions(edge: .leading) {
                    if treatment.active {
                        Button {
                            withAnimation { treatment.markGiven() }
                        } label: {
                            Label("Given", systemImage: "checkmark")
                        }
                        .tint(.green)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        context.delete(treatment)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        treatment.active.toggle()
                    } label: {
                        Label(treatment.active ? "Stop" : "Resume",
                              systemImage: treatment.active ? "stop.circle" : "play.circle")
                    }
                    .tint(.gray)
                }
                .contextMenu {
                    Button("Edit") { healthSheet = .editTreatment(treatment) }
                    if treatment.active {
                        Button("Given Today") { treatment.markGiven() }
                    }
                    Button(treatment.active ? "Stop" : "Resume") { treatment.active.toggle() }
                    Button("Delete", role: .destructive) { context.delete(treatment) }
                }
            }
            Button {
                healthSheet = .newTreatment
            } label: {
                Label("Add Medication or Treatment", systemImage: "plus")
            }
        }
    }

    private var header: some View {
        Section {
            VStack(spacing: 10) {
                CatAvatar(cat: cat, size: 140)
                Text(cat.displayName)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                if let age = Fmt.age(from: cat.birthday) {
                    Text(cat.birthdayApprox ? "\(age) (approx.)" : age)
                        .foregroundStyle(.secondary)
                }
                if cat.archived { Pill("Archived") }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    private var hasCallouts: Bool {
        !cat.specialNeeds.trimmed.isEmpty || !cat.allergies.trimmed.isEmpty
    }

    private var hasFood: Bool {
        ![cat.foodBrand, cat.foodPortion, cat.foodSchedule, cat.foodNotes].allSatisfy { $0.trimmed.isEmpty }
    }

    private var sexText: String {
        let base = cat.sex == .unknown ? "—" : cat.sex.label
        return cat.neutered ? "\(base), neutered" : base
    }

    private var bornText: String {
        let date = Fmt.date(cat.birthday)
        return cat.birthday != nil && cat.birthdayApprox ? "≈ \(date)" : date
    }

    private func deleteCat() {
        // Leave the screen first so nothing reads the cat after it's deleted.
        dismiss()
        let doomed = cat
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            context.delete(doomed)
            try? context.save()
        }
    }
}

#Preview {
    NavigationStack {
        CatDetailView(cat: PreviewData.murka)
    }
    .modelContainer(PreviewData.container)
}
