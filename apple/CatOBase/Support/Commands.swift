import SwiftData
import SwiftUI

// MARK: - What the menu bar can act on

/// Actions for the cat shown in the focused window. Published by CatDetailView.
struct CatActions {
    let name: String
    let id: PersistentIdentifier
    let edit: () -> Void
    let logWeight: () -> Void
    let addVaccination: () -> Void
    let addTreatment: () -> Void
    let share: () -> Void
    let sitterSheet: () -> Void
}

/// App-level actions available from any window. Published by RootView.
struct AppActions {
    let newCat: () -> Void
    let newGuestCat: () -> Void
}

extension FocusedValues {
    @Entry var catActions: CatActions?
    @Entry var appActions: AppActions?
}

// MARK: - Menus

struct CatOBaseCommands: Commands {
    @FocusedValue(\.catActions) private var cat
    @FocusedValue(\.appActions) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // File menu: "New Cat" takes ⌘N; a new window moves to ⌥⌘N.
        CommandGroup(replacing: .newItem) {
            Button("New Cat") { app?.newCat() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(app == nil)
            Button("New Guest Cat") { app?.newGuestCat() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(app == nil)
            Divider()
            Button("New Window") { openWindow(id: WindowID.main) }
                .keyboardShortcut("n", modifiers: [.command, .option])
        }

        CommandMenu("Cat") {
            Button(cat.map { "Edit \($0.name)" } ?? "Edit Cat") { cat?.edit() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(cat == nil)
            Divider()
            Button("Log Weight…") { cat?.logWeight() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(cat == nil)
            Button("Add Vaccination…") { cat?.addVaccination() }
                .keyboardShortcut("v", modifiers: [.command, .option])
                .disabled(cat == nil)
            Button("Add Medication or Treatment…") { cat?.addTreatment() }
                .keyboardShortcut("m", modifiers: [.command, .option])
                .disabled(cat == nil)
            Divider()
            Button("Share…") { cat?.share() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(cat == nil)
            Button("Sitter Sheet") { cat?.sitterSheet() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(cat == nil)
            Button("Open in New Window") {
                if let id = cat?.id { openWindow(id: WindowID.cat, value: id) }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(cat == nil)
        }
    }
}

enum WindowID {
    static let main = "main"
    static let cat = "cat"
}

// MARK: - A cat in its own window

struct CatWindowView: View {
    @Environment(\.modelContext) private var context
    let id: PersistentIdentifier

    var body: some View {
        NavigationStack {
            if let cat = context.model(for: id) as? Cat, !cat.isDeleted {
                CatDetailView(cat: cat)
            } else {
                ContentUnavailableView("Cat Not Found", systemImage: "cat",
                                       description: Text("It may have been deleted."))
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }
}
