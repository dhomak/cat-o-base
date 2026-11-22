import Foundation
import Testing
@testable import CatOBase

/// Reads the compiled Russian and Ukrainian strings straight from the app bundle,
/// so these run the same whatever language the test scheme uses.
@Suite("Russian and Ukrainian")
struct LocalizationTests {
    private func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"),
                                "the app has no \(language).lproj: is Localizable.xcstrings in the target?")
        return try #require(Bundle(path: path))
    }

    private func overdue(_ count: Int, _ language: String) throws -> String {
        String(localized: "\(count) days overdue", bundle: try bundle(language), locale: Locale(identifier: language))
    }

    private func years(_ count: Int, _ language: String) throws -> String {
        String(localized: "\(count) y", bundle: try bundle(language), locale: Locale(identifier: language))
    }

    private func text(_ key: String.LocalizationValue, _ language: String) throws -> String {
        String(localized: key, bundle: try bundle(language), locale: Locale(identifier: language))
    }

    @Test func russianPlurals() throws {
        #expect(try overdue(1, "ru") == "просрочено на 1 день")
        #expect(try overdue(3, "ru") == "просрочено на 3 дня")
        #expect(try overdue(5, "ru") == "просрочено на 5 дней")
        #expect(try overdue(11, "ru") == "просрочено на 11 дней")
        #expect(try overdue(21, "ru") == "просрочено на 21 день")
        #expect(try overdue(22, "ru") == "просрочено на 22 дня")
        #expect(try years(1, "ru") == "1 г.")
        #expect(try years(3, "ru") == "3 г.")
        #expect(try years(5, "ru") == "5 л.")
    }

    @Test func ukrainianPlurals() throws {
        #expect(try overdue(1, "uk") == "прострочено на 1 день")
        #expect(try overdue(3, "uk") == "прострочено на 3 дні")
        #expect(try overdue(5, "uk") == "прострочено на 5 днів")
        #expect(try overdue(21, "uk") == "прострочено на 21 день")
    }

    @Test func englishPlurals() throws {
        #expect(try overdue(1, "en") == "1 day overdue")
        #expect(try overdue(2, "en") == "2 days overdue")
    }

    @Test func gotchaDay() throws {
        #expect(try text("Cat's gotcha day", "ru") == "День укотовления")
        #expect(try text("Cat's gotcha day", "uk") == "День укотовлення")
        #expect(try text("Gotcha day", "ru") == "День появления дома")
        #expect(try text("Gotcha day", "uk") == "День появи вдома")
        #expect(try text("Cat's gotcha day", "en") == "Gotcha day")
    }

    @Test func placeholdersSurvive() throws {
        let name = "Мурка"
        #expect(String(localized: "Guest pet from \(name)", bundle: try bundle("ru"), locale: Locale(identifier: "ru"))
                == "Питомец в гостях от Мурка")
        #expect(String(localized: "Guest pet from \(name)", bundle: try bundle("uk"), locale: Locale(identifier: "uk"))
                == "Улюбленець у гостях від Мурка")
    }
}
