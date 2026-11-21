import Foundation
import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - File format
//
// A backup is one JSON file. Photos and documents are embedded (base64), so a
// single file holds everything and can be kept anywhere: Files, iCloud Drive,
// a NAS share, email.

struct BackupFile: Codable, Sendable {
    static let formatName = "cat-o-base-apple"

    var format = BackupFile.formatName
    var version = 1
    var exported = Date()
    var cats: [CatDTO] = []
    var contacts: [ContactDTO] = []
}

struct CatDTO: Codable, Sendable {
    var name = ""
    var sex = ""
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
    var archived = false
    var createdAt = Date()
    var profilePhotoID: UUID?
    var photos: [PhotoDTO] = []
    var vaccinations: [VaccinationDTO] = []
    var treatments: [TreatmentDTO] = []
    var weights: [WeightDTO] = []
    var visits: [VisitDTO] = []
    var documents: [DocumentDTO] = []
    var journal: [JournalDTO] = []
}

struct PhotoDTO: Codable, Sendable {
    var uuid = UUID()
    /// Full image. From the web app this is the original file and gets processed on import.
    var image: Data
    /// Avatar. Nil means "work it out on import" (with cat detection).
    var thumbnail: Data?
    var caption = ""
    var takenOn: Date?
    var addedAt = Date()
    var cropCenterX: Double?
    var cropCenterY: Double?
    var cropSide: Double?
}

struct VaccinationDTO: Codable, Sendable {
    var name = ""
    var dateGiven: Date?
    var nextDue: Date?
    var vet = ""
    var notes = ""
}

struct TreatmentDTO: Codable, Sendable {
    var kind = TreatmentKind.medication.rawValue
    var name = ""
    var dose = ""
    var schedule = ""
    var intervalDays: Int?
    var lastGiven: Date?
    var nextDue: Date?
    var endDate: Date?
    var active = true
    var notes = ""
}

struct WeightDTO: Codable, Sendable {
    var date = Date()
    var kg = 0.0
}

struct VisitDTO: Codable, Sendable {
    var date = Date()
    var clinic = ""
    var reason = ""
    var outcome = ""
    var cost = ""
    var notes = ""
}

struct DocumentDTO: Codable, Sendable {
    var title = ""
    var filename = ""
    var typeIdentifier = ""
    var data: Data
    var addedAt = Date()
}

struct JournalDTO: Codable, Sendable {
    var date = Date()
    var kind = "note"
    var text = ""
}

struct ContactDTO: Codable, Sendable {
    var role = ""
    var name = ""
    var phone = ""
    var address = ""
    var notes = ""
}

extension BackupFile {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Export

@MainActor
enum BackupExporter {
    static func makeBackup(cats: [Cat], contacts: [Contact]) -> BackupFile {
        var file = BackupFile()
        file.cats = cats.map(dto)
        file.contacts = contacts.map {
            ContactDTO(role: $0.role, name: $0.name, phone: $0.phone, address: $0.address, notes: $0.notes)
        }
        return file
    }

    static var defaultFilename: String {
        let day = Date.now.formatted(.iso8601.year().month().day())
        return "Cat-o-Base Backup \(day)"
    }

    private static func dto(_ cat: Cat) -> CatDTO {
        var dto = CatDTO()
        dto.name = cat.name
        dto.sex = cat.sexRaw
        dto.neutered = cat.neutered
        dto.breed = cat.breed
        dto.markings = cat.markings
        dto.microchip = cat.microchip
        dto.birthday = cat.birthday
        dto.birthdayApprox = cat.birthdayApprox
        dto.adoptionDate = cat.adoptionDate
        dto.specialNeeds = cat.specialNeeds
        dto.allergies = cat.allergies
        dto.foodBrand = cat.foodBrand
        dto.foodPortion = cat.foodPortion
        dto.foodSchedule = cat.foodSchedule
        dto.foodNotes = cat.foodNotes
        dto.notes = cat.notes
        dto.archived = cat.archived
        dto.createdAt = cat.createdAt
        dto.profilePhotoID = cat.profilePhotoID
        dto.photos = (cat.photos ?? []).compactMap { photo in
            guard let image = photo.imageData else { return nil }
            return PhotoDTO(uuid: photo.uuid, image: image, thumbnail: photo.thumbnailData,
                            caption: photo.caption, takenOn: photo.takenOn, addedAt: photo.addedAt,
                            cropCenterX: photo.cropCenterX, cropCenterY: photo.cropCenterY,
                            cropSide: photo.cropSide)
        }
        dto.vaccinations = (cat.vaccinations ?? []).map {
            VaccinationDTO(name: $0.name, dateGiven: $0.dateGiven, nextDue: $0.nextDue, vet: $0.vet, notes: $0.notes)
        }
        dto.treatments = (cat.treatments ?? []).map {
            TreatmentDTO(kind: $0.kindRaw, name: $0.name, dose: $0.dose, schedule: $0.schedule,
                         intervalDays: $0.intervalDays, lastGiven: $0.lastGiven, nextDue: $0.nextDue,
                         endDate: $0.endDate, active: $0.active, notes: $0.notes)
        }
        dto.weights = (cat.weights ?? []).map { WeightDTO(date: $0.date, kg: $0.kg) }
        dto.visits = (cat.visits ?? []).map {
            VisitDTO(date: $0.date, clinic: $0.clinic, reason: $0.reason, outcome: $0.outcome,
                     cost: $0.cost, notes: $0.notes)
        }
        dto.documents = (cat.documents ?? []).compactMap { document in
            guard let data = document.data else { return nil }
            return DocumentDTO(title: document.title, filename: document.filename,
                               typeIdentifier: document.typeIdentifier, data: data, addedAt: document.addedAt)
        }
        dto.journal = (cat.journal ?? []).map { JournalDTO(date: $0.date, kind: $0.kind, text: $0.text) }
        return dto
    }
}

/// Wraps backup bytes for SwiftUI's file exporter.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Import

enum BackupSource: String {
    case app = "Cat-o-Base app backup"
    case webZip = "Cat-o-Base web full backup"
    case webJSON = "Cat-o-Base web data export (no photos)"
}

enum BackupError: LocalizedError {
    case unreadable
    case unknownFormat
    case newerVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unreadable: return "The file couldn't be read."
        case .unknownFormat: return "This isn't a Cat-o-Base backup."
        case .newerVersion(let version):
            return "This backup was made by a newer version of Cat-o-Base (format \(version)). Update the app first."
        }
    }
}

/// Reads any supported backup file into the common format. Call off the main thread.
enum BackupReader {
    static func read(_ url: URL) throws -> (BackupFile, BackupSource) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { throw BackupError.unreadable }

        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) { // "PK", a zip file
            return (try WebImport.backup(fromZip: data), .webZip)
        }

        struct Probe: Decodable {
            let format: String?
            let version: Int?
            let app: String?
        }
        guard let probe = try? JSONDecoder().decode(Probe.self, from: data) else { throw BackupError.unknownFormat }

        if probe.format == BackupFile.formatName {
            if let version = probe.version, version > 1 { throw BackupError.newerVersion(version) }
            return (try BackupFile.decoder().decode(BackupFile.self, from: data), .app)
        }
        if probe.app == "cat-o-base" || probe.app == "catdb" {
            return (try WebImport.backup(fromJSON: data), .webJSON)
        }
        throw BackupError.unknownFormat
    }
}

struct ImportSummary {
    var cats = 0
    var photos = 0
    var documents = 0
    var contacts = 0

    var text: String {
        func plural(_ count: Int, _ word: String) -> String { "\(count) \(word)\(count == 1 ? "" : "s")" }
        return [plural(cats, "cat"), plural(photos, "photo"), plural(documents, "document"),
                plural(contacts, "contact")].joined(separator: ", ")
    }
}

@MainActor
enum BackupImporter {
    /// Shows in Xcode's console (and Console.app) under "import".
    static let log = Logger(subsystem: "com.arimanoff.catobase", category: "import")

    /// Adds everything in `file` to the store. With `replace`, deletes all cats and contacts first.
    static func run(_ file: BackupFile, into context: ModelContext, replace: Bool,
                    progress: @escaping (String) -> Void) async throws -> ImportSummary {
        log.info("Import started: \(file.cats.count) cats, \(file.contacts.count) contacts, replace=\(replace)")
        let started = Date()
        if replace {
            progress("Removing current data…")
            await Task.yield()
            // Deleted one by one so cascade rules run; then sweep up any orphans.
            try deleteAll(Cat.self, in: context)
            try deleteAll(Contact.self, in: context)
            try deleteAll(CatPhoto.self, in: context)
            try deleteAll(Vaccination.self, in: context)
            try deleteAll(Treatment.self, in: context)
            try deleteAll(WeightEntry.self, in: context)
            try deleteAll(VetVisit.self, in: context)
            try deleteAll(CatDocument.self, in: context)
            try deleteAll(JournalEntry.self, in: context)
            try context.save()
            log.info("Old data removed")
        }

        var summary = ImportSummary()
        for (catIndex, dto) in file.cats.enumerated() {
            try Task.checkCancellation()
            let catLabel = "\(dto.name.isEmpty ? "Cat" : dto.name) (\(catIndex + 1) of \(file.cats.count))"
            progress("Importing \(catLabel)…")
            log.info("Cat \(catLabel, privacy: .public): \(dto.photos.count) photos, \(dto.documents.count) documents")
            await Task.yield()
            let cat = Cat(name: dto.name)
            cat.sexRaw = CatSex(rawValue: dto.sex)?.rawValue ?? CatSex.unknown.rawValue
            cat.neutered = dto.neutered
            cat.breed = dto.breed
            cat.markings = dto.markings
            cat.microchip = dto.microchip
            cat.birthday = dto.birthday
            cat.birthdayApprox = dto.birthdayApprox
            cat.adoptionDate = dto.adoptionDate
            cat.specialNeeds = dto.specialNeeds
            cat.allergies = dto.allergies
            cat.foodBrand = dto.foodBrand
            cat.foodPortion = dto.foodPortion
            cat.foodSchedule = dto.foodSchedule
            cat.foodNotes = dto.foodNotes
            cat.notes = dto.notes
            cat.archived = dto.archived
            cat.createdAt = dto.createdAt
            context.insert(cat)

            for (photoIndex, photoDTO) in dto.photos.enumerated() {
                try Task.checkCancellation()
                progress("\(catLabel)\nPhoto \(photoIndex + 1) of \(dto.photos.count)")
                await Task.yield()
                let photoStarted = Date()
                guard let photo = await makePhoto(photoDTO) else {
                    log.error("Photo \(photoIndex + 1) couldn't be read (\(photoDTO.image.count) bytes), skipped")
                    continue
                }
                log.info("Photo \(photoIndex + 1) done in \(Date().timeIntervalSince(photoStarted), format: .fixed(precision: 2)) s")
                context.insert(photo)
                photo.cat = cat
                summary.photos += 1
            }
            cat.profilePhotoID = dto.profilePhotoID

            for item in dto.vaccinations {
                let vaccination = Vaccination(name: item.name)
                vaccination.dateGiven = item.dateGiven
                vaccination.nextDue = item.nextDue
                vaccination.vet = item.vet
                vaccination.notes = item.notes
                context.insert(vaccination)
                vaccination.cat = cat
            }
            for item in dto.treatments {
                let treatment = Treatment(name: item.name)
                treatment.kindRaw = TreatmentKind(rawValue: item.kind)?.rawValue ?? TreatmentKind.other.rawValue
                treatment.dose = item.dose
                treatment.schedule = item.schedule
                treatment.intervalDays = item.intervalDays
                treatment.lastGiven = item.lastGiven
                treatment.nextDue = item.nextDue
                treatment.endDate = item.endDate
                treatment.active = item.active
                treatment.notes = item.notes
                context.insert(treatment)
                treatment.cat = cat
            }
            for item in dto.weights {
                let weight = WeightEntry(date: item.date, kg: item.kg)
                context.insert(weight)
                weight.cat = cat
            }
            for item in dto.visits {
                let visit = VetVisit(date: item.date)
                visit.clinic = item.clinic
                visit.reason = item.reason
                visit.outcome = item.outcome
                visit.cost = item.cost
                visit.notes = item.notes
                context.insert(visit)
                visit.cat = cat
            }
            for item in dto.documents {
                let document = CatDocument(title: item.title, filename: item.filename,
                                           typeIdentifier: item.typeIdentifier, data: item.data)
                document.addedAt = item.addedAt
                context.insert(document)
                document.cat = cat
                summary.documents += 1
            }
            for item in dto.journal {
                let entry = JournalEntry(date: item.date, kind: item.kind, text: item.text)
                context.insert(entry)
                entry.cat = cat
            }
            summary.cats += 1
            progress("\(catLabel)\nSaving…")
            await Task.yield()
            try context.save()
            log.info("Cat \(catLabel, privacy: .public) saved")
        }

        for item in file.contacts {
            let contact = Contact(name: item.name)
            contact.role = item.role
            contact.phone = item.phone
            contact.address = item.address
            contact.notes = item.notes
            context.insert(contact)
            summary.contacts += 1
        }
        try context.save()
        log.info("Import finished in \(Date().timeIntervalSince(started), format: .fixed(precision: 1)) s: \(summary.text, privacy: .public)")
        return summary
    }

    private static func deleteAll<Model: PersistentModel>(_ type: Model.Type, in context: ModelContext) throws {
        for object in try context.fetch(FetchDescriptor<Model>()) {
            context.delete(object)
        }
    }

    /// App backups carry the finished avatar; web photos are downsized and cat-detected here.
    private static func makePhoto(_ dto: PhotoDTO) async -> CatPhoto? {
        if let thumbnail = dto.thumbnail {
            let photo = CatPhoto(imageData: dto.image, thumbnailData: thumbnail)
            photo.uuid = dto.uuid
            photo.caption = dto.caption
            photo.takenOn = dto.takenOn
            photo.addedAt = dto.addedAt
            photo.cropCenterX = dto.cropCenterX ?? 0.5
            photo.cropCenterY = dto.cropCenterY ?? 0.5
            photo.cropSide = dto.cropSide ?? 1
            return photo
        }
        let original = dto.image
        guard let prepared = await Task.detached(priority: .userInitiated, operation: {
            ImageTools.prepare(original)
        }).value else { return nil }
        let photo = CatPhoto.make(from: prepared)
        photo.uuid = dto.uuid
        photo.caption = dto.caption
        photo.takenOn = dto.takenOn ?? prepared.takenOn
        photo.addedAt = dto.addedAt
        return photo
    }
}
