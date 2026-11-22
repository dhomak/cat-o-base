import Foundation
import SwiftData
import Testing
@testable import CatOBase

@MainActor
@Suite("Vaccines, treatments, weight and reminders")
struct HealthTests {
    let now = localDay(2026, 11, 22, hour: 10)

    private func makeCat(_ store: TestStore, name: String = "Murka") -> Cat {
        let cat = Cat(name: name)
        store.context.insert(cat)
        return cat
    }

    @discardableResult
    private func vaccine(_ name: String, given: Date?, due: Date?, for cat: Cat, in store: TestStore) -> Vaccination {
        let vaccination = Vaccination(name: name)
        vaccination.dateGiven = given
        vaccination.nextDue = due
        store.context.insert(vaccination)
        vaccination.cat = cat
        return vaccination
    }

    @Test func onlyTheNewestDoseIsDue() throws {
        let store = try TestStore()
        let cat = makeCat(store)
        let old = vaccine("Rabies", given: localDay(2024, 11, 10), due: localDay(2025, 11, 10), for: cat, in: store)
        let current = vaccine("rabies ", given: localDay(2025, 11, 10), due: localDay(2026, 11, 10), for: cat, in: store)

        #expect(!old.isCurrent(among: [old, current]), "names match ignoring case and spaces")
        #expect(current.isCurrent(among: [old, current]))
        #expect(cat.dueItems.count == 1)
        #expect(ymd(cat.dueItems.first?.date) == [2026, 11, 10])
        #expect(current.repeatMonths == 12)
    }

    @Test func recordingTheNextDoseKeepsTheInterval() throws {
        let store = try TestStore()
        let cat = makeCat(store)
        let current = vaccine("Rabies", given: localDay(2025, 11, 10), due: localDay(2026, 11, 10), for: cat, in: store)

        let dose = current.recordNextDose(on: localDay(2026, 11, 22), in: store.context)
        #expect(dose.name == "Rabies")
        #expect(ymd(dose.nextDue) == [2027, 11, 22])
        #expect(dose.cat === cat)
        #expect(!current.isCurrent(among: cat.vaccinations ?? []))
        #expect(ymd(cat.dueItems.first?.date) == [2027, 11, 22])
    }

    @Test func vaccineWithoutRepeatHasNoNextDose() throws {
        let store = try TestStore()
        let cat = makeCat(store)
        let once = vaccine("FIP", given: localDay(2026, 1, 1), due: nil, for: cat, in: store)
        #expect(once.repeatMonths == nil)
        #expect(once.recordNextDose(on: now, in: store.context).nextDue == nil)
        #expect(cat.dueItems.isEmpty)
    }

    @Test func markingATreatmentGivenMovesItForward() throws {
        let store = try TestStore()
        let cat = makeCat(store)
        let treatment = Treatment(name: "Bravecto")
        treatment.intervalDays = 90
        store.context.insert(treatment)
        treatment.cat = cat

        treatment.markGiven(on: localDay(2026, 10, 1))
        #expect(ymd(treatment.lastGiven) == [2026, 10, 1])
        #expect(ymd(treatment.nextDue) == [2026, 12, 30])
        #expect(cat.dueItems.count == 1)

        treatment.intervalDays = nil
        treatment.markGiven(on: now)
        #expect(treatment.nextDue == nil, "no repeat means nothing more is due")
        #expect(cat.dueItems.isEmpty)
    }

    @Test func stoppedAndFinishedTreatmentsAreNotDue() throws {
        let store = try TestStore()
        let cat = makeCat(store)
        let stopped = Treatment(name: "Milbemax")
        stopped.nextDue = localDay(2026, 12, 1)
        stopped.active = false
        let finished = Treatment(name: "Antibiotic")
        finished.nextDue = localDay(2026, 12, 1)
        finished.endDate = localDay(2026, 11, 30)
        let running = Treatment(name: "Bravecto")
        running.nextDue = localDay(2026, 12, 5)
        for treatment in [stopped, finished, running] {
            store.context.insert(treatment)
            treatment.cat = cat
        }
        #expect(cat.dueItems.map(\.title) == ["Bravecto"])
    }

    @Test func weightLossWarning() throws {
        let store = try TestStore()
        let cat = makeCat(store)
        for (date, kg) in [(localDay(2026, 5, 1), 4.6), (localDay(2026, 8, 1), 4.4), (localDay(2026, 11, 1), 4.1)] {
            let entry = WeightEntry(date: date, kg: kg)
            store.context.insert(entry)
            entry.cat = cat
        }
        let trend = try #require(cat.weightTrend)
        #expect(trend.latest.kg == 4.1)
        #expect(abs((trend.changeSincePrevious ?? 0) - -0.3) < 1e-9)
        #expect(ymd(trend.referenceDate) == [2026, 5, 1], "compares with about six months back")
        #expect(abs((trend.percentChange ?? 0) - (4.1 - 4.6) / 4.6 * 100) < 1e-9)
        #expect(trend.isWarning, "a loss of more than 10% is flagged")
    }

    @Test func oneWeighInHasNoTrend() throws {
        let store = try TestStore()
        let cat = makeCat(store)
        let entry = WeightEntry(date: now, kg: 4)
        store.context.insert(entry)
        entry.cat = cat
        let trend = try #require(cat.weightTrend)
        #expect(trend.changeSincePrevious == nil)
        #expect(trend.percentChange == nil)
        #expect(!trend.isWarning)
    }

    @Test func remindersOnTheDayAndTheDayBefore() throws {
        let store = try TestStore()
        let cat = makeCat(store)
        let treatment = Treatment(name: "Bravecto")
        treatment.nextDue = localDay(2026, 11, 25)
        store.context.insert(treatment)
        treatment.cat = cat

        let settings = ReminderSettings(enabled: true, minutes: 9 * 60, dayBefore: true, badge: true)
        let plans = ReminderScheduler.plans(for: cat.dueItems, settings: settings, now: now)
        #expect(plans.count == 2)
        #expect(plans.map(\.fireDate) == [localDay(2026, 11, 24, hour: 9), localDay(2026, 11, 25, hour: 9)])
        #expect(plans.map(\.title) == ["Murka: Bravecto due tomorrow", "Murka: Bravecto due today"])

        var noDayBefore = settings
        noDayBefore.dayBefore = false
        #expect(ReminderScheduler.plans(for: cat.dueItems, settings: noDayBefore, now: now).count == 1)
    }

    @Test func noRemindersInThePast() throws {
        let store = try TestStore()
        let cat = makeCat(store)
        let treatment = Treatment(name: "Bravecto")
        treatment.nextDue = localDay(2026, 11, 22) // today; 9:00 has already passed at 10:00
        store.context.insert(treatment)
        treatment.cat = cat

        let settings = ReminderSettings(enabled: true, minutes: 9 * 60, dayBefore: true, badge: true)
        #expect(ReminderScheduler.plans(for: cat.dueItems, settings: settings, now: now).isEmpty)
    }

    @Test func sortingByAge() throws {
        let store = try TestStore()
        let old = makeCat(store, name: "Old")
        old.birthday = localDay(2012, 1, 1)
        let young = makeCat(store, name: "Young")
        young.birthday = localDay(2024, 1, 1)
        let unknownB = makeCat(store, name: "B unknown")
        let unknownA = makeCat(store, name: "a unknown")
        let cats = [young, unknownB, old, unknownA]

        #expect(CatSort.oldestFirst.sorted(cats).map(\.name) == ["Old", "Young", "a unknown", "B unknown"])
        #expect(CatSort.youngestFirst.sorted(cats).map(\.name) == ["Young", "Old", "a unknown", "B unknown"])
        #expect(CatSort.name.sorted(cats).map(\.name) == ["a unknown", "B unknown", "Old", "Young"])
    }
}
