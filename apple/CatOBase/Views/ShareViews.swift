import SwiftData
import SwiftUI

// MARK: - Sending

/// Choose what to share, then send a `.catobase` file plus a readable summary
/// through the standard share sheet.
struct CatShareView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Contact.role), SortDescriptor(\Contact.name)]) private var contacts: [Contact]
    @AppStorage(PrefKey.sharerName) private var sender = ""
    @AppStorage(PrefKey.weightUnit) private var unit: WeightUnit = .kg

    let cat: Cat
    @State private var options = ShareOptions()
    @State private var fileURL: URL?
    @State private var fileSize: Int?
    @State private var building = false

    private var photoCount: Int { cat.photos?.count ?? 0 }
    private var documentCount: Int { cat.documents?.count ?? 0 }
    private var contactCount: Int { cat.isGuest ? cat.guestContacts.count : contacts.count }

    private var summary: String {
        CatShareBuilder.summary(for: cat, options: options, sender: sender,
                                ownContacts: contacts, unit: unit)
    }

    private var buildKey: String {
        "\(options.hashValue)|\(sender)|\(photoCount)|\(documentCount)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $sender, prompt: Text("e.g. David"))
                } footer: {
                    Text("Shown to the person you share with, so they know who \(cat.displayName) is from.")
                }

                Section("Include") {
                    Picker("Photos", selection: $options.photos) {
                        ForEach(ShareOptions.Photos.allCases) { choice in
                            Text(choice == .all ? String(localized: "All photos (\(photoCount))") : choice.label).tag(choice)
                        }
                    }
                    Toggle("Breed, markings, microchip", isOn: $options.details)
                    Toggle("Special needs & allergies", isOn: $options.specialNeeds)
                    Toggle("Food", isOn: $options.food)
                    Toggle("Vaccinations & medications", isOn: $options.health)
                    Toggle("Weight history", isOn: $options.weight)
                    Toggle("Vet visits", isOn: $options.visits)
                    Toggle("Documents (\(documentCount))", isOn: $options.documents)
                        .disabled(documentCount == 0)
                    Toggle("Journal", isOn: $options.journal)
                    Toggle("Notes", isOn: $options.notes)
                    Toggle("Contacts (\(contactCount))", isOn: $options.contacts)
                        .disabled(contactCount == 0)
                }

                Section {
                    if let fileURL, !building {
                        ShareLink(item: fileURL,
                                  subject: Text(cat.displayName),
                                  message: Text(summary),
                                  preview: SharePreview("\(cat.displayName).petobase", image: previewImage)) {
                            shareRow("Share File and Text", detail: "Messages, Mail, AirDrop",
                                     systemImage: "square.and.arrow.up")
                        }
                        .help("Sends the pet file with the readable summary")

                        ShareLink(item: fileURL,
                                  preview: SharePreview("\(cat.displayName).petobase", image: previewImage)) {
                            shareRow("Share File Only", detail: "Telegram, WhatsApp and apps that drop the text",
                                     systemImage: "doc")
                        }
                        .help("Some apps, like Telegram, send only the text when given both. Use this there.")
                    } else {
                        HStack {
                            ProgressView()
                            Text("Preparing…").foregroundStyle(.secondary)
                        }
                    }
                    ShareLink(item: summary, subject: Text(cat.displayName)) {
                        shareRow("Share Text Only", detail: "For people without Pet-o-Base",
                                 systemImage: "text.bubble")
                    }
                    .help("Just the readable summary, no file")
                } footer: {
                    if let fileSize {
                        Text("File size: \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)). Anyone with Pet-o-Base can open the file to add \(cat.displayName) to their Guest Pets. In Telegram, send the file and the text separately.")
                    }
                }

                Section("Message preview") {
                    Text(summary)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Share \(cat.displayName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: buildKey) {
                building = true
                // Small pause so flipping several toggles builds once.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                let url = await CatShareBuilder.makeFile(for: cat, options: options, sender: sender,
                                                         ownContacts: contacts, context: context)
                guard !Task.isCancelled else { return }
                fileURL = url
                fileSize = url.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
                building = false
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 640)
        #endif
    }

    private func shareRow(_ title: LocalizedStringKey, detail: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }

    private var previewImage: Image {
        if let image = cat.profilePhoto?.thumbnailImage {
            return Image(decorative: image, scale: 1)
        }
        return Image(systemName: "pawprint.fill")
    }
}

// MARK: - Receiving

struct GuestReceiveView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let share: ReceivedShare
    @State private var existing: Cat?
    @State private var working = false
    @State private var failure: String?

    private var cat: CatDTO { share.cat }
    private var sender: String { share.file.sharedBy ?? "" }

    private var avatar: CGImage? {
        let photo = cat.photos.first { $0.uuid == cat.profilePhotoID } ?? cat.photos.first
        guard let data = photo?.thumbnail ?? photo?.image else { return nil }
        return ImageTools.downsample(data, maxPixels: ImageTools.avatarPixels)
    }

    private var included: [String] {
        var items: [String] = []
        let photos = cat.photos.count, vaccinations = cat.vaccinations.count
        let treatments = cat.treatments.count, weighIns = cat.weights.count
        let visits = cat.visits.count, documents = cat.documents.count
        let entries = cat.journal.count, contacts = share.file.contacts.count
        if photos > 0 { items.append(String(localized: "\(photos) photos")) }
        if vaccinations > 0 { items.append(String(localized: "\(vaccinations) vaccinations")) }
        if treatments > 0 { items.append(String(localized: "\(treatments) treatments")) }
        if weighIns > 0 { items.append(String(localized: "\(weighIns) weigh-ins")) }
        if visits > 0 { items.append(String(localized: "\(visits) vet visits")) }
        if documents > 0 { items.append(String(localized: "\(documents) documents")) }
        if entries > 0 { items.append(String(localized: "\(entries) journal entries")) }
        if contacts > 0 { items.append(String(localized: "\(contacts) contacts")) }
        return items
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        AvatarCircle(image: avatar, size: 110,
                                     species: Species(rawValue: cat.species ?? "cat") ?? .other)
                        Text(cat.name.isEmpty ? String(localized: "Unnamed pet") : cat.name)
                            .font(.title.bold())
                        Text(sender.isEmpty ? "Shared with you" : "Shared by \(sender)")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("Included") {
                    if included.isEmpty {
                        Text("Basic details only").foregroundStyle(.secondary)
                    } else {
                        Text(included.joined(separator: ", "))
                    }
                    if !cat.specialNeeds.isEmpty {
                        CalloutRow(title: "Special needs", text: cat.specialNeeds,
                                   systemImage: "exclamationmark.triangle.fill")
                    }
                }

                if let existing {
                    Section {
                        Text(existing.guestFrom.isEmpty
                             ? "You already have \(existing.displayName), received \(Fmt.date(existing.guestReceivedAt)). Updating replaces that copy, including any changes you made to it."
                             : "You already have \(existing.displayName) from \(existing.guestFrom), received \(Fmt.date(existing.guestReceivedAt)). Updating replaces that copy, including any changes you made to it.")
                            .font(.callout)
                        Button {
                            add(replacing: existing)
                        } label: {
                            Label("Update \(existing.displayName)", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(working)
                        Button("Keep Both") { add(replacing: nil) }
                            .disabled(working)
                    }
                } else {
                    Section {
                        Button {
                            add(replacing: nil)
                        } label: {
                            Label("Add to Guest Pets", systemImage: "plus.circle.fill")
                        }
                        .disabled(working)
                    } footer: {
                        Text("It's your own copy: you can edit it, and your changes stay on this device.")
                    }
                }

                if working {
                    HStack {
                        ProgressView()
                        Text("Adding…").foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Shared Pet")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Couldn't add the pet", isPresented: Binding(
                get: { failure != nil },
                set: { if !$0 { failure = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
            .onAppear {
                existing = GuestImporter.existingGuest(for: share, in: context)
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    private func add(replacing old: Cat?) {
        working = true
        Task {
            do {
                let cat = try await GuestImporter.add(share, replacing: old, in: context)
                NotificationRouter.shared.pendingCatID = cat.persistentModelID
                dismiss()
            } catch {
                failure = error.localizedDescription
            }
            working = false
        }
    }
}
