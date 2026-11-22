import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct PendingImport {
    let file: BackupFile
    let source: BackupSource
}

struct SettingsView: View {
    @Environment(\.modelContext) private var context
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

    @State private var exportDocument: BackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingImport: PendingImport?
    @State private var showImportChoice = false
    @State private var busyMessage: String?
    @State private var resultMessage: String?
    @State private var importTask: Task<Void, Never>?

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
                displaySection
                remindersSection
                backupSection
                dataSection
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json,
                          defaultFilename: BackupExporter.defaultFilename) { result in
                switch result {
                case .success: resultMessage = "Backup saved."
                case .failure(let error): resultMessage = "Couldn't save the backup: \(error.localizedDescription)"
                }
                exportDocument = nil
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .zip, .catobaseCat]) { result in
                switch result {
                case .success(let url): readBackup(url)
                case .failure(let error): resultMessage = error.localizedDescription
                }
            }
            .confirmationDialog("Import backup?", isPresented: $showImportChoice,
                                titleVisibility: .visible, presenting: pendingImport) { pending in
                Button("Add to My Data") { performImport(pending, replace: false) }
                Button("Replace All My Data", role: .destructive) { performImport(pending, replace: true) }
                Button("Cancel", role: .cancel) { pendingImport = nil }
            } message: { pending in
                Text("\(pending.source.rawValue): \(pending.file.cats.count) pets, \(pending.file.contacts.count) contacts. Adding keeps everything you have, so importing the same backup twice makes duplicates. Replacing deletes your current data first.")
            }
            .alert("Backup", isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(resultMessage ?? "")
            }
            .overlay {
                if let busyMessage {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(busyMessage)
                                .multilineTextAlignment(.center)
                                .monospacedDigit()
                            if importTask != nil {
                                Button("Cancel", role: .cancel) { importTask?.cancel() }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 300)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
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
    // MARK: Sections

    private var displaySection: some View {
        Section("Display") {
            Picker("Sort pets by", selection: $sort) {
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
    }

    private var remindersSection: some View {
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
                .help("Sends a notification in 5 seconds to check reminders work")
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Notifications for vaccinations and treatments on their due date. They're scheduled on this device, so they work offline.")
        }
    }

    private var backupSection: some View {
        Section {
            Button(action: exportBackup) {
                Label("Export Backup…", systemImage: "square.and.arrow.up")
            }
            .help("Save everything, including photos and documents, to one file")
            Button {
                importing = true
            } label: {
                Label("Import…", systemImage: "square.and.arrow.down")
            }
            .help("Load a backup from this app or the Cat-o-Base web app")
        } header: {
            Text("Backup")
        } footer: {
            Text("A backup is one file with every pet, record, photo and document. Import takes backups from this app and from the Cat-o-Base web app (its Full backup .zip, or the data-only .json).")
        }
    }

    @ViewBuilder
    private var dataSection: some View {
        Section("Your data") {
            LabeledContent("Pets", value: "\(cats.count)")
            LabeledContent("Photos", value: "\(photos.count)")
            LabeledContent("Contacts", value: "\(contacts.count)")
            LabeledContent("Stored", value: "On this device")
        }
        Section("Coming soon") {
            Label("iCloud sync", systemImage: "icloud")
        }
        Section {
            LabeledContent("Version", value: version)
            Link("Cat-o-Base on GitHub", destination: URL(string: "https://github.com/dhomak/cat-o-base")!)
        }
    }

    private func exportBackup() {
        busyMessage = "Preparing backup…"
        Task {
            let cats = (try? context.fetch(FetchDescriptor<Cat>(sortBy: [SortDescriptor(\.name)]))) ?? []
            let contacts = (try? context.fetch(FetchDescriptor<Contact>())) ?? []
            let file = BackupExporter.makeBackup(cats: cats, contacts: contacts)
            let data = await Task.detached(priority: .userInitiated) {
                try? BackupFile.encoder().encode(file)
            }.value
            busyMessage = nil
            if let data {
                exportDocument = BackupDocument(data: data)
                exporting = true
            } else {
                resultMessage = "Couldn't create the backup."
            }
        }
    }

    private func readBackup(_ url: URL) {
        busyMessage = "Reading backup…"
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Result { try BackupReader.read(url) }
            }.value
            busyMessage = nil
            switch outcome {
            case .success(let read) where read.1 == .catShare:
                if !read.0.cats.isEmpty {
                    GuestInbox.shared.pending = ReceivedShare(file: read.0)
                }
            case .success(let read):
                pendingImport = PendingImport(file: read.0, source: read.1)
                showImportChoice = true
            case .failure(let error):
                resultMessage = error.localizedDescription
            }
        }
    }

    private func performImport(_ pending: PendingImport, replace: Bool) {
        busyMessage = "Starting import…"
        importTask = Task {
            do {
                let summary = try await BackupImporter.run(pending.file, into: context, replace: replace) { message in
                    busyMessage = message
                }
                resultMessage = "Imported \(summary.text)."
            } catch is CancellationError {
                try? context.save()
                resultMessage = "Import cancelled. Pets that finished importing were kept."
            } catch {
                BackupImporter.log.error("Import failed: \(error.localizedDescription, privacy: .public)")
                resultMessage = "Import failed: \(error.localizedDescription)"
            }
            busyMessage = nil
            pendingImport = nil
            importTask = nil
        }
    }

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
