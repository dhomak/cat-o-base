import Foundation
import SwiftData
import Testing
@testable import CatOBase

@Suite("Choosing what to share")
struct ShareOptionsTests {
    private func fullPet() -> (CatDTO, UUID) {
        var dto = CatDTO()
        dto.name = "Murka"
        dto.breed = "Tabby"
        dto.markings = "White socks"
        dto.microchip = "123"
        dto.adoptionDate = localDay(2016, 5, 1)
        dto.specialNeeds = "Kidney diet"
        dto.allergies = "Chicken"
        dto.foodBrand = "Renal"
        dto.notes = "Shy"
        dto.archived = true
        dto.isGuest = true
        dto.guestFrom = "Someone"
        dto.photos = [PhotoDTO(image: Data([1])), PhotoDTO(image: Data([2])), PhotoDTO(image: Data([3]))]
        dto.vaccinations = [VaccinationDTO(name: "Rabies")]
        dto.treatments = [TreatmentDTO(name: "Bravecto")]
        dto.weights = [WeightDTO(kg: 4)]
        dto.visits = [VisitDTO(clinic: "Vet")]
        dto.documents = [DocumentDTO(data: Data([9]))]
        dto.journal = [JournalDTO(text: "Hi")]
        return (dto, dto.photos[1].uuid)
    }

    @Test func defaultsShareTheEssentials() {
        let (full, profile) = fullPet()
        let shared = ShareOptions().apply(to: full, profilePhotoID: profile)
        #expect(shared.photos.map(\.uuid) == [profile], "just the profile photo")
        #expect(shared.profilePhotoID == profile)
        #expect(shared.breed == "Tabby")
        #expect(shared.specialNeeds == "Kidney diet")
        #expect(shared.vaccinations.count == 1)
        #expect(shared.weights.count == 1)
        #expect(shared.visits.isEmpty)
        #expect(shared.documents.isEmpty)
        #expect(shared.journal.isEmpty)
    }

    @Test func recipientStateIsNeverSent() {
        let (full, profile) = fullPet()
        let shared = ShareOptions().apply(to: full, profilePhotoID: profile)
        #expect(!shared.archived)
        #expect(shared.isGuest == nil)
        #expect(shared.guestFrom == nil)
        #expect(shared.guestContacts == nil)
    }

    @Test func photoChoices() {
        let (full, profile) = fullPet()
        var options = ShareOptions()
        options.photos = .none
        let none = options.apply(to: full, profilePhotoID: profile)
        #expect(none.photos.isEmpty)
        #expect(none.profilePhotoID == nil)
        options.photos = .all
        #expect(options.apply(to: full, profilePhotoID: profile).photos.count == 3)
    }

    @Test func everythingTurnedOff() {
        let (full, profile) = fullPet()
        var options = ShareOptions()
        options.details = false
        options.specialNeeds = false
        options.food = false
        options.notes = false
        options.health = false
        options.weight = false
        let shared = options.apply(to: full, profilePhotoID: profile)
        #expect([shared.breed, shared.markings, shared.microchip] == ["", "", ""])
        #expect(shared.adoptionDate == nil)
        #expect([shared.specialNeeds, shared.allergies, shared.foodBrand, shared.notes] == ["", "", "", ""])
        #expect(shared.vaccinations.isEmpty)
        #expect(shared.treatments.isEmpty)
        #expect(shared.weights.isEmpty)
        #expect(shared.name == "Murka", "the name always goes")
    }
}

@MainActor
@Suite("Sending and receiving a pet")
struct SharingTests {
    private func makePet(in store: TestStore) throws -> (Cat, Contact) {
        let cat = Cat(name: "Murka")
        cat.birthday = localDay(2015, 3, 10)
        store.context.insert(cat)
        let jpeg = try Fixture.data("tiny.jpg")
        let photo = CatPhoto(imageData: jpeg, thumbnailData: jpeg)
        store.context.insert(photo)
        photo.cat = cat
        let vaccination = Vaccination(name: "Rabies")
        vaccination.dateGiven = localDay(2025, 11, 10)
        vaccination.nextDue = localDay(2026, 11, 10)
        store.context.insert(vaccination)
        vaccination.cat = cat
        let vet = Contact(name: "Steisneider")
        vet.role = "Vet"
        store.context.insert(vet)
        try store.context.save()
        return (cat, vet)
    }

    private func share(_ cat: Cat, sender: String = " David ", contacts: [Contact], in store: TestStore) async throws -> BackupFile {
        let url = try #require(await CatShareBuilder.makeFile(for: cat, options: ShareOptions(), sender: sender,
                                                              ownContacts: contacts, context: store.context))
        #expect(url.pathExtension == "petobase")
        let (file, source) = try BackupReader.read(url)
        #expect(source == .catShare)
        return file
    }

    @Test func theShareFileCarriesThePetAndSender() async throws {
        let store = try TestStore()
        let (cat, vet) = try makePet(in: store)
        let file = try await share(cat, contacts: [vet], in: store)

        #expect(file.sharedBy == "David", "the sender's name is trimmed")
        #expect(file.cats.count == 1)
        #expect(file.cats[0].name == "Murka")
        #expect(file.cats[0].photos.count == 1)
        #expect(file.contacts.map(\.name) == ["Steisneider"])
        let shareID = try #require(cat.shareID, "the first share gives the pet an ID")
        #expect(file.cats[0].shareID == shareID)

        let again = try await share(cat, contacts: [vet], in: store)
        #expect(again.cats[0].shareID == shareID, "later shares reuse it, so the recipient can update")
    }

    @Test func receivingAddsAGuestPet() async throws {
        let sender = try TestStore()
        let (cat, vet) = try makePet(in: sender)
        let file = try await share(cat, contacts: [vet], in: sender)

        let recipient = try TestStore()
        let received = ReceivedShare(file: file)
        #expect(GuestImporter.existingGuest(for: received, in: recipient.context) == nil)

        let guest = try await GuestImporter.add(received, replacing: nil, in: recipient.context)
        #expect(guest.isGuest)
        #expect(guest.guestFrom == "David")
        #expect(guest.guestReceivedAt != nil)
        #expect(guest.guestContacts.map(\.name) == ["Steisneider"])
        #expect(guest.shareID == cat.shareID)
        #expect(guest.birthday == localDay(2015, 3, 10))
        #expect(guest.vaccinations?.first?.name == "Rabies")
    }

    @Test func aNewShareCanUpdateTheOldCopy() async throws {
        let sender = try TestStore()
        let (cat, vet) = try makePet(in: sender)
        let first = try await share(cat, contacts: [vet], in: sender)

        let recipient = try TestStore()
        let oldCopy = try await GuestImporter.add(ReceivedShare(file: first), replacing: nil, in: recipient.context)
        oldCopy.notes = "My own edit"
        try recipient.context.save()

        cat.notes = "Now on a new diet"
        let second = ReceivedShare(file: try await share(cat, contacts: [vet], in: sender))
        let existing = try #require(GuestImporter.existingGuest(for: second, in: recipient.context))
        #expect(existing === oldCopy)

        _ = try await GuestImporter.add(second, replacing: existing, in: recipient.context)
        let guests = try recipient.all(Cat.self)
        #expect(guests.count == 1, "updating replaces the copy")
        #expect(guests.first?.notes == "Now on a new diet")
        #expect(try recipient.all(Vaccination.self).count == 1, "the old copy's records go with it")
    }

    @Test func keepingBothMakesTwoCopies() async throws {
        let sender = try TestStore()
        let (cat, vet) = try makePet(in: sender)
        let file = try await share(cat, contacts: [vet], in: sender)

        let recipient = try TestStore()
        _ = try await GuestImporter.add(ReceivedShare(file: file), replacing: nil, in: recipient.context)
        _ = try await GuestImporter.add(ReceivedShare(file: file), replacing: nil, in: recipient.context)
        #expect(try recipient.all(Cat.self).count == 2)
    }

    @Test func resharingAGuestPassesOnTheOwnersContacts() async throws {
        let store = try TestStore()
        let guest = Cat(name: "Splinter")
        guest.isGuest = true
        guest.guestFrom = "Anna"
        guest.guestContactsData = try JSONEncoder().encode([ContactDTO(role: "Owner", name: "Anna", phone: "+972541234567")])
        store.context.insert(guest)
        let myVet = Contact(name: "My vet")
        store.context.insert(myVet)
        try store.context.save()

        let file = try await share(guest, contacts: [myVet], in: store)
        #expect(file.contacts.map(\.name) == ["Anna"], "the owner's contacts, not mine")
    }

    @Test func fullBackupIsNotAShare() throws {
        let file = BackupFile()
        let url = try temporaryFile(try BackupFile.encoder().encode(file), name: "full.petobase")
        #expect(try BackupReader.read(url).1 == .app)
    }
}
