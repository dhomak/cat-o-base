import SwiftUI

/// On launch, a faint copy of the app icon zooms up and fades away, revealing the app.
/// The launch screen (project.yml, UILaunchScreen) shows the same LaunchIcon image in
/// the same place, so the icon is there from the moment the app is tapped and the zoom
/// picks up seamlessly. LaunchIcon is already faint and rounded; tools/make-icons.sh
/// remakes it with the app icon. Plays once per launch (not for each new window),
/// can be tapped through, and only fades when Reduce Motion is on.
struct LaunchZoom: ViewModifier {
    nonisolated(unsafe) private static var played = false

    /// Same size as on the launch screen, in points.
    static let iconSize: CGFloat = 120

    @State private var visible = !LaunchZoom.played
    @State private var zoomed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if visible {
                ZStack {
                    LaunchZoom.background
                        .opacity(zoomed ? 0 : 1)
                    Image("LaunchIcon")
                        .resizable()
                        .frame(width: LaunchZoom.iconSize, height: LaunchZoom.iconSize)
                        .opacity(zoomed ? 0 : 1)
                        .scaleEffect(zoomed && !reduceMotion ? 6 : 1)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .task {
                    LaunchZoom.played = true
                    withAnimation(.easeIn(duration: 0.5)) {
                        zoomed = true
                    } completion: {
                        visible = false
                    }
                }
            }
        }
    }

    private static var background: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}

extension View {
    /// The faint app-icon zoom shown when the app starts.
    func launchZoom() -> some View {
        modifier(LaunchZoom())
    }
}
