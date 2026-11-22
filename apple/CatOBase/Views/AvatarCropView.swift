import SwiftData
import SwiftUI

/// Position and zoom a photo inside a circle to make the round profile picture.
/// Drag to move, pinch (or the slider) to zoom, "Find Pet" to auto-centre (cats and dogs).
struct AvatarCropView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let photo: CatPhoto

    @State private var image: CGImage?
    @State private var centerX: Double
    @State private var centerY: Double
    @State private var side: Double
    @State private var detecting = false
    @State private var saving = false
    @State private var noCatFound = false

    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1

    /// The circle's share of the canvas; the rest shows dimmed context.
    private let circleFraction: CGFloat = 0.86

    init(photo: CatPhoto) {
        self.photo = photo
        _centerX = State(initialValue: photo.cropCenterX)
        _centerY = State(initialValue: photo.cropCenterY)
        _side = State(initialValue: photo.cropSide)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let image {
                    GeometryReader { geometry in
                        let canvas = min(geometry.size.width, geometry.size.height)
                        cropCanvas(image: image, canvas: canvas)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .padding(.horizontal)

                    zoomSlider

                    HStack(spacing: 12) {
                        Button {
                            findCat(in: image)
                        } label: {
                            if detecting {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Find Pet", systemImage: "viewfinder")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(detecting || !(photo.cat?.species.supportsAutoCentring ?? true))
                        .help("Find the cat or dog in the photo and centre on it")

                        Button {
                            withAnimation { reset(image) }
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .help("Show the whole photo")
                    }

                    Text("Drag to move. Pinch or use the slider to zoom.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical)
            .navigationTitle("Profile Photo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(image == nil || saving)
                }
            }
            .alert("No pet found", isPresented: $noCatFound) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Automatic centring recognises cats and dogs, and couldn't find one here. Drag and zoom to position the photo yourself.")
            }
            .task { await load() }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 600)
        #endif
    }

    // MARK: Canvas

    private func cropCanvas(image: CGImage, canvas: CGFloat) -> some View {
        let diameter = canvas * circleFraction
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let crop = effectiveCrop(width: width, height: height, diameter: diameter)
        let scale = diameter / (CGFloat(crop.side) * min(width, height)) // points per pixel
        let shownWidth = width * scale
        let shownHeight = height * scale
        let offsetX = (0.5 - CGFloat(crop.x)) * shownWidth
        let offsetY = (0.5 - CGFloat(crop.y)) * shownHeight

        return ZStack {
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: shownWidth, height: shownHeight)
                .offset(x: offsetX, y: offsetY)

            Rectangle()
                .fill(Color.black.opacity(0.55))
                .mask {
                    Rectangle()
                        .overlay {
                            Circle()
                                .frame(width: diameter, height: diameter)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }
                .allowsHitTesting(false)

            Circle()
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                .frame(width: diameter, height: diameter)
                .allowsHitTesting(false)
        }
        .frame(width: canvas, height: canvas)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .gesture(
            dragGesture(width: width, height: height, diameter: diameter)
                .simultaneously(with: pinchGesture(width: width, height: height))
        )
        .accessibilityLabel("Photo crop area")
        .help("Drag to move. Pinch on the trackpad, or use the slider, to zoom.")
    }

    private var zoomSlider: some View {
        HStack {
            Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { 1 / side },
                    set: { zoom in
                        guard let image else { return }
                        side = AvatarCrop.clampSide(1 / zoom)
                        clampCenter(for: image)
                    }
                ),
                in: 1...(1 / AvatarCrop.minimumSide)
            )
            Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .help("Zoom")
    }

    // MARK: Gestures

    /// The crop including any drag or pinch in progress.
    private func effectiveCrop(width: CGFloat, height: CGFloat, diameter: CGFloat) -> (x: Double, y: Double, side: Double) {
        let liveSide = AvatarCrop.clampSide(side / Double(pinchScale))
        let scale = Double(diameter) / (liveSide * Double(min(width, height)))
        let x = centerX - Double(dragTranslation.width) / (Double(width) * scale)
        let y = centerY - Double(dragTranslation.height) / (Double(height) * scale)
        let clamped = AvatarCrop.clampCenter(x: x, y: y, side: liveSide, width: Double(width), height: Double(height))
        return (clamped.0, clamped.1, liveSide)
    }

    private func dragGesture(width: CGFloat, height: CGFloat, diameter: CGFloat) -> some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let scale = Double(diameter) / (side * Double(min(width, height)))
                let x = centerX - Double(value.translation.width) / (Double(width) * scale)
                let y = centerY - Double(value.translation.height) / (Double(height) * scale)
                let clamped = AvatarCrop.clampCenter(x: x, y: y, side: side, width: Double(width), height: Double(height))
                centerX = clamped.0
                centerY = clamped.1
            }
    }

    private func pinchGesture(width: CGFloat, height: CGFloat) -> some Gesture {
        MagnifyGesture()
            .updating($pinchScale) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                side = AvatarCrop.clampSide(side / Double(value.magnification))
                let clamped = AvatarCrop.clampCenter(x: centerX, y: centerY, side: side,
                                                     width: Double(width), height: Double(height))
                centerX = clamped.0
                centerY = clamped.1
            }
    }

    // MARK: Actions

    private func clampCenter(for image: CGImage) {
        let clamped = AvatarCrop.clampCenter(x: centerX, y: centerY, side: side,
                                             width: Double(image.width), height: Double(image.height))
        centerX = clamped.0
        centerY = clamped.1
    }

    private func reset(_ image: CGImage) {
        side = 1
        centerX = 0.5
        centerY = 0.5
        clampCenter(for: image)
    }

    private func load() async {
        let data = photo.imageData
        let loaded = await Task.detached(priority: .userInitiated) {
            data.flatMap { ImageTools.downsample($0, maxPixels: ImageTools.fullMaxPixels) }
        }.value
        image = loaded
        if let loaded { clampCenter(for: loaded) }
    }

    private func findCat(in image: CGImage) {
        detecting = true
        Task {
            let crop = await Task.detached(priority: .userInitiated) {
                CatDetector.avatarCrop(for: image)
            }.value
            detecting = false
            guard let crop else {
                noCatFound = true
                return
            }
            withAnimation(.easeInOut(duration: 0.35)) {
                side = crop.side
                centerX = crop.centerX
                centerY = crop.centerY
                clampCenter(for: image)
            }
        }
    }

    private func save() {
        guard let image else { return }
        saving = true
        let x = centerX
        let y = centerY
        let cropSide = side
        Task {
            let thumbnail = await Task.detached(priority: .userInitiated) {
                ImageTools.makeAvatar(from: image, centerX: x, centerY: y, side: cropSide)
            }.value
            photo.cropCenterX = x
            photo.cropCenterY = y
            photo.cropSide = cropSide
            if let thumbnail { photo.thumbnailData = thumbnail }
            photo.cat?.profilePhotoID = photo.uuid
            try? context.save()
            dismiss()
        }
    }
}
