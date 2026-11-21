import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case cats, due, contacts, settings
}

/// Tabs on iPhone; a sidebar on iPad and Mac.
struct RootView: View {
    @State private var tab: AppTab = .cats
    @Query(filter: #Predicate<Cat> { $0.archived == false }) private var activeCats: [Cat]
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(PrefKey.remindersEnabled) private var remindersEnabled = false
    @AppStorage(PrefKey.reminderMinutes) private var reminderMinutes = PrefDefault.reminderMinutes
    @AppStorage(PrefKey.remindDayBefore) private var remindDayBefore = true
    @AppStorage(PrefKey.badgeOverdue) private var badgeOverdue = true

    private var dueItems: [DueItem] {
        activeCats.flatMap(\.dueItems)
    }

    private var overdueCount: Int {
        dueItems.filter { $0.status == .overdue }.count
    }

    private var reminderSettings: ReminderSettings {
        ReminderSettings(enabled: remindersEnabled, minutes: reminderMinutes,
                         dayBefore: remindDayBefore, badge: badgeOverdue)
    }

    /// Changes whenever anything that affects reminders changes: due dates, cat
    /// names, settings, or the calendar day (so the badge stays right).
    private var reminderSignature: String {
        let items = dueItems
            .map { "\($0.cat.displayName)|\($0.title)|\($0.date.timeIntervalSince1970)" }
            .joined(separator: ";")
        let settings = "\(remindersEnabled)|\(reminderMinutes)|\(remindDayBefore)|\(badgeOverdue)"
        let day = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        return "\(settings)#\(day)#\(items)"
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Cats", systemImage: "cat", value: AppTab.cats) {
                CatsView()
            }
            Tab("Due", systemImage: "calendar.badge.clock", value: AppTab.due) {
                DueView()
            }
            .badge(overdueCount)
            Tab("Contacts", systemImage: "phone", value: AppTab.contacts) {
                ContactsView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .task(id: reminderSignature) {
            // Short pause so a burst of edits reschedules once.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            let settings = reminderSettings
            let plans = ReminderScheduler.plans(for: dueItems, settings: settings)
            await ReminderScheduler.apply(plans, overdueCount: overdueCount, settings: settings)
        }
        .onChange(of: NotificationRouter.shared.pendingCatID) { _, id in
            if id != nil { tab = .cats }
        }
        // A .catobase file opened from Messages, Telegram, Mail, Files or Finder.
        .onOpenURL { url in
            GuestInbox.shared.receive(url)
        }
        .sheet(item: Binding(
            get: { GuestInbox.shared.pending },
            set: { GuestInbox.shared.pending = $0 }
        )) { share in
            GuestReceiveView(share: share)
        }
        .alert("Couldn't open the file", isPresented: Binding(
            get: { GuestInbox.shared.error != nil },
            set: { if !$0 { GuestInbox.shared.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(GuestInbox.shared.error ?? "")
        }
        .onChange(of: scenePhase) { _, _ in
            // Re-evaluated on return to the app so a new day refreshes reminders.
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container)
}
