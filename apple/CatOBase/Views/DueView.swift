import SwiftData
import SwiftUI

/// Everything overdue or coming up, across all cats that aren't archived.
struct DueView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Cat> { $0.archived == false }, sort: \Cat.name)
    private var cats: [Cat]

    private var items: [DueItem] {
        cats.flatMap(\.dueItems).sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            // Always-present list with an overlay, so the navigationDestination stays registered.
            List {
                section("Overdue", items.filter { $0.status == .overdue })
                section("Next 2 weeks", items.filter { $0.status == .soon })
                section("Later", items.filter { $0.status == .later })
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Nothing Due",
                        systemImage: "checkmark.circle",
                        description: Text("Vaccinations and treatments with a next due date appear here.")
                    )
                }
            }
            .navigationTitle("Due")
            .navigationDestination(for: Cat.self) { cat in
                CatDetailView(cat: cat)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [DueItem]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    NavigationLink(value: item.cat) {
                        DueRow(item: item)
                    }
                    .help("Open \(item.cat.displayName). Swipe right or right-click to mark as given today.")
                    .swipeActions(edge: .leading) {
                        Button {
                            withAnimation { DueActions.markGiven(item, in: context) }
                        } label: {
                            Label("Given today", systemImage: "checkmark")
                        }
                        .tint(.green)
                    }
                    .contextMenu {
                        Button {
                            withAnimation { DueActions.markGiven(item, in: context) }
                        } label: {
                            Label("Given today", systemImage: "checkmark")
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    DueView()
        .modelContainer(PreviewData.container)
}
