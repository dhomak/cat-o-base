import SwiftData
import SwiftUI

struct SettingsView: View {
    @Query private var cats: [Cat]
    @Query private var photos: [CatPhoto]
    @Query private var contacts: [Contact]

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your data") {
                    LabeledContent("Cats", value: "\(cats.count)")
                    LabeledContent("Photos", value: "\(photos.count)")
                    LabeledContent("Contacts", value: "\(contacts.count)")
                    LabeledContent("Stored", value: "On this device")
                }
                Section("Coming soon") {
                    Label("Reminders for due dates", systemImage: "bell")
                    Label("Backup, export and import", systemImage: "externaldrive")
                    Label("iCloud sync", systemImage: "icloud")
                }
                Section {
                    LabeledContent("Version", value: version)
                    Link("Cat-o-Base on GitHub", destination: URL(string: "https://github.com/dhomak/cat-o-base")!)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewData.container)
}
