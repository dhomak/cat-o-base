import Foundation
import SwiftData

/// Sample data for Xcode previews only. Not used by the running app.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let schema = Schema(AppSchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Preview container failed: \(error)")
        }
        let context = container.mainContext

        context.insert(murka)
        murka.weights = [
            WeightEntry(date: daysAgo(180), kg: 4.6),
            WeightEntry(date: daysAgo(90), kg: 4.4),
            WeightEntry(date: daysAgo(5), kg: 4.2),
        ]

        let barsik = Cat(name: "Barsik")
        barsik.sex = .male
        barsik.birthday = Calendar.current.date(byAdding: .year, value: -3, to: .now)
        context.insert(barsik)

        let shusha = Cat(name: "Shusha")
        shusha.sex = .female
        shusha.birthday = Calendar.current.date(byAdding: .month, value: -82, to: .now)
        shusha.birthdayApprox = true
        context.insert(shusha)

        let vet = Contact(name: "Vet TLV")
        vet.role = "Vet"
        vet.phone = "+972 3 000 0000"
        context.insert(vet)

        return container
    }()

    static let murka: Cat = {
        let cat = Cat(name: "Murka")
        cat.sex = .female
        cat.neutered = true
        cat.birthday = Calendar.current.date(byAdding: .year, value: -11, to: .now)
        cat.breed = "Domestic shorthair"
        cat.markings = "Tabby"
        cat.microchip = "972000123456789"
        cat.specialNeeds = "Early CKD: renal diet only, keep water bowls full."
        cat.allergies = "Chicken"
        cat.foodBrand = "Royal Canin Renal, wet"
        cat.foodPortion = "1 pouch"
        cat.foodSchedule = "08:00 and 20:00"
        cat.notes = "Hides under the bed when the doorbell rings."
        return cat
    }()

    private static func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
    }
}
