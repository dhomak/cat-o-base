import SwiftData
import SwiftUI

struct CatsView: View {
    @Query(sort: \Cat.name) private var cats: [Cat]
    @State private var showingNewCat = false
    @State private var showArchived = false
    @AppStorage(PrefKey.catSort) private var sort: CatSort = .name

    private var visibleCats: [Cat] {
        sort.sorted(cats.filter { $0.archived == showArchived })
    }

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if visibleCats.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(visibleCats) { cat in
                                NavigationLink(value: cat) {
                                    CatCard(cat: cat)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
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
                }
                ToolbarItem(placement: .secondaryAction) {
                    Toggle(isOn: $showArchived) {
                        Label("Show Archived", systemImage: "archivebox")
                    }
                }
            }
            .sheet(isPresented: $showingNewCat) {
                CatEditView(cat: nil)
            }
        }
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
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    CatsView()
        .modelContainer(PreviewData.container)
}
