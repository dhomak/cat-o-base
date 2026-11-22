import SwiftData
import SwiftUI
import UserNotifications

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
            fatalError("Could not open the Pet-o-Base database: \(error)")
        }
    }()

    init() {
        // Set early so taps on notifications that launched the app are handled.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup(id: WindowID.main) {
            RootView()
        }
        .modelContainer(container)
        .commands {
            CatOBaseCommands()
            #if os(macOS)
            // File → Import from iPhone: take a photo or scan a document (Continuity Camera).
            ImportFromDevicesCommands()
            #endif
        }

        // One cat in its own window (Mac, and iPad with multiple windows).
        WindowGroup("Pet", id: WindowID.cat, for: PersistentIdentifier.self) { $id in
            if let id {
                CatWindowView(id: id)
            }
        }
        .modelContainer(container)

        #if os(macOS)
        // Pet-o-Base → Settings… (⌘,)
        Settings {
            SettingsView()
                .frame(width: 520, height: 680)
        }
        .modelContainer(container)
        #endif
    }
}
