import PhotosUI
import SwiftData
import SwiftUI

// MARK: - Gallery section on the cat page

struct PhotosSection: View {
    @Environment(\.modelContext) private var context
    let cat: Cat
    /// Opens the viewer at this index of `cat.photosNewestFirst`.
    let onOpen: (Int) -> Void

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var importProgress: (done: Int, total: Int)?

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 160), spacing: 8)]

    var body: some View {
        Section("Photos") {
            let photos = cat.photosNewestFirst
            if !photos.isEmpty {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.element.persistentModelID) { index, photo in
                        Button {
                            onOpen(index)
                        } label: {
                            PhotoTile(photo: photo, isProfile: photo.uuid == cat.profilePhoto?.uuid)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            if let progress = importProgress {
                HStack {
                    ProgressView()
                    Text("Adding photo \(min(progress.done + 1, progress.total)) of \(progress.total)…")
                        .foregroundStyle(.secondary)
                }
            } else {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 30, matching: .images) {
                    Label("Add Photos", systemImage: "plus")
                }
                .onChange(of: pickerItems) { _, items in
                    importPhotos(items)
                }
            }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        importProgress = (0, items.count)
        Task {
            for (index, item) in items.enumerated() {
                importProgress = (index, items.count)
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let prepared = await Task.detached(priority: .userInitiated) {
                    ImageTools.prepare(data)
                }.value
                guard let prepared else { continue }
                let photo = CatPhoto.make(from: prepared)
                context.insert(photo)
                photo.cat = cat
                if cat.profilePhotoID == nil {
                    cat.profilePhotoID = photo.uuid
                }
            }
            try? context.save()
            importProgress = nil
            pickerItems = []
        }
    }
}

struct PhotoTile: View {
    let photo: CatPhoto
    let isProfile: Bool

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                CachedImageView(key: photo.cacheKey("grid"), data: photo.imageData, maxPixels: 400)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if isProfile {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Color.accentColor, in: Circle())
                        .padding(5)
                        .accessibilityLabel("Profile photo")
                }
            }
            .contentShape(Rectangle())
    }
}

// MARK: - Full-screen viewer

struct PhotoViewerStart: Identifiable {
    let id = UUID()
    let index: Int
}

struct PhotoViewer: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let cat: Cat
    /// Called with the photo to crop once the viewer has closed.
    let onSetProfile: (CatPhoto) -> Void

    @State private var index: Int
    @State private var editingCaption = false
    @State private var captionDraft = ""
    @State private var confirmingDelete = false

    init(cat: Cat, startIndex: Int, onSetProfile: @escaping (CatPhoto) -> Void) {
        self.cat = cat
        self.onSetProfile = onSetProfile
        _index = State(initialValue: startIndex)
    }

    private var photos: [CatPhoto] { cat.photosNewestFirst }

    private var current: CatPhoto? {
        photos.indices.contains(index) ? photos[index] : nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let photo = current {
                    CachedImageView(key: photo.cacheKey("full"), data: photo.imageData,
                                    maxPixels: ImageTools.fullMaxPixels, contentMode: .fit)
                        .id(photo.persistentModelID)
                        .transition(.opacity)
                        .gesture(swipe)
                    VStack {
                        Spacer()
                        caption(for: photo)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: index)
            .navigationTitle(photos.isEmpty ? "" : "\(index + 1) of \(photos.count)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
            .toolbar { toolbarContent }
            .alert("Caption", isPresented: $editingCaption) {
                TextField("Caption", text: $captionDraft)
                Button("Save") {
                    current?.caption = captionDraft.trimmed
                    try? context.save()
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete this photo?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Photo", role: .destructive, action: deleteCurrent)
            }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 560)
        #endif
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                step(-1)
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(index <= 0)
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button {
                step(1)
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(index >= photos.count - 1)
            .keyboardShortcut(.rightArrow, modifiers: [])

            if let photo = current {
                Menu {
                    Button {
                        let target = photo
                        dismiss()
                        onSetProfile(target)
                    } label: {
                        Label("Use as Profile Photo…", systemImage: "person.crop.circle")
                    }
                    Button {
                        captionDraft = photo.caption
                        editingCaption = true
                    } label: {
                        Label("Edit Caption", systemImage: "text.bubble")
                    }
                    if let image = ImageCache.shared.cached(photo.cacheKey("full")) {
                        let shareImage = Image(decorative: image, scale: 1)
                        ShareLink(item: shareImage, preview: SharePreview(cat.displayName, image: shareImage)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete Photo", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private func caption(for photo: CatPhoto) -> some View {
        let date = photo.takenOn.map { Fmt.date($0) }
        return Group {
            if !photo.caption.isEmpty || date != nil {
                VStack(spacing: 2) {
                    if !photo.caption.isEmpty {
                        Text(photo.caption).font(.body)
                    }
                    if let date {
                        Text(date).font(.caption).opacity(0.75)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.bottom, 24)
            }
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                if value.translation.width < -60 {
                    step(1)
                } else if value.translation.width > 60 {
                    step(-1)
                }
            }
    }

    private func step(_ delta: Int) {
        let next = index + delta
        if photos.indices.contains(next) { index = next }
    }

    private func deleteCurrent() {
        guard let photo = current else { return }
        if cat.profilePhotoID == photo.uuid {
            cat.profilePhotoID = nil
        }
        context.delete(photo)
        try? context.save()
        let remaining = photos.count
        if remaining == 0 {
            dismiss()
        } else {
            index = min(index, remaining - 1)
        }
    }
}
