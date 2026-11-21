import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct SettingsView: View {
    @Query private var cats: [Cat]
    @Query private var photos: [CatPhoto]
    @Query private var contacts: [Contact]
    @AppStorage(PrefKey.catSort) private var sort: CatSort = .name
    @AppStorage(PrefKey.weightUnit) private var unit: WeightUnit = .kg
    @AppStorage(PrefKey.remindersEnabled) private var remindersEnabled = false
    @AppStorage(PrefKey.reminderMinutes) private var reminderMinutes = PrefDefault.reminderMinutes
    @AppStorage(PrefKey.remindDayBefore) private var remindDayBefore = true
    @AppStorage(PrefKey.badgeOverdue) private var badgeOverdue = true
    @Environment(\.openURL) private var openURL

    @State private var showNotificationsOff = false
    @State private var scheduledCount: Int?
    @State private var testSent = false

    private var remindersToggle: Binding<Bool> {
        Binding(
            get: { remindersEnabled },
            set: { turnOn in
                guard turnOn else {
                    remindersEnabled = false
                    return
                }
                Task {
                    let allowed = await ReminderScheduler.requestAuthorization()
                    remindersEnabled = allowed
                    if !allowed { showNotificationsOff = true }
                }
            }
        )
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60,
                                      second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                reminderMinutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
            }
        )
    }

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
                Section {
                    Toggle("Due-date reminders", isOn: remindersToggle)
                    if remindersEnabled {
                        DatePicker("Remind at", selection: reminderTime, displayedComponents: .hourAndMinute)
                        Toggle("Also the day before", isOn: $remindDayBefore)
                        Toggle("Overdue count on app icon", isOn: $badgeOverdue)
                        if let scheduledCount {
                            LabeledContent("Scheduled", value: "\(scheduledCount)")
                        }
                        Button(testSent ? "Test sent. Wait 5 seconds…" : "Send a Test Notification") {
                            testSent = true
                            Task {
                                await ReminderScheduler.sendTest()
                                try? await Task.sleep(for: .seconds(6))
                                testSent = false
                            }
                        }
                        .disabled(testSent)
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Notifications for vaccinations and treatments on their due date. They're scheduled on this device, so they work offline.")
                }

                Section("Your data") {
                    LabeledContent("Cats", value: "\(cats.count)")
                    LabeledContent("Photos", value: "\(photos.count)")
                    LabeledContent("Contacts", value: "\(contacts.count)")
                    LabeledContent("Stored", value: "On this device")
                }
                Section("Coming soon") {
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
            .task(id: remindersEnabled) {
                // Give RootView a moment to reschedule before counting.
                try? await Task.sleep(for: .seconds(1))
                scheduledCount = await ReminderScheduler.pendingCount()
            }
            .alert("Notifications are turned off", isPresented: $showNotificationsOff) {
                Button("Open Settings", action: openNotificationSettings)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Allow notifications for Cat-o-Base in Settings to get due-date reminders.")
            }
        }
    }
}

extension SettingsView {
    private func openNotificationSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            openURL(url)
        }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            openURL(url)
        }
        #endif
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewData.container)
}
