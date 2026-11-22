import Foundation
import SwiftData
@testable import CatOBase

/// A fresh in-memory database, so tests never touch your real pets.
@MainActor
final class TestStore {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        let schema = Schema(AppSchema.models)
        let configuration = ModelConfiguration(UUID().uuidString, schema: schema,
                                               isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: configuration)
    }

    func all<Model: PersistentModel>(_ type: Model.Type) throws -> [Model] {
        try context.fetch(FetchDescriptor<Model>())
    }

    func cat(named name: String) throws -> Cat? {
        try all(Cat.self).first { $0.name == name }
    }
}

/// Files in CatOBaseTests/Fixtures, made from the real web app by make_fixtures.py.
enum Fixture {
    private final class BundleToken {}

    struct Missing: Error, CustomStringConvertible {
        let name: String
        var description: String { "Fixture \(name) isn't in the test bundle" }
    }

    static func url(_ name: String) throws -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = Bundle(for: BundleToken.self).url(forResource: base, withExtension: ext) else {
            throw Missing(name: name)
        }
        return url
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }
}

/// Local midnight (or another hour) on a calendar day.
func localDay(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

/// [year, month, day] of a date in the local time zone, for comparing days.
func ymd(_ date: Date?) -> [Int]? {
    guard let date else { return nil }
    let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return [parts.year!, parts.month!, parts.day!]
}

/// Writes data to a new temporary file and returns its URL.
func temporaryFile(_ data: Data, name: String) throws -> URL {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("catobase-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent(name)
    try data.write(to: url)
    return url
}

/// A date with whole seconds, so it survives the ISO 8601 round trip unchanged.
func wholeSeconds(_ date: Date) -> Date {
    Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
}
