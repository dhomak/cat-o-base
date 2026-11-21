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

    init(cat: Cat?) {
        self.cat = cat
        _draft = State(initialValue: CatDraft(cat))
    }

    private var currentAvatar: CGImage? {
        newPhotoPreview ?? cat?.profilePhoto?.thumbnailImage
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        AvatarCircle(image: currentAvatar, size: 120)
                            .overlay {
                                if loadingPhoto { ProgressView() }
                            }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Text(currentAvatar == nil ? "Add Photo" : "Change Photo")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("Basics") {
                    TextField("Name", text: $draft.name)
                    Picker("Sex", selection: $draft.sex) {
                        ForEach(CatSex.allCases) { sex in
                            Text(sex.label).tag(sex)
                        }
                    }
                    Toggle("Neutered / spayed", isOn: $draft.neutered)
                    TextField("Breed", text: $draft.breed, prompt: Text("e.g. domestic shorthair"))
                    TextField("Colour & markings", text: $draft.markings, prompt: Text("e.g. tabby, white socks"))
                    TextField("Microchip number", text: $draft.microchip)
                        .autocorrectionDisabled()
                }

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
            .navigationTitle(cat == nil ? "New Cat" : "Edit Cat")
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

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        loadingPhoto = true
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            let prepared = await Task.detached(priority: .userInitiated) {
                data.flatMap { ImageTools.prepare($0) }
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
            let photo = CatPhoto(imageData: newPhoto.full, thumbnailData: newPhoto.thumbnail)
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

    init(_ cat: Cat?) {
        guard let cat else { return }
        name = cat.name
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
    }
}

#Preview {
    CatEditView(cat: nil)
        .modelContainer(PreviewData.container)
}
