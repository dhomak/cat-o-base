import Foundation
import SwiftData
import Testing
@testable import CatOBase

@MainActor
@Suite("Backup and restore")
struct BackupTests {
    /// A pet with one of every kind of record. Dates have whole seconds so they
    /// compare equal after the ISO 8601 round trip.
    private func makeFullPet(in store: TestStore) throws -> (Cat, Contact) {
        let context = store.context
        let cat = Cat(name: "Rex")
        cat.species = .dog
        cat.sex = .male
        cat.neutered = true
        cat.breed = "Beagle"
        cat.markings = "Tricolour"
        cat.microchip = "972000111222333"
        cat.birthday = localDay(2019, 4, 2)
        cat.birthdayApprox = true
        cat.adoptionDate = localDay(2019, 7, 1)
        cat.specialNeeds = "Bad hip"
        cat.allergies = "Beef"
        cat.foodBrand = "Hill's"
        cat.foodPortion = "200 g"
        cat.foodSchedule = "Twice a day"
        cat.foodNotes = "No table scraps"
        cat.notes = "Loves the beach"
        cat.createdAt = wholeSeconds(Date())
        context.insert(cat)

        let jpeg = try Fixture.data("tiny.jpg")
        let photo = CatPhoto(imageData: jpeg, thumbnailData: jpeg)
        photo.caption = "On the beach"
        photo.takenOn = localDay(2025, 8, 3)
        photo.addedAt = wholeSeconds(Date())
        photo.cropCenterX = 0.4
        photo.cropCenterY = 0.6
        photo.cropSide = 0.8
        context.insert(photo)
        photo.cat = cat
        cat.profilePhotoID = photo.uuid

        let vaccination = Vaccination(name: "DHPP")
        vaccination.dateGiven = localDay(2026, 3, 1)
        vaccination.nextDue = localDay(2027, 3, 1)
        vaccination.vet = "Dr. Levi"
        vaccination.notes = "Batch 42"
        context.insert(vaccination)
        vaccination.cat = cat

        let treatment = Treatment(name: "NexGard")
        treatment.kind = .fleaTick
        treatment.dose = "1 chew"
        treatment.schedule = "Monthly"
        treatment.intervalDays = 30
        treatment.lastGiven = localDay(2026, 11, 1)
        treatment.nextDue = localDay(2026, 12, 1)
        treatment.endDate = localDay(2027, 6, 1)
        treatment.active = false
        treatment.notes = "With food"
        context.insert(treatment)
        treatment.cat = cat

        for (date, kg) in [(localDay(2026, 1, 1), 12.4), (localDay(2026, 6, 1), 12.9)] {
            let weight = WeightEntry(date: date, kg: kg)
            context.insert(weight)
            weight.cat = cat
        }

        let visit = VetVisit(date: localDay(2026, 2, 14))
        visit.clinic = "Steisneider"
        visit.reason = "Limping"
        visit.outcome = "Rest"
        visit.cost = "450"
        visit.notes = "X-ray fine"
        context.insert(visit)
        visit.cat = cat

        let document = CatDocument(title: "X-ray", filename: "xray.pdf", typeIdentifier: "com.adobe.pdf",
                                   data: Data("%PDF-1.4 test".utf8))
        document.addedAt = wholeSeconds(Date())
        context.insert(document)
        document.cat = cat

        let entry = JournalEntry(date: localDay(2026, 11, 20), kind: "grooming", text: "Bath")
        context.insert(entry)
        entry.cat = cat

        let contact = Contact(name: "Steisneider")
        contact.role = "Vet"
        contact.phone = "037307333"
        contact.address = "Tel Aviv"
        contact.notes = "24/7"
        context.insert(contact)
        try context.save()
        return (cat, contact)
    }

    private func encode(_ file: BackupFile) throws -> URL {
        try temporaryFile(try BackupFile.encoder().encode(file), name: "backup.json")
    }

    @Test func everythingSurvivesARoundTrip() async throws {
        let source = try TestStore()
        let (original, contact) = try makeFullPet(in: source)
        let url = try encode(BackupExporter.makeBackup(cats: [original], contacts: [contact]))

        let (file, kind) = try BackupReader.read(url)
        #expect(kind == .app)

        let target = try TestStore()
        let summary = try await BackupImporter.run(file, into: target.context, replace: false) { _ in }
        #expect(summary.cats == 1)
        #expect(summary.photos == 1)
        #expect(summary.documents == 1)
        #expect(summary.contacts == 1)

        let cat = try #require(try target.cat(named: "Rex"))
        #expect(cat.species == .dog)
        #expect(cat.sex == .male)
        #expect(cat.neutered)
        #expect(cat.breed == "Beagle")
        #expect(cat.markings == "Tricolour")
        #expect(cat.microchip == "972000111222333")
        #expect(cat.birthday == original.birthday)
        #expect(cat.birthdayApprox)
        #expect(cat.adoptionDate == original.adoptionDate)
        #expect(cat.specialNeeds == "Bad hip")
        #expect(cat.allergies == "Beef")
        #expect([cat.foodBrand, cat.foodPortion, cat.foodSchedule, cat.foodNotes]
                == ["Hill's", "200 g", "Twice a day", "No table scraps"])
        #expect(cat.notes == "Loves the beach")
        #expect(cat.createdAt == original.createdAt)
        #expect(!cat.isGuest)

        let photo = try #require(cat.photos?.first)
        #expect(photo.uuid == original.photos?.first?.uuid)
        #expect(cat.profilePhoto?.uuid == photo.uuid)
        #expect(photo.imageData == original.photos?.first?.imageData)
        #expect(photo.caption == "On the beach")
        #expect(photo.takenOn == localDay(2025, 8, 3))
        #expect([photo.cropCenterX, photo.cropCenterY, photo.cropSide] == [0.4, 0.6, 0.8])

        let vaccination = try #require(cat.vaccinations?.first)
        #expect(vaccination.name == "DHPP")
        #expect(vaccination.dateGiven == localDay(2026, 3, 1))
        #expect(vaccination.nextDue == localDay(2027, 3, 1))
        #expect(vaccination.vet == "Dr. Levi")
        #expect(vaccination.notes == "Batch 42")

        let treatment = try #require(cat.treatments?.first)
        #expect(treatment.kind == .fleaTick)
        #expect(treatment.dose == "1 chew")
        #expect(treatment.schedule == "Monthly")
        #expect(treatment.intervalDays == 30)
        #expect(treatment.lastGiven == localDay(2026, 11, 1))
        #expect(treatment.nextDue == localDay(2026, 12, 1))
        #expect(treatment.endDate == localDay(2027, 6, 1))
        #expect(!treatment.active)
        #expect(treatment.notes == "With food")

        #expect(cat.weightsNewestFirst.map(\.kg) == [12.9, 12.4])

        let visit = try #require(cat.visits?.first)
        #expect([visit.clinic, visit.reason, visit.outcome, visit.cost, visit.notes]
                == ["Steisneider", "Limping", "Rest", "450", "X-ray fine"])
        #expect(visit.date == localDay(2026, 2, 14))

        let document = try #require(cat.documents?.first)
        #expect(document.title == "X-ray")
        #expect(document.filename == "xray.pdf")
        #expect(document.typeIdentifier == "com.adobe.pdf")
        #expect(document.data == Data("%PDF-1.4 test".utf8))

        let entry = try #require(cat.journal?.first)
        #expect(entry.kind == "grooming")
        #expect(entry.text == "Bath")

        let restoredContact = try #require(try target.all(Contact.self).first)
        #expect([restoredContact.role, restoredContact.name, restoredContact.phone, restoredContact.address,
                 restoredContact.notes] == ["Vet", "Steisneider", "037307333", "Tel Aviv", "24/7"])
    }

    @Test func guestPetsKeepTheirOwnerAndContacts() async throws {
        let source = try TestStore()
        let guest = Cat(name: "Splinter")
        guest.species = .rat
        guest.isGuest = true
        guest.guestFrom = "Anna"
        guest.guestReceivedAt = localDay(2026, 11, 15)
        guest.shareID = UUID()
        guest.guestContactsData = try JSONEncoder().encode([ContactDTO(role: "Owner", name: "Anna", phone: "+972541234567")])
        source.context.insert(guest)

        let url = try encode(BackupExporter.makeBackup(cats: [guest], contacts: []))
        let target = try TestStore()
        _ = try await BackupImporter.run(try BackupReader.read(url).0, into: target.context, replace: false) { _ in }

        let cat = try #require(try target.cat(named: "Splinter"))
        #expect(cat.isGuest)
        #expect(cat.guestFrom == "Anna")
        #expect(cat.guestReceivedAt == localDay(2026, 11, 15))
        #expect(cat.shareID == guest.shareID)
        #expect(cat.guestContacts.map(\.phone) == ["+972541234567"])
        #expect(cat.species == .rat)
    }

    @Test func replaceDeletesCurrentData() async throws {
        let source = try TestStore()
        let (original, contact) = try makeFullPet(in: source)
        let file = try BackupReader.read(try encode(BackupExporter.makeBackup(cats: [original], contacts: [contact]))).0

        let target = try TestStore()
        let old = Cat(name: "Old")
        target.context.insert(old)
        let oldVaccine = Vaccination(name: "Old vaccine")
        target.context.insert(oldVaccine)
        oldVaccine.cat = old
        target.context.insert(Contact(name: "Old contact"))
        try target.context.save()

        _ = try await BackupImporter.run(file, into: target.context, replace: true) { _ in }
        #expect(try target.all(Cat.self).map(\.name) == ["Rex"])
        #expect(try target.all(Vaccination.self).map(\.name) == ["DHPP"], "the old pet's records go too")
        #expect(try target.all(Contact.self).map(\.name) == ["Steisneider"])
    }

    @Test func addingKeepsCurrentData() async throws {
        let source = try TestStore()
        let (original, contact) = try makeFullPet(in: source)
        let file = try BackupReader.read(try encode(BackupExporter.makeBackup(cats: [original], contacts: [contact]))).0

        let target = try TestStore()
        target.context.insert(Cat(name: "Old"))
        try target.context.save()

        _ = try await BackupImporter.run(file, into: target.context, replace: false) { _ in }
        #expect(Set(try target.all(Cat.self).map(\.name)) == ["Old", "Rex"])
    }

    @Test func progressIsReported() async throws {
        let source = try TestStore()
        let (original, _) = try makeFullPet(in: source)
        let file = BackupExporter.makeBackup(cats: [original], contacts: [])
        let target = try TestStore()
        var messages: [String] = []
        _ = try await BackupImporter.run(file, into: target.context, replace: false) { messages.append($0) }
        #expect(messages.contains { $0.contains("Rex (1 of 1)") })
    }

    @Test func newerFormatIsRefused() throws {
        let json = #"{"format":"cat-o-base-apple","version":2,"exported":"2026-01-01T00:00:00Z","cats":[],"contacts":[]}"#
        let url = try temporaryFile(Data(json.utf8), name: "future.json")
        let error = #expect(throws: BackupError.self) { try BackupReader.read(url) }
        guard case .newerVersion(let version)? = error else {
            Issue.record("expected newerVersion, got \(String(describing: error))")
            return
        }
        #expect(version == 2)
    }

    @Test(arguments: [Data("hello".utf8), Data(#"{"foo": 1}"#.utf8), Data([0x50, 0x4B, 0x05, 0x06])])
    func unknownFilesAreRefused(data: Data) throws {
        let url = try temporaryFile(data, name: "mystery.json")
        #expect(throws: (any Error).self) { try BackupReader.read(url) }
    }

    @Test func missingFileIsUnreadable() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString).json")
        let error = #expect(throws: BackupError.self) { try BackupReader.read(url) }
        guard case .unreadable? = error else {
            Issue.record("expected unreadable, got \(String(describing: error))")
            return
        }
    }
}
