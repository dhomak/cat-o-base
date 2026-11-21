import QuickLook
import SwiftData
import SwiftUI

struct CatsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Cat.name) private var cats: [Cat]
    @State private var path: [Cat] = []
    @State private var sitterSheetURL: URL?
    @State private var showingNewCat = false
    @State private var showingNewGuest = false
    @State private var showArchived = false
    @AppStorage(PrefKey.catSort) private var sort: CatSort = .name

    private var visibleCats: [Cat] {
        sort.sorted(cats.filter { $0.archived == showArchived })
    }

    private var myCats: [Cat] { visibleCats.filter { !$0.isGuest } }
    private var guestCats: [Cat] { visibleCats.filter(\.isGuest) }

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16)]

    var body: some View {
        NavigationStack(path: $path) {
            // The scroll view is always present (the empty state is an overlay) so the
            // navigationDestination below stays registered. Swapping the root view in an
            // if/else can make SwiftUI lose it, and then taps on cats do nothing.
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !myCats.isEmpty {
                        if !guestCats.isEmpty {
                            sectionHeader("My Cats")
                        }
                        grid(myCats)
                    }
                    if !guestCats.isEmpty {
                        sectionHeader("Guest Cats")
                            .padding(.top, myCats.isEmpty ? 0 : 12)
                            .help("Cats other people shared with you")
                        grid(guestCats)
                    }
                }
                .padding()
            }
            .overlay {
                if visibleCats.isEmpty {
                    emptyState
                }
            }
            .navigationTitle(showArchived ? "Archived" : "Cats")
            .navigationDestination(for: Cat.self) { cat in
                CatDetailView(cat: cat)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewCat = true
                    } label: {
                        Label("Add Cat", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .help("Add a cat (⌘N)")
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        showingNewGuest = true
                    } label: {
                        Label("New Guest Cat", systemImage: "person.2")
                    }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .help("Add a cat you're looking after for someone (⇧⌘N)")
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Picker("Sort by", selection: $sort) {
                            ForEach(CatSort.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    } label: {
                        Label("Sort by", systemImage: "arrow.up.arrow.down")
                    }
                    .help("Sort cats by name or age")
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        sitterSheetURL = SitterSheetPDF.make(in: context)
                    } label: {
                        Label("Sitter Sheet", systemImage: "doc.text.image")
                    }
                    .help("Make a printable care sheet for all cats")
                }
                ToolbarItem(placement: .secondaryAction) {
                    Toggle(isOn: $showArchived) {
                        Label("Show Archived", systemImage: "archivebox")
                    }
                    .help(showArchived ? "Show current cats" : "Show archived cats")
                }
            }
            .sheet(isPresented: $showingNewCat) {
                CatEditView(cat: nil)
            }
            .sheet(isPresented: $showingNewGuest) {
                CatEditView(cat: nil, startAsGuest: true)
            }
        }
        .quickLookPreview($sitterSheetURL)
        .onAppear { openPendingCat() }
        .onChange(of: NotificationRouter.shared.pendingCatID) { _, _ in
            openPendingCat()
        }
    }

    /// Opens the cat from a tapped reminder.
    private func openPendingCat() {
        guard let id = NotificationRouter.shared.pendingCatID else { return }
        NotificationRouter.shared.pendingCatID = nil
        if let cat = context.model(for: id) as? Cat {
            showArchived = cat.archived
            path = [cat]
        }
    }

    private func grid(_ cats: [Cat]) -> some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(cats) { cat in
                NavigationLink(value: cat) {
                    CatCard(cat: cat)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var emptyState: some View {
        if showArchived {
            ContentUnavailableView(
                "No Archived Cats",
                systemImage: "archivebox",
                description: Text("Cats you archive appear here, with all their records kept.")
            )
        } else {
            ContentUnavailableView {
                Label("No Cats Yet", systemImage: "cat")
            } description: {
                Text("Add your first cat to start keeping records.")
            } actions: {
                Button("Add a Cat") { showingNewCat = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct CatCard: View {
    let cat: Cat
    @AppStorage(PrefKey.weightUnit) private var unit: WeightUnit = .kg

    private var status: DueStatus? { cat.archived ? nil : cat.worstDueStatus }

    /// "Rabies: 5 days overdue · Bravecto: in 6 days"
    private var tooltip: String {
        let urgent = cat.dueItems.filter { $0.status != .later }.prefix(3)
        guard !urgent.isEmpty else { return "Open \(cat.displayName)" }
        return urgent.map { "\($0.title): \(Fmt.relativeDue($0.date))" }.joined(separator: " · ")
    }

    private var subtitle: String {
        var parts: [String] = []
        if let age = Fmt.age(from: cat.birthday) {
            parts.append(cat.birthdayApprox ? "≈\(age)" : age)
        }
        if cat.sex != .unknown { parts.append(cat.sex.label.lowercased()) }
        if let weight = cat.latestWeight { parts.append(unit.format(kilograms: weight.kg)) }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 10) {
            CatAvatar(cat: cat, size: 112)
            VStack(spacing: 2) {
                Text(cat.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 4) {
                switch status {
                case .some(.overdue): Pill("overdue", tint: .red)
                case .some(.soon): Pill("due soon", tint: .orange)
                default: EmptyView()
                }
                if cat.isGuest {
                    Pill(cat.guestFrom.isEmpty ? "guest" : "from \(cat.guestFrom)", tint: .teal)
                }
                if !cat.specialNeeds.trimmed.isEmpty { Pill("special needs", tint: .purple) }
                if !cat.allergies.trimmed.isEmpty { Pill("allergies", tint: .purple) }
            }
            .frame(minHeight: 18)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            if let status, !cat.archived {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(status.color, lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .help(tooltip)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    CatsView()
        .modelContainer(PreviewData.container)
}
