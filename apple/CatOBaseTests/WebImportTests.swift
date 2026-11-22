import Foundation
import Testing
@testable import CatOBase

@Suite("Zip reader")
struct ZipReaderTests {
    private let hello = String(repeating: "Hello, Pet-o-Base! ", count: 20)

    @Test(arguments: ["stored.zip", "deflated.zip"])
    func readsEntries(fixture: String) throws {
        let zip = try ZipArchive(data: try Fixture.data(fixture))
        #expect(Set(zip.entries.keys) == ["hello.txt", "folder/empty.txt"])
        #expect(zip.extract("hello.txt").map { String(decoding: $0, as: UTF8.self) } == hello)
        #expect(zip.extract("folder/empty.txt") == Data())
        #expect(zip.extract("missing.txt") == nil)
    }

    @Test func readsPastAComment() throws {
        let zip = try ZipArchive(data: try Fixture.data("comment.zip"))
        #expect(zip.extract("hello.txt").map { String(decoding: $0, as: UTF8.self) } == hello)
    }

    @Test func refusesBrokenArchives() throws {
        #expect(throws: ZipArchive.ZipError.self) { try ZipArchive(data: try Fixture.data("truncated.zip")) }
        #expect(throws: ZipArchive.ZipError.self) { try ZipArchive(data: Data("not a zip".utf8)) }
        #expect(throws: ZipArchive.ZipError.self) { try ZipArchive(data: Data()) }
    }

    @Test func errorsAreReadable() {
        #expect(ZipArchive.ZipError.notAZip.localizedDescription == "This file isn't a valid zip archive.")
    }
}

/// web-backup.zip, web-export.json and web-share.petobase come from the real web app
/// (Fixtures/make_fixtures.py): Murka the cat with everything, Rex the dog, and
/// Splinter, a guest rat from Anna.
@MainActor
@Suite("Importing from the web app")
struct WebImportTests {
    @Test func fullBackupZip() throws {
        let (file, source) = try BackupReader.read(try Fixture.url("web-backup.zip"))
        #expect(source == .webZip)
        #expect(file.cats.map(\.name).sorted() == ["Murka", "Rex", "Splinter"])

        let murka = try #require(file.cats.first { $0.name == "Murka" })
        #expect(murka.species == "cat")
        #expect(murka.sex == "female")
        #expect(murka.neutered)
        #expect(murka.breed == "Domestic shorthair")
        #expect(murka.markings == "Tabby, white socks")
        #expect(murka.microchip == "972000123456789")
        #expect(ymd(murka.birthday) == [2015, 3, 10], "web dates land on the same local day")
        #expect(ymd(murka.adoptionDate) == [2016, 5, 1])
        #expect(murka.specialNeeds == "Kidney diet")
        #expect(murka.allergies == "Chicken")
        #expect(murka.foodBrand == "Royal Canin Renal")
        #expect(murka.foodPortion == "½ pouch")
        #expect(murka.notes == "Hides under the bed")

        #expect(murka.photos.count == 2)
        #expect(murka.photos.allSatisfy { $0.image.starts(with: [0xFF, 0xD8]) }, "photos are the JPEGs from media/")
        let profile = try #require(murka.profilePhotoID)
        #expect(murka.photos.contains { $0.uuid == profile })

        let rabies = try #require(murka.vaccinations.first)
        #expect(rabies.name == "Rabies")
        #expect(ymd(rabies.dateGiven) == [2025, 11, 10])
        #expect(ymd(rabies.nextDue) == [2026, 11, 10])

        let bravecto = try #require(murka.treatments.first)
        #expect(bravecto.kind == TreatmentKind.fleaTick.rawValue, "web 'flea/tick' maps to fleaTick")
        #expect(bravecto.dose == "1 pipette")
        #expect(bravecto.intervalDays == 90)
        #expect(ymd(bravecto.lastGiven) == [2026, 10, 1])
        #expect(ymd(bravecto.nextDue) == [2026, 12, 30])
        #expect(bravecto.active)

        #expect(murka.weights.sorted { $0.date < $1.date }.map(\.kg) == [4.6, 4.1])
        #expect(murka.visits.first?.clinic == "Steisneider")
        #expect(murka.visits.first?.cost == "350")

        let document = try #require(murka.documents.first)
        #expect(document.title == "Bloodwork")
        #expect(document.filename == "bloodwork.pdf")
        #expect(document.typeIdentifier == "com.adobe.pdf")
        #expect(document.data.starts(with: Array("%PDF".utf8)))

        #expect(murka.journal.first?.kind == "nails")
        #expect(murka.journal.first?.text == "Trimmed")

        let rex = try #require(file.cats.first { $0.name == "Rex" })
        #expect(rex.species == "dog")
        #expect(rex.sex == "male")
        #expect(rex.birthday == nil)
        #expect(rex.isGuest != true)

        let splinter = try #require(file.cats.first { $0.name == "Splinter" })
        #expect(splinter.species == "rat")
        #expect(splinter.isGuest == true)
        #expect(splinter.guestFrom == "Anna")
        #expect(ymd(splinter.guestReceivedAt) == [2026, 11, 15])
        #expect(splinter.guestContacts?.map(\.phone) == ["+972541234567"])

        #expect(file.contacts.map(\.name) == ["Steisneider"])
        #expect(file.contacts.first?.role == "vet")
    }

    @Test func fullBackupImportsIntoTheApp() async throws {
        let (file, _) = try BackupReader.read(try Fixture.url("web-backup.zip"))
        let store = try TestStore()
        let summary = try await BackupImporter.run(file, into: store.context, replace: false) { _ in }
        #expect(summary.cats == 3)
        #expect(summary.photos == 2, "web photos have no thumbnail, so the app makes one")
        #expect(summary.documents == 1)
        #expect(summary.contacts == 1)

        let murka = try #require(try store.cat(named: "Murka"))
        #expect(murka.photos?.allSatisfy { $0.thumbnailData != nil } == true)
        #expect(murka.profilePhoto != nil)
        #expect(murka.dueItems.map(\.title).contains("Bravecto"))
        #expect(try store.cat(named: "Splinter")?.isGuest == true)
        #expect(try store.cat(named: "Rex")?.species == .dog)
    }

    @Test func dataOnlyExport() throws {
        let (file, source) = try BackupReader.read(try Fixture.url("web-export.json"))
        #expect(source == .webJSON)
        #expect(file.cats.count == 3)
        let murka = try #require(file.cats.first { $0.name == "Murka" })
        #expect(murka.photos.isEmpty, "the JSON export has no media")
        #expect(murka.documents.isEmpty)
        #expect(murka.vaccinations.count == 1)
        #expect(ymd(murka.birthday) == [2015, 3, 10])
    }

    @Test func petSharedFromTheWeb() async throws {
        let (file, source) = try BackupReader.read(try Fixture.url("web-share.petobase"))
        #expect(source == .catShare)
        #expect(file.sharedBy == "David")
        let murka = try #require(file.cats.first)
        #expect(murka.name == "Murka")
        #expect(ymd(murka.birthday) == [2015, 3, 10], "noon UTC shows as the same day in any time zone")
        #expect(murka.photos.count == 2)
        #expect(murka.visits.count == 1)
        #expect(murka.documents.count == 1)
        #expect(murka.journal.count == 1)
        #expect(murka.treatments.first?.kind == TreatmentKind.fleaTick.rawValue)
        #expect(murka.shareID != nil, "lets a later share update this copy")

        let store = try TestStore()
        let guest = try await GuestImporter.add(ReceivedShare(file: file), replacing: nil, in: store.context)
        #expect(guest.isGuest)
        #expect(guest.guestFrom == "David")
        #expect(guest.photos?.count == 2)
        #expect(guest.documents?.count == 1)
    }
}
