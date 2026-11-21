import SwiftUI

enum AppTab: Hashable {
    case cats, due, contacts, settings
}

/// Tabs on iPhone; a sidebar on iPad and Mac.
struct RootView: View {
    @State private var tab: AppTab = .cats

    var body: some View {
        TabView(selection: $tab) {
            Tab("Cats", systemImage: "cat", value: AppTab.cats) {
                CatsView()
            }
            Tab("Due", systemImage: "calendar.badge.clock", value: AppTab.due) {
                DueView()
            }
            Tab("Contacts", systemImage: "phone", value: AppTab.contacts) {
                ContactsView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container)
}
