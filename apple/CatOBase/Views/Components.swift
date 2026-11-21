import SwiftUI

/// A round photo, or a cat silhouette when there's no image.
struct AvatarCircle: View {
    let image: CGImage?
    var size: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(Color.accentColor.opacity(0.15))
                Image(systemName: "cat.fill")
                    .font(.system(size: size * 0.42))
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
        AvatarCircle(image: cat.profilePhoto?.thumbnailImage, size: size)
    }
}

/// Small rounded label, e.g. "special needs".
struct Pill: View {
    let text: String
    var tint: Color = .secondary

    init(_ text: String, tint: Color = .secondary) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: Capsule())
    }
}

/// A toggle that reveals a date picker; the date is nil while off.
struct OptionalDatePicker: View {
    let title: String
    @Binding var date: Date?

    init(_ title: String, date: Binding<Date?>) {
        self.title = title
        self._date = date
    }

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { date != nil },
            set: { isOn in date = isOn ? (date ?? Date()) : nil }
        ))
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
    let title: String
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
