import QuickLook
import SwiftData
import SwiftUI

struct CatDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let cat: Cat

    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var healthSheet: HealthSheet?
    @AppStorage(PrefKey.weightUnit) private var unit: WeightUnit = .kg
    @State private var viewer: PhotoViewerStart?
    @State private var cropTarget: CatPhoto?
    @State private var pendingCrop: CatPhoto?
    @State private var sitterSheetURL: URL?
    @State private var sharing = false
    @State private var dropTargeted = false

    enum HealthSheet: Identifiable, Hashable {
        case newVaccination, editVaccination(Vaccination)
        case newTreatment, editTreatment(Treatment)
        case logWeight
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

            if cat.isGuest {
                guestSection
            }

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

            Section(title: "Details") {
                LabeledContent("Sex", value: sexText)
                LabeledContent("Born", value: bornText)
                LabeledContent("Gotcha day", value: Fmt.date(cat.adoptionDate))
                LabeledContent("Weight", value: cat.latestWeight.map { unit.format(kilograms: $0.kg) } ?? "—")
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
            WeightSection(cat: cat) { healthSheet = .logWeight }
            PhotosSection(cat: cat) { index in viewer = PhotoViewerStart(index: index) }
            DocumentsSection(cat: cat)

            Section(title: "Food") {
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
                Section(title: "Notes") {
                    Text(cat.notes).textSelection(.enabled)
                }
            }
        }
        .comfortableListOnMac()
        .navigationTitle(cat.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    sharing = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Send \(cat.displayName) to someone: choose what to include")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = true }
                    #if os(iOS)
                    .keyboardShortcut("e", modifiers: .command)
                    #endif
                    .help("Edit details (⌘E)")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    sitterSheetURL = SitterSheetPDF.make(in: context, cats: [cat])
                } label: {
                    Label("Sitter Sheet", systemImage: "doc.text.image")
                }
                .help("Make a printable care sheet for this cat")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    cat.archived.toggle()
                } label: {
                    Label(cat.archived ? "Unarchive" : "Archive",
                          systemImage: cat.archived ? "tray.and.arrow.up" : "archivebox")
                }
                .help(cat.archived ? "Move back to the main list" : "Hide from the main list but keep all records")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label(cat.isGuest ? "Remove Guest Cat" : "Delete Cat", systemImage: "trash")
                }
                .help("Delete this cat and all its records")
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
            case .logWeight:
                WeightEntryEditView(cat: cat, entry: nil)
            }
        }
        .coverOrSheet(item: $viewer, onDismiss: {
            // "Use as Profile Photo" closes the viewer first, then opens the crop editor.
            if let photo = pendingCrop {
                pendingCrop = nil
                cropTarget = photo
            }
        }) { start in
            PhotoViewer(cat: cat, startIndex: start.index) { photo in
                pendingCrop = photo
            }
        }
        .sheet(item: $cropTarget) { photo in
            AvatarCropView(photo: photo)
        }
        .quickLookPreview($sitterSheetURL)
        .sheet(isPresented: $sharing) {
            CatShareView(cat: cat)
        }
        // Menu bar (Mac) and hardware-keyboard commands for this cat.
        .focusedSceneValue(\.catActions, CatActions(
            name: cat.displayName,
            id: cat.persistentModelID,
            edit: { editing = true },
            logWeight: { healthSheet = .logWeight },
            addVaccination: { healthSheet = .newVaccination },
            addTreatment: { healthSheet = .newTreatment },
            share: { sharing = true },
            sitterSheet: { sitterSheetURL = SitterSheetPDF.make(in: context, cats: [cat]) }
        ))
        // Drop photos, PDFs or other files onto the page.
        .onDrop(of: CatMedia.dropTypes, isTargeted: $dropTargeted) { providers in
            CatMedia.handleDrop(providers, cat: cat, context: context)
            return true
        }
        .overlay {
            if dropTargeted { DropHighlight(catName: cat.displayName) }
        }
        #if os(macOS)
        // File → Import from iPhone → Take Photo / Scan Documents.
        .importableFromServices(for: ContinuityImport.self) { imports in
            let items = imports.map(\.incoming)
            Task { await CatMedia.add(items, to: cat, in: context) }
            return true
        }
        #endif
        .confirmationDialog("Delete \(cat.displayName)?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete Cat and All Records", role: .destructive, action: deleteCat)
        } message: {
            Text("This permanently deletes every record and photo for this cat. Archiving hides the cat but keeps everything.")
        }
    }

    @ViewBuilder
    private var guestSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cat.guestFrom.isEmpty ? "Guest cat" : "Guest cat from \(cat.guestFrom)")
                        .font(.body.weight(.medium))
                    Text(cat.shareID == nil
                         ? "Staying since \(Fmt.date(cat.guestReceivedAt))."
                         : "Received \(Fmt.date(cat.guestReceivedAt)). Your own copy: edits stay on this device, and a new share from the owner can update it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "person.2.fill").foregroundStyle(.teal)
            }
        }
        let contacts = cat.guestContacts
        if !contacts.isEmpty {
            Section(title: cat.guestFrom.isEmpty ? "Contacts" : "Contacts from \(cat.guestFrom)") {
                ForEach(Array(contacts.enumerated()), id: \.offset) { _, contact in
                    GuestContactRow(contact: contact)
                }
            }
        }
    }

    @ViewBuilder
    private var comingUpSection: some View {
        let due = cat.dueItems
        if !due.isEmpty {
            Section(title: "Coming up") {
                ForEach(due) { item in
                    DueRow(item: item, showCat: false)
                        .help("Swipe right or right-click to mark as given today")
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
        Section(title: "Vaccinations") {
            let all = sortedVaccinations
            ForEach(all) { vaccination in
                VaccinationRow(vaccination: vaccination, isCurrent: vaccination.isCurrent(among: all))
                    .help("Click to edit. Right-click to record the next dose or delete.")
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
            .help("Record a vaccination")
        }
    }

    private var treatmentsSection: some View {
        Section(title: "Medications & treatments") {
            ForEach(sortedTreatments) { treatment in
                TreatmentRow(treatment: treatment) {
                    withAnimation { treatment.markGiven() }
                }
                .onTapGesture { healthSheet = .editTreatment(treatment) }
                .help("Click to edit. Right-click to stop, resume or delete.")
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
            .help("Add a medication, flea/tick or deworming treatment, or supplement")
        }
    }

    private var header: some View {
        Section {
            VStack(spacing: 10) {
                CatAvatar(cat: cat, size: 140)
                    .overlay(alignment: .bottomTrailing) {
                        if cat.profilePhoto != nil {
                            Image(systemName: "crop")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(7)
                                .background(Color.accentColor, in: Circle())
                                .offset(x: -4, y: -4)
                        }
                    }
                    .onTapGesture {
                        if let photo = cat.profilePhoto { cropTarget = photo }
                    }
                    .accessibilityAddTraits(cat.profilePhoto != nil ? .isButton : [])
                    .accessibilityLabel("Adjust profile photo")
                    .help(cat.profilePhoto != nil ? "Adjust the round profile photo" : "Add photos below, or choose one in Edit")
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
