import SwiftData
import SwiftUI

@main
struct CatOBaseApp: App {
    let container: ModelContainer = {
        let schema = Schema(AppSchema.models)
        // Local-only for now. To turn on iCloud later: add the iCloud/CloudKit
        // capability and change `.none` to `.automatic`.
        let configuration = ModelConfiguration("CatOBase", schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Could not open the Cat-o-Base database: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
