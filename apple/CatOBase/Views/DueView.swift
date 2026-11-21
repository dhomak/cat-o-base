import SwiftUI

/// Placeholder until phase 2 adds vaccinations and treatments.
struct DueView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Coming in Phase 2",
                systemImage: "calendar.badge.clock",
                description: Text("Vaccinations and medications due across all your cats will appear here.")
            )
            .navigationTitle("Due")
        }
    }
}

#Preview {
    DueView()
}
