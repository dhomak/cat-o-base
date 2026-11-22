import SwiftUI

enum Species: String, CaseIterable, Identifiable {
    case cat, dog, rabbit, bird, rat, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cat: return String(localized: "Cat", comment: "Species")
        case .dog: return String(localized: "Dog", comment: "Species")
        case .rabbit: return String(localized: "Rabbit", comment: "Species")
        case .bird: return String(localized: "Bird", comment: "Species")
        case .rat: return String(localized: "Rat", comment: "Species")
        case .other: return String(localized: "Other species", defaultValue: "Other", comment: "Species")
        }
    }

    /// SF Symbol name, or nil when the icon is a custom asset (the rat).
    var systemImage: String? {
        switch self {
        case .cat: return "cat.fill"
        case .dog: return "dog.fill"
        case .rabbit: return "hare.fill"
        case .bird: return "bird.fill"
        case .rat: return nil
        case .other: return "pawprint.fill"
        }
    }

    /// Custom template image in the asset catalog.
    var assetImage: String? {
        self == .rat ? "species-rat" : nil
    }

    var emoji: String {
        switch self {
        case .cat: return "🐈"
        case .dog: return "🐕"
        case .rabbit: return "🐇"
        case .bird: return "🐦"
        case .rat: return "🐀"
        case .other: return "🐾"
        }
    }

    var breedHint: String {
        switch self {
        case .cat: return String(localized: "e.g. domestic shorthair")
        case .dog: return String(localized: "e.g. beagle")
        case .rabbit: return String(localized: "e.g. Holland Lop")
        case .bird: return String(localized: "e.g. budgie")
        case .rat: return String(localized: "e.g. fancy rat")
        case .other: return String(localized: "Breed or kind")
        }
    }

    /// Cats have their own word for it in Russian and Ukrainian ("день укотовления").
    var gotchaDayLabel: String {
        self == .cat ? String(localized: "Cat's gotcha day", defaultValue: "Gotcha day")
                     : String(localized: "Gotcha day")
    }

    /// Quick-fill vaccine names for the vaccination form; any name can be typed.
    var vaccineSuggestions: [String] {
        switch self {
        case .cat: return [String(localized: "Rabies"), "FVRCP (tricat)", "FeLV", String(localized: "Chlamydia"), "FIP"]
        case .dog: return [String(localized: "Rabies"), "DHPP", String(localized: "Leptospirosis"),
                           String(localized: "Bordetella"), String(localized: "Lyme")]
        case .rabbit: return ["RHDV1", "RHDV2", String(localized: "Myxomatosis")]
        case .bird: return [String(localized: "Polyomavirus")]
        case .rat: return []
        case .other: return [String(localized: "Rabies")]
        }
    }

    /// Apple's on-device animal recogniser only knows cats and dogs.
    var supportsAutoCentring: Bool {
        self == .cat || self == .dog
    }
}

extension Cat {
    var species: Species {
        get { Species(rawValue: speciesRaw) ?? .other }
        set { speciesRaw = newValue.rawValue }
    }
}

/// The species icon, sized by the surrounding font like an SF Symbol.
struct SpeciesIcon: View {
    let species: Species

    var body: some View {
        if let name = species.systemImage {
            Image(systemName: name)
        } else if let asset = species.assetImage {
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .accessibilityLabel(species.label)
        }
    }
}

/// Species icon scaled to fill a given box (avatar placeholders).
struct SpeciesGlyph: View {
    let species: Species
    let size: CGFloat

    var body: some View {
        if let name = species.systemImage {
            Image(systemName: name)
                .font(.system(size: size))
        } else if let asset = species.assetImage {
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size * 1.3, height: size * 1.3)
        }
    }
}
