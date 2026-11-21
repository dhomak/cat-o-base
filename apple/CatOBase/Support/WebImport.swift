import Compression
import Foundation
import SQLite3
import UniformTypeIdentifiers

/// Imports data from the Cat-o-Base web app: its "Full backup" zip (SQLite
/// database plus media folder) or its "Data only" JSON export.
enum WebImport {
    typealias Row = [String: SQLValue]

    static let tables = ["cats", "photos", "weights", "vaccinations", "treatments",
                         "visits", "documents", "logs", "contacts"]
    /// Database names inside the zip, current and pre-rename.
    static let databaseNames = ["catobase.sqlite3", "catdb.sqlite3"]

    static func backup(fromZip data: Data) throws -> BackupFile {
        let zip = try ZipArchive(data: data)
        guard let dbName = databaseNames.first(where: { zip.entries[$0] != nil }),
              let dbData = zip.extract(dbName)
        else { throw BackupError.unknownFormat }

        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("web-import-\(UUID().uuidString).sqlite3")
        try dbData.write(to: dbURL)
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let reader = try SQLiteReader(path: dbURL.path)
        var tableRows: [String: [Row]] = [:]
        for table in tables {
            tableRows[table] = reader.rows(of: table)
        }
        return build(tableRows) { filename in zip.extract("media/" + filename) }
    }

    static func backup(fromJSON data: Data) throws -> BackupFile {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackupError.unknownFormat
        }
        var tableRows: [String: [Row]] = [:]
        for table in tables {
            let rows = object[table] as? [[String: Any]] ?? []
            tableRows[table] = rows.map { $0.mapValues(SQLValue.init(json:)) }
        }
        return build(tableRows) { _ in nil }
    }

    // MARK: Mapping web tables to the backup format

    private static func build(_ tables: [String: [Row]], media: (String) -> Data?) -> BackupFile {
        func rows(_ table: String) -> [Row] { tables[table] ?? [] }
        func byCat(_ table: String) -> [Int: [Row]] {
            Dictionary(grouping: rows(table)) { $0.int("cat_id") ?? -1 }
        }
        let photos = byCat("photos")
        let weights = byCat("weights")
        let vaccinations = byCat("vaccinations")
        let treatments = byCat("treatments")
        let visits = byCat("visits")
        let documents = byCat("documents")
        let logs = byCat("logs")

        var file = BackupFile()
        for row in rows("cats") {
            guard let id = row.int("id") else { continue }
            var cat = CatDTO()
            cat.name = row.text("name")
            let sex = row.text("sex").lowercased()
            cat.sex = CatSex(rawValue: sex)?.rawValue ?? CatSex.unknown.rawValue
            cat.neutered = row.bool("neutered")
            cat.breed = row.text("breed")
            cat.markings = row.text("markings")
            cat.microchip = row.text("microchip")
            cat.birthday = row.day("birthday")
            cat.birthdayApprox = row.bool("birthday_approx")
            cat.adoptionDate = row.day("adoption_date")
            cat.specialNeeds = row.text("special_needs")
            cat.allergies = row.text("allergies")
            cat.foodBrand = row.text("food_brand")
            cat.foodPortion = row.text("food_portion")
            cat.foodSchedule = row.text("food_schedule")
            cat.foodNotes = row.text("food_notes")
            cat.notes = row.text("notes")
            cat.archived = row.bool("archived")
            cat.createdAt = row.timestamp("created_at") ?? Date()

            let profileID = row.int("profile_photo_id")
            for photo in photos[id] ?? [] {
                let filename = photo.text("filename")
                guard !filename.isEmpty, let image = media(filename) else { continue }
                let uuid = UUID()
                if let profileID, photo.int("id") == profileID {
                    cat.profilePhotoID = uuid
                }
                cat.photos.append(PhotoDTO(uuid: uuid, image: image, thumbnail: nil,
                                           caption: photo.text("caption"), takenOn: photo.day("taken_on"),
                                           addedAt: photo.timestamp("created_at") ?? Date()))
            }

            cat.vaccinations = (vaccinations[id] ?? []).map {
                VaccinationDTO(name: $0.text("name"), dateGiven: $0.day("date_given"),
                               nextDue: $0.day("next_due"), vet: $0.text("vet"), notes: $0.text("notes"))
            }
            cat.treatments = (treatments[id] ?? []).map {
                let interval = $0.int("interval_days")
                return TreatmentDTO(kind: treatmentKind($0.text("kind")).rawValue, name: $0.text("name"),
                                    dose: $0.text("dose"), schedule: $0.text("schedule"),
                                    intervalDays: (interval ?? 0) > 0 ? interval : nil,
                                    lastGiven: $0.day("last_given"), nextDue: $0.day("next_due"),
                                    endDate: $0.day("end_date"), active: $0.bool("active", default: true),
                                    notes: $0.text("notes"))
            }
            cat.weights = (weights[id] ?? []).compactMap {
                guard let kg = $0.double("kg"), let date = $0.day("date") else { return nil }
                return WeightDTO(date: date, kg: kg)
            }
            cat.visits = (visits[id] ?? []).map {
                VisitDTO(date: $0.day("date") ?? Date(), clinic: $0.text("clinic"), reason: $0.text("reason"),
                         outcome: $0.text("outcome"), cost: $0.text("cost"), notes: $0.text("notes"))
            }
            cat.documents = (documents[id] ?? []).compactMap { document in
                let stored = document.text("filename")
                guard !stored.isEmpty, let data = media(stored) else { return nil }
                let original = document.text("original_name")
                let name = original.isEmpty ? stored : original
                let ext = (name as NSString).pathExtension
                let type = UTType(filenameExtension: ext) ?? .data
                let title = document.text("title")
                return DocumentDTO(title: title.isEmpty ? name : title, filename: name,
                                   typeIdentifier: type.identifier, data: data,
                                   addedAt: document.timestamp("created_at") ?? Date())
            }
            cat.journal = (logs[id] ?? []).map {
                let kind = $0.text("kind")
                return JournalDTO(date: $0.day("date") ?? Date(), kind: kind.isEmpty ? "note" : kind,
                                  text: $0.text("text"))
            }
            file.cats.append(cat)
        }

        file.contacts = rows("contacts").map {
            ContactDTO(role: $0.text("role"), name: $0.text("name"), phone: $0.text("phone"),
                       address: $0.text("address"), notes: $0.text("notes"))
        }
        return file
    }

    private static func treatmentKind(_ web: String) -> TreatmentKind {
        switch web.lowercased() {
        case "medication": return .medication
        case "flea/tick", "flea", "tick": return .fleaTick
        case "deworming": return .deworming
        case "supplement": return .supplement
        default: return .other
        }
    }
}

// MARK: - SQLite values

enum SQLValue {
    case integer(Int64)
    case real(Double)
    case text(String)
    case null

    init(json value: Any) {
        switch value {
        case let string as String:
            self = .text(string)
        case let number as NSNumber:
            self = CFNumberIsFloatType(number as CFNumber) ? .real(number.doubleValue) : .integer(number.int64Value)
        default:
            self = .null
        }
    }
}

private enum WebDates {
    /// "2026-11-21" as local midnight.
    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// SQLite CURRENT_TIMESTAMP: "2026-11-21 10:47:03" in UTC.
    static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

extension Dictionary where Key == String, Value == SQLValue {
    func text(_ key: String) -> String {
        switch self[key] {
        case .text(let value): return value.trimmed
        case .integer(let value): return String(value)
        case .real(let value): return String(value)
        default: return ""
        }
    }

    func int(_ key: String) -> Int? {
        switch self[key] {
        case .integer(let value): return Int(value)
        case .real(let value): return Int(value)
        case .text(let value): return Int(value.trimmed)
        default: return nil
        }
    }

    func double(_ key: String) -> Double? {
        switch self[key] {
        case .integer(let value): return Double(value)
        case .real(let value): return value
        case .text(let value): return Double(value.trimmed)
        default: return nil
        }
    }

    func bool(_ key: String, default fallback: Bool = false) -> Bool {
        guard let value = int(key) else { return fallback }
        return value != 0
    }

    func day(_ key: String) -> Date? {
        let value = text(key)
        guard value.count >= 10 else { return nil }
        return WebDates.day.date(from: String(value.prefix(10)))
    }

    func timestamp(_ key: String) -> Date? {
        let value = text(key)
        guard value.count >= 19 else { return day(key) }
        return WebDates.timestamp.date(from: String(value.prefix(19)))
    }
}

// MARK: - SQLite reader

final class SQLiteReader {
    private var db: OpaquePointer?

    init(path: String) throws {
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            db = nil
            throw BackupError.unreadable
        }
    }

    deinit {
        sqlite3_close(db)
    }

    /// All rows of a table as column → value. Empty if the table doesn't exist.
    func rows(of table: String) -> [[String: SQLValue]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT * FROM \"\(table)\"", -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var result: [[String: SQLValue]] = []
        let columns = sqlite3_column_count(statement)
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: SQLValue] = [:]
            for index in 0..<columns {
                guard let rawName = sqlite3_column_name(statement, index) else { continue }
                let name = String(cString: rawName)
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    row[name] = .integer(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT:
                    row[name] = .real(sqlite3_column_double(statement, index))
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, index) {
                        row[name] = .text(String(cString: text))
                    } else {
                        row[name] = .null
                    }
                default:
                    row[name] = .null
                }
            }
            result.append(row)
        }
        return result
    }
}

// MARK: - Minimal ZIP reader

/// Reads standard (non-ZIP64) zip files with stored or deflated entries,
/// which is what the web app's backup produces.
struct ZipArchive {
    struct Entry {
        let name: String
        let method: Int
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    enum ZipError: Error { case notAZip, unsupported }

    private let data: Data
    let entries: [String: Entry]

    init(data: Data) throws {
        self.data = data
        let count = data.count
        guard count >= 22 else { throw ZipError.notAZip }

        // End of central directory record, searched backwards past any comment.
        var eocd: Int?
        let lowest = max(0, count - 22 - 0xFFFF)
        var position = count - 22
        while position >= lowest {
            if ZipArchive.u32(data, position) == 0x0605_4B50 {
                eocd = position
                break
            }
            position -= 1
        }
        guard let eocd else { throw ZipError.notAZip }

        let total = ZipArchive.u16(data, eocd + 10)
        let directoryOffset = ZipArchive.u32(data, eocd + 16)
        guard directoryOffset != 0xFFFF_FFFF, directoryOffset < count else { throw ZipError.unsupported }

        var entries: [String: Entry] = [:]
        var cursor = directoryOffset
        for _ in 0..<total {
            guard cursor + 46 <= count, ZipArchive.u32(data, cursor) == 0x0201_4B50 else { throw ZipError.notAZip }
            let method = ZipArchive.u16(data, cursor + 10)
            let compressed = ZipArchive.u32(data, cursor + 20)
            let uncompressed = ZipArchive.u32(data, cursor + 24)
            let nameLength = ZipArchive.u16(data, cursor + 28)
            let extraLength = ZipArchive.u16(data, cursor + 30)
            let commentLength = ZipArchive.u16(data, cursor + 32)
            let localOffset = ZipArchive.u32(data, cursor + 42)
            let nameStart = data.startIndex + cursor + 46
            guard cursor + 46 + nameLength <= count else { throw ZipError.notAZip }
            let name = String(decoding: data[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            entries[name] = Entry(name: name, method: method, compressedSize: compressed,
                                  uncompressedSize: uncompressed, localHeaderOffset: localOffset)
            cursor += 46 + nameLength + extraLength + commentLength
        }
        self.entries = entries
    }

    /// The decompressed contents of an entry, or nil if missing or unreadable.
    func extract(_ name: String) -> Data? {
        guard let entry = entries[name] else { return nil }
        let header = entry.localHeaderOffset
        guard header + 30 <= data.count, ZipArchive.u32(data, header) == 0x0403_4B50 else { return nil }
        let nameLength = ZipArchive.u16(data, header + 26)
        let extraLength = ZipArchive.u16(data, header + 28)
        let start = header + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard end <= data.count else { return nil }
        let raw = data[(data.startIndex + start)..<(data.startIndex + end)]

        switch entry.method {
        case 0:
            return Data(raw)
        case 8:
            return ZipArchive.inflate(Data(raw), expectedSize: entry.uncompressedSize)
        default:
            return nil
        }
    }

    /// Raw DEFLATE (what zip uses) via Apple's Compression framework.
    private static func inflate(_ input: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        guard !input.isEmpty else { return nil }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) -> Int in
            input.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                guard let dst = destination.bindMemory(to: UInt8.self).baseAddress,
                      let src = source.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_decode_buffer(dst, expectedSize, src, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written == expectedSize ? output : nil
    }

    private static func u16(_ data: Data, _ offset: Int) -> Int {
        let base = data.startIndex + offset
        return Int(data[base]) | Int(data[base + 1]) << 8
    }

    private static func u32(_ data: Data, _ offset: Int) -> Int {
        let base = data.startIndex + offset
        return Int(data[base]) | Int(data[base + 1]) << 8 | Int(data[base + 2]) << 16 | Int(data[base + 3]) << 24
    }
}
