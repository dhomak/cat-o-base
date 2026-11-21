import SwiftData
import SwiftUI

struct CatDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let cat: Cat

    @State private var editing = false
    @State private var confirmingDelete = false

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
        .confirmationDialog("Delete \(cat.displayName)?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete Cat and All Records", role: .destructive, action: deleteCat)
        } message: {
            Text("This permanently deletes every record and photo for this cat. Archiving hides the cat but keeps everything.")
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
