import SwiftUI

/// On launch, a faint copy of the app icon zooms up and fades away, revealing the app.
/// Plays once per launch (not for each new window), can be tapped through, and only
/// fades when Reduce Motion is on. The image is the LaunchIcon asset, which
/// tools/make-icons.sh refreshes along with the app icon.
struct LaunchZoom: ViewModifier {
    nonisolated(unsafe) private static var played = false

    /// Same size the icon has on the Home Screen, in points.
    static let iconSize: CGFloat = 120
    /// iOS rounds icons to about 22.4% of their width.
    static let cornerRadius: CGFloat = iconSize * 0.224

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
                        .clipShape(RoundedRectangle(cornerRadius: LaunchZoom.cornerRadius, style: .continuous))
                        .opacity(zoomed ? 0 : 0.2)
                        .scaleEffect(zoomed && !reduceMotion ? 6 : 1)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .task {
                    LaunchZoom.played = true
                    try? await Task.sleep(for: .milliseconds(150))
                    withAnimation(.easeIn(duration: 0.55)) {
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
