import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    /// A single shared pet (`.petobase`; older `.catobase` files too). Declared in project.yml.
    static let catobaseCat = UTType(exportedAs: "com.arimanoff.catobase.cat")
}

extension PrefKey {
    static let sharerName = "sharerName"
}

// MARK: - What to include

struct ShareOptions: Hashable {
    enum Photos: String, CaseIterable, Identifiable {
        case none, profile, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: return String(localized: "None", comment: "No photos")
            case .profile: return String(localized: "Profile photo")
            case .all: return String(localized: "All photos")
            }
        }
    }

    var photos: Photos = .profile
    /// Breed, markings, microchip, gotcha day.
    var details = true
    var specialNeeds = true
    var food = true
    var notes = true
    /// Vaccinations and treatments.
    var health = true
    var weight = true
    var visits = false
    var documents = false
    var journal = false
    var contacts = true

    /// Strips everything not chosen from a full copy of the cat.
    func apply(to full: CatDTO, profilePhotoID: UUID?) -> CatDTO {
        var dto = full
        switch photos {
        case .none:
            dto.photos = []
            dto.profilePhotoID = nil
        case .profile:
            dto.photos = dto.photos.filter { $0.uuid == profilePhotoID }
            dto.profilePhotoID = dto.photos.first?.uuid
        case .all:
            break
        }
        if !details {
            dto.breed = ""
            dto.markings = ""
            dto.microchip = ""
            dto.adoptionDate = nil
        }
        if !specialNeeds {
            dto.specialNeeds = ""
            dto.allergies = ""
        }
        if !food {
            dto.foodBrand = ""
            dto.foodPortion = ""
            dto.foodSchedule = ""
            dto.foodNotes = ""
        }
        if !notes { dto.notes = "" }
        if !health {
            dto.vaccinations = []
            dto.treatments = []
        }
        if !weight { dto.weights = [] }
        if !visits { dto.visits = [] }
        if !documents { dto.documents = [] }
        if !journal { dto.journal = [] }
        dto.archived = false
        // The recipient's app fills these in.
        dto.isGuest = nil
        dto.guestFrom = nil
        dto.guestReceivedAt = nil
        dto.guestContacts = nil
        return dto
    }
}

// MARK: - Building a share

@MainActor
enum CatShareBuilder {
    /// Writes `<Name>.petobase` to a temporary folder. Assigns the cat a share ID the
    /// first time, so the recipient can later update their copy from a re-send.
    static func makeFile(for cat: Cat, options: ShareOptions, sender: String,
                         ownContacts: [Contact], context: ModelContext) async -> URL? {
        if cat.shareID == nil {
            cat.shareID = UUID()
            try? context.save()
        }
        let full = BackupExporter.dto(cat)
        var file = BackupFile()
        file.kind = BackupFile.catShareKind
        file.sharedBy = sender.trimmed.isEmpty ? nil : sender.trimmed
        file.cats = [options.apply(to: full, profilePhotoID: cat.profilePhoto?.uuid)]
        if options.contacts {
            // Re-sharing a guest cat passes its owner's contacts along.
            file.contacts = cat.isGuest ? cat.guestContacts : ownContacts.map(contactDTO)
        }

        let data = await Task.detached(priority: .userInitiated) {
            try? BackupFile.encoder().encode(file)
        }.value
        guard let data else { return nil }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-\(UUID().uuidString)", isDirectory: true)
        let safeName = cat.displayName.replacingOccurrences(of: "/", with: "-")
        let url = folder.appendingPathComponent("\(safeName).petobase")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    static func contactDTO(_ contact: Contact) -> ContactDTO {
        ContactDTO(role: contact.role, name: contact.name, phone: contact.phone,
                   address: contact.address, notes: contact.notes)
    }

    /// A readable message for people without the app (and a preview for those with it).
    static func summary(for cat: Cat, options: ShareOptions, sender: String,
                        ownContacts: [Contact], unit: WeightUnit) -> String {
        var lines: [String] = ["\(cat.species.emoji) \(cat.displayName)"]

        var facts: [String] = [cat.species.label.lowercased()]
        if let age = Fmt.age(from: cat.birthday) { facts.append(cat.birthdayApprox ? String(localized: "about \(age)", comment: "Approximate age") : age) }
        if cat.sex != .unknown { facts.append(cat.sex.label.lowercased() + (cat.neutered ? ", " + String(localized: "neutered") : "")) }
        if options.details {
            if !cat.breed.isEmpty { facts.append(cat.breed) }
            if !cat.markings.isEmpty { facts.append(cat.markings) }
        }
        if !facts.isEmpty { lines.append(facts.joined(separator: " · ")) }
        if options.details && !cat.microchip.isEmpty { lines.append(String(localized: "Microchip: \(cat.microchip)")) }

        if options.specialNeeds {
            if !cat.specialNeeds.isEmpty { lines.append("\n⚠️ " + String(localized: "Special needs: \(cat.specialNeeds)")) }
            if !cat.allergies.isEmpty { lines.append(String(localized: "Allergies: \(cat.allergies)")) }
        }

        if options.food {
            let food = [cat.foodBrand, cat.foodPortion, cat.foodSchedule].filter { !$0.isEmpty }
            if !food.isEmpty || !cat.foodNotes.isEmpty {
                lines.append("\n🍽 " + String(localized: "Food:") + (food.isEmpty ? "" : " " + food.joined(separator: ", ")))
                if !cat.foodNotes.isEmpty { lines.append(cat.foodNotes) }
            }
        }

        if options.health {
            let meds = (cat.treatments ?? []).filter(\.active)
            if !meds.isEmpty {
                lines.append("\n💊 " + String(localized: "Medication & treatments:"))
                for treatment in meds {
                    var line = "• \(treatment.name)"
                    if !treatment.summary.isEmpty { line += " (\(treatment.summary))" }
                    if let due = treatment.nextDue {
                        let dueText = Fmt.date(due)
                        line += ", " + String(localized: "next \(dueText)", comment: "Next dose date")
                    }
                    lines.append(line)
                }
            }
            let vaccines = cat.vaccinations ?? []
            let current = vaccines.filter { $0.isCurrent(among: vaccines) && $0.nextDue != nil }
            if !current.isEmpty {
                lines.append("\n💉 " + String(localized: "Vaccinations:"))
                for vaccine in current {
                    let dueText = Fmt.date(vaccine.nextDue)
                    lines.append("• " + String(localized: "\(vaccine.name), next due \(dueText)"))
                }
            }
        }

        if options.weight, let latest = cat.latestWeight {
            let weightText = unit.format(kilograms: latest.kg)
            let weighedOn = Fmt.date(latest.date)
            lines.append("\n⚖️ " + String(localized: "Weight: \(weightText) (\(weighedOn))"))
        }

        if options.notes && !cat.notes.isEmpty {
            lines.append("\n📝 \(cat.notes)")
        }

        if options.contacts {
            let contacts = cat.isGuest ? cat.guestContacts : ownContacts.map(contactDTO)
            if !contacts.isEmpty {
                lines.append("\n📞 " + String(localized: "Contacts:"))
                for contact in contacts {
                    let role = contact.role.isEmpty ? "" : "\(contact.role): "
                    let phone = contact.phone.isEmpty ? "" : ", \(contact.phone)"
                    lines.append("\(role)\(contact.name)\(phone)")
                }
            }
        }

        let senderName = sender.trimmed
        lines.append("\n— " + (senderName.isEmpty ? String(localized: "Shared from Pet-o-Base")
                                                  : String(localized: "Shared from Pet-o-Base by \(senderName)")))
        return lines.joined(separator: "\n")
    }
}

// MARK: - Receiving

/// A cat share waiting for the user to confirm. Shown by RootView.
struct ReceivedShare: Identifiable {
    let id = UUID()
    let file: BackupFile
    var cat: CatDTO { file.cats[0] }
}

@Observable
final class GuestInbox {
    static let shared = GuestInbox()
    var pending: ReceivedShare?
    var error: String?
    private init() {}

    /// Reads a file handed to the app (Messages, Telegram, Files, Finder…).
    @MainActor
    func receive(_ url: URL) {
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Result { try BackupReader.read(url) }
            }.value
            switch outcome {
            case .success(let read) where read.1 == .catShare && !read.0.cats.isEmpty:
                pending = ReceivedShare(file: read.0)
            case .success:
                error = String(localized: "This is a full backup, not a shared pet. To restore it, use Settings → Backup → Import.")
            case .failure(let failure):
                error = failure.localizedDescription
            }
        }
    }
}

@MainActor
enum GuestImporter {
    /// A guest cat already received from the same original, if any.
    static func existingGuest(for share: ReceivedShare, in context: ModelContext) -> Cat? {
        guard let shareID = share.cat.shareID else { return nil }
        let guests = (try? context.fetch(FetchDescriptor<Cat>(predicate: #Predicate { $0.isGuest == true }))) ?? []
        return guests.first { $0.shareID == shareID }
    }

    /// Adds the shared cat as a guest. With `replacing`, that older copy is deleted first.
    static func add(_ share: ReceivedShare, replacing old: Cat?, in context: ModelContext) async throws -> Cat {
        var dto = share.cat
        dto.isGuest = true
        dto.guestFrom = share.file.sharedBy ?? ""
        dto.guestReceivedAt = Date()
        dto.guestContacts = share.file.contacts
        dto.archived = false
        if let old {
            context.delete(old)
            try context.save()
        }
        let (cat, _, _) = try await BackupImporter.insertCat(dto, into: context)
        try context.save()
        return cat
    }
}
