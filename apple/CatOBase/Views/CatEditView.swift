import PhotosUI
import SwiftData
import SwiftUI

/// Add or edit a cat. Changes are kept in a draft and only written on Save.
struct CatEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let cat: Cat?
    @State private var draft: CatDraft
    @State private var photoItem: PhotosPickerItem?
    @State private var newPhoto: ImageTools.Prepared?
    @State private var newPhotoPreview: CGImage?
    @State private var loadingPhoto = false
    @State private var photoError = false
    @State private var showingLibrary = false
    @State private var showingCamera = false

    init(cat: Cat?, startAsGuest: Bool = false) {
        self.cat = cat
        _draft = State(initialValue: CatDraft(cat, startAsGuest: startAsGuest))
    }

    private var currentAvatar: CGImage? {
        newPhotoPreview ?? cat?.profilePhoto?.thumbnailImage
    }

    private var title: LocalizedStringKey {
        if cat != nil { return "Edit Pet" }
        return draft.isGuest ? "New Guest Pet" : "New Pet"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        AvatarCircle(image: currentAvatar, size: 120, species: draft.species)
                            .overlay {
                                if loadingPhoto { ProgressView() }
                            }
                        Menu(currentAvatar == nil ? "Add Photo" : "Change Photo") {
                            #if os(iOS)
                            if CameraPicker.isAvailable {
                                Button {
                                    showingCamera = true
                                } label: {
                                    Label("Take Photo", systemImage: "camera")
                                }
                            }
                            #endif
                            Button {
                                showingLibrary = true
                            } label: {
                                Label("Choose from Library", systemImage: "photo.on.rectangle")
                            }
                        }
                        .fixedSize()
                        .help("Take a photo or choose one from your library")
                        .photosPicker(isPresented: $showingLibrary, selection: $photoItem, matching: .images)
                        #if os(iOS)
                        .fullScreenCover(isPresented: $showingCamera) {
                            CameraPicker { data in
                                process(data)
                            }
                            .ignoresSafeArea()
                        }
                        #endif
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("Basics") {
                    TextField("Name", text: $draft.name)
                    Picker("Species", selection: $draft.species) {
                        ForEach(Species.allCases) { species in
                            Label {
                                Text(species.label)
                            } icon: {
                                SpeciesIcon(species: species)
                            }
                            .tag(species)
                        }
                    }
                    Picker("Sex", selection: $draft.sex) {
                        ForEach(CatSex.allCases) { sex in
                            Text(sex.label).tag(sex)
                        }
                    }
                    Toggle("Neutered / spayed", isOn: $draft.neutered)
                    TextField("Breed", text: $draft.breed, prompt: Text(draft.species.breedHint))
                    TextField("Colour & markings", text: $draft.markings, prompt: Text("e.g. tabby, white socks"))
                    TextField("Microchip number", text: $draft.microchip)
                        .autocorrectionDisabled()
                }

                guestSections

                Section("Dates") {
                    OptionalDatePicker("Birthday", date: $draft.birthday)
                    if draft.birthday != nil {
                        Toggle("Birthday is approximate", isOn: $draft.birthdayApprox)
                    }
                    OptionalDatePicker("Gotcha day", date: $draft.adoptionDate)
                }

                Section("Health") {
                    TextField("Special needs", text: $draft.specialNeeds,
                              prompt: Text("Kidney diet, deaf in one ear, needs a ramp…"), axis: .vertical)
                        .lineLimit(2...6)
                    TextField("Allergies / intolerances", text: $draft.allergies, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section("Food") {
                    TextField("Food & brand", text: $draft.foodBrand)
                    TextField("Portion", text: $draft.foodPortion, prompt: Text("e.g. ½ pouch + 30 g dry"))
                    TextField("Schedule", text: $draft.foodSchedule, prompt: Text("e.g. 08:00 and 20:00"))
                    TextField("Special food needs, treats, refuses…", text: $draft.foodNotes, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section("Notes") {
                    TextField("Personality, quirks, how to give pills…", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...10)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(draft.name.trimmed.isEmpty || loadingPhoto)
                }
            }
            .onChange(of: photoItem) { _, item in
                loadPhoto(item)
            }
            .alert("Couldn't use that photo", isPresented: $photoError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Try a different photo.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }

    @ViewBuilder
    private var guestSections: some View {
        Section {
            Toggle("Guest pet", isOn: $draft.isGuest.animation())
                .help("For a pet you're looking after for someone else")
            if draft.isGuest {
                TextField("Owner's name", text: $draft.guestFrom, prompt: Text("e.g. Anna"))
                DatePicker("Staying since", selection: $draft.guestSince, displayedComponents: .date)
            }
        } header: {
            Text("Guest")
        } footer: {
            Text(draft.isGuest
                 ? "Listed under Guest Pets. The contacts below appear on this pet's page and sitter sheet."
                 : "Turn on for a pet you're looking after, like a friend's cat or dog you're babysitting.")
        }

        if draft.isGuest {
            Section("Owner's contacts") {
                ForEach($draft.guestContacts) { $contact in
                    VStack(spacing: 6) {
                        TextField("Role", text: $contact.role, prompt: Text("Owner, their vet…"))
                            .font(.caption.weight(.semibold))
                        TextField("Name", text: $contact.name)
                        TextField("Phone", text: $contact.phone)
                            #if os(iOS)
                            .keyboardType(.phonePad)
                            #endif
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { draft.guestContacts.remove(atOffsets: $0) }
                Button {
                    let owner = String(localized: "Owner")
                    let hasOwner = draft.guestContacts.contains {
                        $0.role.lowercased() == "owner" || $0.role.lowercased() == owner.lowercased()
                    }
                    let role = hasOwner ? String(localized: "Vet") : owner
                    draft.guestContacts.append(GuestContactDraft(role: role))
                } label: {
                    Label("Add Contact", systemImage: "plus")
                }
                .help("Add the owner, their vet or an emergency contact")
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        loadingPhoto = true
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                process(data)
            } else {
                loadingPhoto = false
                photoError = true
            }
        }
    }

    /// Resizes the photo and centres the avatar on the cat, off the main thread.
    private func process(_ data: Data) {
        loadingPhoto = true
        Task {
            let prepared = await Task.detached(priority: .userInitiated) {
                ImageTools.prepare(data)
            }.value
            if let prepared {
                newPhoto = prepared
                newPhotoPreview = ImageTools.downsample(prepared.thumbnail, maxPixels: ImageTools.avatarPixels)
            } else {
                photoError = true
            }
            loadingPhoto = false
        }
    }

    private func save() {
        let target: Cat
        if let cat {
            target = cat
        } else {
            target = Cat()
            context.insert(target)
        }
        draft.apply(to: target)

        if let newPhoto {
            let photo = CatPhoto.make(from: newPhoto)
            context.insert(photo)
            photo.cat = target
            target.profilePhotoID = photo.uuid
        }

        try? context.save()
        dismiss()
    }
}

/// Editable copy of a cat's own fields.
struct CatDraft {
    var name = ""
    var species: Species = .cat
    var sex: CatSex = .unknown
    var neutered = false
    var breed = ""
    var markings = ""
    var microchip = ""
    var birthday: Date?
    var birthdayApprox = false
    var adoptionDate: Date?
    var specialNeeds = ""
    var allergies = ""
    var foodBrand = ""
    var foodPortion = ""
    var foodSchedule = ""
    var foodNotes = ""
    var notes = ""
    var isGuest = false
    var guestFrom = ""
    var guestSince = Date()
    var guestContacts: [GuestContactDraft] = []

    init(_ cat: Cat?, startAsGuest: Bool = false) {
        guard let cat else {
            if startAsGuest {
                isGuest = true
                guestContacts = [GuestContactDraft(role: String(localized: "Owner"))]
            }
            return
        }
        isGuest = cat.isGuest
        guestFrom = cat.guestFrom
        guestSince = cat.guestReceivedAt ?? Date()
        guestContacts = cat.guestContacts.map { GuestContactDraft($0) }
        name = cat.name
        species = cat.species
        sex = cat.sex
        neutered = cat.neutered
        breed = cat.breed
        markings = cat.markings
        microchip = cat.microchip
        birthday = cat.birthday
        birthdayApprox = cat.birthdayApprox
        adoptionDate = cat.adoptionDate
        specialNeeds = cat.specialNeeds
        allergies = cat.allergies
        foodBrand = cat.foodBrand
        foodPortion = cat.foodPortion
        foodSchedule = cat.foodSchedule
        foodNotes = cat.foodNotes
        notes = cat.notes
    }

    func apply(to cat: Cat) {
        cat.name = name.trimmed
        cat.species = species
        cat.sex = sex
        cat.neutered = neutered
        cat.breed = breed.trimmed
        cat.markings = markings.trimmed
        cat.microchip = microchip.trimmed
        cat.birthday = birthday
        cat.birthdayApprox = birthday != nil && birthdayApprox
        cat.adoptionDate = adoptionDate
        cat.specialNeeds = specialNeeds.trimmed
        cat.allergies = allergies.trimmed
        cat.foodBrand = foodBrand.trimmed
        cat.foodPortion = foodPortion.trimmed
        cat.foodSchedule = foodSchedule.trimmed
        cat.foodNotes = foodNotes.trimmed
        cat.notes = notes.trimmed

        cat.isGuest = isGuest
        if isGuest {
            cat.guestFrom = guestFrom.trimmed
            cat.guestReceivedAt = guestSince
            let contacts = guestContacts.map(\.dto).filter { !$0.name.isEmpty || !$0.phone.isEmpty }
            cat.guestContactsData = contacts.isEmpty ? nil : try? JSONEncoder().encode(contacts)
        } else {
            cat.guestFrom = ""
            cat.guestReceivedAt = nil
            cat.guestContactsData = nil
        }
    }
}

/// An editable contact row for a guest cat.
struct GuestContactDraft: Identifiable {
    let id = UUID()
    var role = ""
    var name = ""
    var phone = ""
    var address = ""
    var notes = ""

    init(role: String = "") {
        self.role = role
    }

    init(_ dto: ContactDTO) {
        role = dto.role
        name = dto.name
        phone = dto.phone
        address = dto.address
        notes = dto.notes
    }

    var dto: ContactDTO {
        ContactDTO(role: role.trimmed, name: name.trimmed, phone: phone.trimmed,
                   address: address.trimmed, notes: notes.trimmed)
    }
}

#Preview {
    CatEditView(cat: nil)
        .modelContainer(PreviewData.container)
}
