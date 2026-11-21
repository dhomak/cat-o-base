import Foundation
import SwiftData

// All models follow CloudKit's rules so iCloud sync can be switched on later
// without a migration: every stored property has a default or is optional,
// every relationship is optional and has an inverse, no unique constraints.
// Enums are stored as raw strings for the same reason.

// MARK: - Cat

@Model
final class Cat {
    var name: String = ""
    var sexRaw: String = CatSex.unknown.rawValue
    var neutered: Bool = false
    var breed: String = ""
    var markings: String = ""
    var microchip: String = ""
    var birthday: Date?
    var birthdayApprox: Bool = false
    var adoptionDate: Date?
    var specialNeeds: String = ""
    var allergies: String = ""
    var foodBrand: String = ""
    var foodPortion: String = ""
    var foodSchedule: String = ""
    var foodNotes: String = ""
    var notes: String = ""
    var archived: Bool = false
    var createdAt: Date = Date()
    /// `CatPhoto.uuid` of the profile photo. Stored as an ID rather than a second
    /// relationship to CatPhoto, because CloudKit requires every relationship to
    /// have an inverse.
    var profilePhotoID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \CatPhoto.cat)
    var photos: [CatPhoto]? = []
    @Relationship(deleteRule: .cascade, inverse: \Vaccination.cat)
    var vaccinations: [Vaccination]? = []
    @Relationship(deleteRule: .cascade, inverse: \Treatment.cat)
    var treatments: [Treatment]? = []
    @Relationship(deleteRule: .cascade, inverse: \WeightEntry.cat)
    var weights: [WeightEntry]? = []
    @Relationship(deleteRule: .cascade, inverse: \VetVisit.cat)
    var visits: [VetVisit]? = []
    @Relationship(deleteRule: .cascade, inverse: \CatDocument.cat)
    var documents: [CatDocument]? = []
    @Relationship(deleteRule: .cascade, inverse: \JournalEntry.cat)
    var journal: [JournalEntry]? = []

    init(name: String = "") {
        self.name = name
    }

    var sex: CatSex {
        get { CatSex(rawValue: sexRaw) ?? .unknown }
        set { sexRaw = newValue.rawValue }
    }

    /// The chosen profile photo, or the most recently added photo.
    var profilePhoto: CatPhoto? {
        let all = photos ?? []
        if let id = profilePhotoID, let match = all.first(where: { $0.uuid == id }) {
            return match
        }
        return all.max(by: { $0.addedAt < $1.addedAt })
    }

    var latestWeight: WeightEntry? {
        (weights ?? []).max(by: { $0.date < $1.date })
    }

    var displayName: String {
        name.isEmpty ? "Unnamed cat" : name
    }
}

enum CatSex: String, CaseIterable, Identifiable {
    case unknown, female, male
    var id: String { rawValue }
    var label: String {
        switch self {
        case .unknown: return "Unknown"
        case .female: return "Female"
        case .male: return "Male"
        }
    }
}

// MARK: - Photos

@Model
final class CatPhoto {
    var uuid: UUID = UUID()
    /// Full image, downscaled to at most 2400 px on the long side, JPEG.
    @Attribute(.externalStorage) var imageData: Data?
    /// Square avatar, 512 px, cut from the crop settings below.
    @Attribute(.externalStorage) var thumbnailData: Data?
    var caption: String = ""
    var takenOn: Date?
    var addedAt: Date = Date()
    /// Avatar crop: centre (0…1 of width/height) and side (0…1 of the shorter edge).
    var cropCenterX: Double = 0.5
    var cropCenterY: Double = 0.5
    var cropSide: Double = 1.0
    var cat: Cat?

    init(imageData: Data?, thumbnailData: Data?) {
        self.imageData = imageData
        self.thumbnailData = thumbnailData
    }
}

// MARK: - Health

@Model
final class Vaccination {
    var name: String = ""
    var dateGiven: Date?
    var nextDue: Date?
    var vet: String = ""
    var notes: String = ""
    var cat: Cat?

    init(name: String = "") { self.name = name }
}

enum TreatmentKind: String, CaseIterable, Identifiable {
    case medication, fleaTick, deworming, supplement, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .medication: return "Medication"
        case .fleaTick: return "Flea / tick"
        case .deworming: return "Deworming"
        case .supplement: return "Supplement"
        case .other: return "Other"
        }
    }
}

@Model
final class Treatment {
    var kindRaw: String = TreatmentKind.medication.rawValue
    var name: String = ""
    var dose: String = ""
    var schedule: String = ""
    /// Repeat interval in days; nil for one-off or free-text schedules.
    var intervalDays: Int?
    var lastGiven: Date?
    var nextDue: Date?
    var endDate: Date?
    var active: Bool = true
    var notes: String = ""
    var cat: Cat?

    init(name: String = "") { self.name = name }

    var kind: TreatmentKind {
        get { TreatmentKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class WeightEntry {
    var date: Date = Date()
    var kg: Double = 0
    var cat: Cat?

    init(date: Date = Date(), kg: Double = 0) {
        self.date = date
        self.kg = kg
    }
}

@Model
final class VetVisit {
    var date: Date = Date()
    var clinic: String = ""
    var reason: String = ""
    var outcome: String = ""
    var cost: String = ""
    var notes: String = ""
    var cat: Cat?

    init(date: Date = Date()) { self.date = date }
}

// MARK: - Files and notes

@Model
final class CatDocument {
    var title: String = ""
    var filename: String = ""
    /// Uniform Type Identifier, e.g. "com.adobe.pdf".
    var typeIdentifier: String = ""
    @Attribute(.externalStorage) var data: Data?
    var byteCount: Int = 0
    var addedAt: Date = Date()
    var cat: Cat?

    init(title: String = "", filename: String = "", typeIdentifier: String = "", data: Data? = nil) {
        self.title = title
        self.filename = filename
        self.typeIdentifier = typeIdentifier
        self.data = data
        self.byteCount = data?.count ?? 0
    }
}

@Model
final class JournalEntry {
    var date: Date = Date()
    var kind: String = "note"
    var text: String = ""
    var cat: Cat?

    init(date: Date = Date(), kind: String = "note", text: String = "") {
        self.date = date
        self.kind = kind
        self.text = text
    }
}

// MARK: - Contacts

@Model
final class Contact {
    var role: String = ""
    var name: String = ""
    var phone: String = ""
    var address: String = ""
    var notes: String = ""
    var createdAt: Date = Date()

    init(name: String = "") { self.name = name }
}

// MARK: - Schema

enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        Cat.self, CatPhoto.self, Vaccination.self, Treatment.self, WeightEntry.self,
        VetVisit.self, CatDocument.self, JournalEntry.self, Contact.self,
    ]
}
