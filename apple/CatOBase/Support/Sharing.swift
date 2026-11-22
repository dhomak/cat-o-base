import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    /// A single shared cat (`.catobase`). Declared in project.yml (Info.plist).
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
            case .none: return "None"
            case .profile: return "Profile photo"
            case .all: return "All photos"
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
    /// Writes `<Name>.catobase` to a temporary folder. Assigns the cat a share ID the
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
        let url = folder.appendingPathComponent("\(safeName).catobase")
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
        var lines: [String] = ["🐾 \(cat.displayName)"]

        var facts: [String] = []
        if let age = Fmt.age(from: cat.birthday) { facts.append(cat.birthdayApprox ? "about \(age)" : age) }
        if cat.sex != .unknown { facts.append(cat.sex.label.lowercased() + (cat.neutered ? ", neutered" : "")) }
        if options.details {
            if !cat.breed.isEmpty { facts.append(cat.breed) }
            if !cat.markings.isEmpty { facts.append(cat.markings) }
        }
        if !facts.isEmpty { lines.append(facts.joined(separator: " · ")) }
        if options.details && !cat.microchip.isEmpty { lines.append("Microchip: \(cat.microchip)") }

        if options.specialNeeds {
            if !cat.specialNeeds.isEmpty { lines.append("\n⚠️ Special needs: \(cat.specialNeeds)") }
            if !cat.allergies.isEmpty { lines.append("Allergies: \(cat.allergies)") }
        }

        if options.food {
            let food = [cat.foodBrand, cat.foodPortion, cat.foodSchedule].filter { !$0.isEmpty }
            if !food.isEmpty || !cat.foodNotes.isEmpty {
                lines.append("\n🍽 Food: " + (food.isEmpty ? "" : food.joined(separator: ", ")))
                if !cat.foodNotes.isEmpty { lines.append(cat.foodNotes) }
            }
        }

        if options.health {
            let meds = (cat.treatments ?? []).filter(\.active)
            if !meds.isEmpty {
                lines.append("\n💊 Medication & treatments:")
                for treatment in meds {
                    var line = "• \(treatment.name)"
                    if !treatment.summary.isEmpty { line += " (\(treatment.summary))" }
                    if let due = treatment.nextDue { line += ", next \(Fmt.date(due))" }
                    lines.append(line)
                }
            }
            let vaccines = cat.vaccinations ?? []
            let current = vaccines.filter { $0.isCurrent(among: vaccines) && $0.nextDue != nil }
            if !current.isEmpty {
                lines.append("\n💉 Vaccinations:")
                for vaccine in current {
                    lines.append("• \(vaccine.name), next due \(Fmt.date(vaccine.nextDue))")
                }
            }
        }

        if options.weight, let latest = cat.latestWeight {
            lines.append("\n⚖️ Weight: \(unit.format(kilograms: latest.kg)) (\(Fmt.date(latest.date)))")
        }

        if options.notes && !cat.notes.isEmpty {
            lines.append("\n📝 \(cat.notes)")
        }

        if options.contacts {
            let contacts = cat.isGuest ? cat.guestContacts : ownContacts.map(contactDTO)
            if !contacts.isEmpty {
                lines.append("\n📞 Contacts:")
                for contact in contacts {
                    let role = contact.role.isEmpty ? "" : "\(contact.role): "
                    let phone = contact.phone.isEmpty ? "" : ", \(contact.phone)"
                    lines.append("\(role)\(contact.name)\(phone)")
                }
            }
        }

        let by = sender.trimmed.isEmpty ? "" : " by \(sender.trimmed)"
        lines.append("\n— Shared from Cat-o-Base\(by)")
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
                error = "This is a full backup, not a shared pet. To restore it, use Settings → Backup → Import."
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
