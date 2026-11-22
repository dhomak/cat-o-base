import Foundation
import Testing
@testable import CatOBase

/// These expect English text: the test scheme runs in English (project.yml, test: language).
@Suite("Formatting")
struct FormattingTests {
    let now = localDay(2026, 11, 22, hour: 10)

    @Test func age() {
        #expect(Fmt.age(from: localDay(2023, 6, 10), now: now) == "3 y 5 mo")
        #expect(Fmt.age(from: localDay(2024, 11, 22), now: now) == "2 y")
        #expect(Fmt.age(from: localDay(2026, 4, 1), now: now) == "7 mo")
        #expect(Fmt.age(from: localDay(2027, 1, 1), now: now) == nil, "a birthday in the future has no age")
        #expect(Fmt.age(from: nil, now: now) == nil)
    }

    @Test func relativeDue() {
        #expect(Fmt.relativeDue(localDay(2026, 11, 22, hour: 23), now: now) == "today")
        #expect(Fmt.relativeDue(localDay(2026, 11, 23), now: now) == "tomorrow")
        #expect(Fmt.relativeDue(localDay(2026, 11, 28), now: now) == "in 6 days")
        #expect(Fmt.relativeDue(localDay(2026, 11, 21), now: now) == "1 day overdue")
        #expect(Fmt.relativeDue(localDay(2026, 11, 17), now: now) == "5 days overdue")
    }

    @Test func intervals() {
        #expect(Fmt.interval(days: 1) == "daily")
        #expect(Fmt.interval(days: 7) == "weekly")
        #expect(Fmt.interval(days: 14) == "every 2 weeks")
        #expect(Fmt.interval(days: 90) == "every 90 days")
        #expect(Fmt.interval(days: 21) == "every 21 days")
    }

    @Test func dueStatus() {
        #expect(DueStatus(localDay(2026, 11, 21), now: now) == .overdue)
        #expect(DueStatus(localDay(2026, 11, 22), now: now) == .soon)
        #expect(DueStatus(localDay(2026, 12, 6), now: now) == .soon, "14 days ahead still counts as soon")
        #expect(DueStatus(localDay(2026, 12, 7), now: now) == .later)
        #expect(DueStatus.days(until: localDay(2026, 11, 22, hour: 0), now: now) == 0, "counts calendar days, not hours")
    }

    @Test func percentages() {
        #expect(Fmt.percent(12.5) == "12.5%")
        #expect(Fmt.signedPercent(3.14) == "+3.1%")
        #expect(Fmt.signedPercent(-12.5) == "−12.5%")
    }

    @Test(arguments: [("4,2", 4.2), ("4.2", 4.2), (" 4.2 ", 4.2), ("0", nil), ("abc", nil), ("120", nil), ("", nil)] as [(String, Double?)])
    func weightParsing(input: String, expected: Double?) {
        #expect(WeightUnit.parse(input) == expected)
    }

    @Test func weightUnits() {
        #expect(abs(WeightUnit.lb.fromKilograms(1) - 2.2046226218) < 1e-9)
        #expect(abs(WeightUnit.lb.toKilograms(WeightUnit.lb.fromKilograms(4.1)) - 4.1) < 1e-9)
        #expect(WeightUnit.kg.fromKilograms(4.1) == 4.1)
        #expect(WeightUnit.kg.formatChange(kilograms: 0.25) == "+0.25 kg")
        #expect(WeightUnit.kg.formatChange(kilograms: -0.5) == "−0.5 kg")
        #expect(WeightUnit.kg.formatChange(kilograms: 0) == "no change")
    }

    @Test func importSummaryUsesPlurals() {
        let summary = ImportSummary(cats: 1, photos: 2, documents: 0, contacts: 1)
        #expect(summary.text == "1 pet, 2 photos, 0 documents, 1 contact")
    }

    @Test func gotchaDayInEnglish() {
        #expect(Species.cat.gotchaDayLabel == "Gotcha day")
        #expect(Species.dog.gotchaDayLabel == "Gotcha day")
    }
}
