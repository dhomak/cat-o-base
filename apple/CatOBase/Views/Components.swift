import SwiftUI

/// A round photo, or a cat silhouette when there's no image.
struct AvatarCircle: View {
    let image: CGImage?
    var size: CGFloat
    var species: Species = .other

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(Color.accentColor.opacity(0.15))
                SpeciesGlyph(species: species, size: size * 0.42)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.quaternary, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

struct CatAvatar: View {
    let cat: Cat
    var size: CGFloat

    var body: some View {
        AvatarCircle(image: cat.profilePhoto?.thumbnailImage, size: size, species: cat.species)
    }
}

/// Small rounded label, e.g. "special needs".
struct Pill: View {
    let text: Text
    var tint: Color = .secondary

    /// A literal, looked up in the string catalog.
    init(_ key: LocalizedStringKey, tint: Color = .secondary) {
        self.text = Text(key)
        self.tint = tint
    }

    /// Text that's already translated or comes from the user.
    @_disfavoredOverload
    init<S: StringProtocol>(_ content: S, tint: Color = .secondary) {
        self.text = Text(content)
        self.tint = tint
    }

    var body: some View {
        text
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: Capsule())
    }
}

/// A toggle that reveals a date picker; the date is nil while off.
struct OptionalDatePicker: View {
    let title: Text
    @Binding var date: Date?

    init(_ title: LocalizedStringKey, date: Binding<Date?>) {
        self.title = Text(title)
        self._date = date
    }

    /// For a title that's already translated.
    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, date: Binding<Date?>) {
        self.title = Text(title)
        self._date = date
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { date != nil },
            set: { isOn in date = isOn ? (date ?? Date()) : nil }
        )) {
            title
        }
        if date != nil {
            DatePicker(
                "Date",
                selection: Binding(get: { date ?? Date() }, set: { date = $0 }),
                in: ...Date(),
                displayedComponents: .date
            )
        }
    }
}

/// A highlighted block of text for special needs and allergies.
struct CalloutRow: View {
    let title: LocalizedStringKey
    let text: String
    let systemImage: String
    var tint: Color = .orange

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

/// Shown over a cat's page while files are dragged onto it.
struct DropHighlight: View {
    let catName: String

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                Label("Drop photos or documents for \(catName)", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .padding(12)
                    .background(.regularMaterial, in: Capsule())
            }
            .padding(8)
            .allowsHitTesting(false)
    }
}

extension View {
    /// Mac lists default to tiny grey section titles and tight rows. Give them
    /// prominent headers and more room; iPhone and iPad keep the system style.
    @ViewBuilder
    func comfortableListOnMac() -> some View {
        #if os(macOS)
        self
            .listStyle(.inset)
            .environment(\.defaultMinListRowHeight, 36)
        #else
        self
        #endif
    }
}

/// A list section title: large and bold on the Mac, the standard style on iPhone/iPad.
struct SectionTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        #if os(macOS)
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.top, 14)
            .padding(.bottom, 4)
        #else
        Text(title)
        #endif
    }
}

extension Section where Parent == SectionTitle, Footer == EmptyView, Content: View {
    /// `Section(title: "Details") { … }` uses SectionTitle for the header.
    init(title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { SectionTitle(title) })
    }
}
