import SwiftData
import SwiftUI

struct SettingsView: View {
    @Query private var cats: [Cat]
    @Query private var photos: [CatPhoto]
    @Query private var contacts: [Contact]
    @AppStorage(PrefKey.catSort) private var sort: CatSort = .name
    @AppStorage(PrefKey.weightUnit) private var unit: WeightUnit = .kg

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    Picker("Sort cats by", selection: $sort) {
                        ForEach(CatSort.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    Picker("Weight unit", selection: $unit) {
                        ForEach(WeightUnit.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                }
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
