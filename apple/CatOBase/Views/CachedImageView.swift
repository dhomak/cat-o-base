import SwiftUI

/// Decodes image data off the main thread and keeps the result in ImageCache.
struct CachedImageView: View {
    let key: String
    let data: Data?
    let maxPixels: Int
    var contentMode: ContentMode = .fill

    @State private var image: CGImage?

    init(key: String, data: Data?, maxPixels: Int, contentMode: ContentMode = .fill) {
        self.key = key
        self.data = data
        self.maxPixels = maxPixels
        self.contentMode = contentMode
        _image = State(initialValue: ImageCache.shared.cached(key))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(.quaternary)
                ProgressView()
            }
        }
        .task(id: key) {
            if let hit = ImageCache.shared.cached(key) {
                image = hit
                return
            }
            let key = key
            let data = data
            let maxPixels = maxPixels
            image = await Task.detached(priority: .utility) {
                ImageCache.shared.image(for: key, data: data, maxPixels: maxPixels)
            }.value
        }
    }
}

extension View {
    /// Full-screen cover on iPhone/iPad, a sheet on the Mac.
    @ViewBuilder
    func coverOrSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(iOS)
        fullScreenCover(item: item, onDismiss: onDismiss, content: content)
        #else
        sheet(item: item, onDismiss: onDismiss, content: content)
        #endif
    }
}
