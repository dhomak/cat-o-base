import QuickLook
import SwiftData
import SwiftUI

/// Renders the cat-sitter sheet as a PDF: one A4 page per cat, each with the contacts.
@MainActor
enum SitterSheetPDF {
    static let pageSize = CGSize(width: 595, height: 842) // A4 in points

    static func make(cats: [Cat], contacts: [Contact]) -> URL? {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("sitter-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let title = cats.count == 1 ? String(localized: "\(cats[0].displayName) care sheet")
                                     : String(localized: "Pet care sheet")
        let url = folder.appendingPathComponent("\(title).pdf")

        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let pdf = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return nil }

        let generated = Date()
        var pages: [AnyView] = []
        if cats.isEmpty {
            pages.append(AnyView(Text("No pets yet.").font(.title)
                .frame(width: pageSize.width, height: pageSize.height)))
        }
        for cat in cats {
            // A guest cat's page lists its owner's contacts.
            let pageContacts: [ContactDTO] = cat.isGuest && !cat.guestContacts.isEmpty
                ? cat.guestContacts
                : contacts.map(CatShareBuilder.contactDTO)
            pages.append(AnyView(SitterPage(cat: cat, contacts: pageContacts, generated: generated)))
        }

        for page in pages {
            let content = page
                .frame(width: pageSize.width, height: pageSize.height)
                .background(Color.white)
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(pageSize)
            pdf.beginPDFPage(nil)
            renderer.render { _, draw in
                draw(pdf)
            }
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return url
    }
}

/// One printable page. Fixed light colours so it prints the same in dark mode.
struct SitterPage: View {
    let cat: Cat
    let contacts: [ContactDTO]
    let generated: Date

    private let ink = Color.black
    private let muted = Color(white: 0.4)
    private let rule = Color(white: 0.85)

    private var activeTreatments: [Treatment] {
        (cat.treatments ?? [])
            .filter { treatment in
                guard treatment.active else { return false }
                if let end = treatment.endDate, end < Calendar.current.startOfDay(for: .now) { return false }
                return true
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var facts: String {
        var parts: [String] = [cat.species.label]
        if let age = Fmt.age(from: cat.birthday) { parts.append(cat.birthdayApprox ? String(localized: "about \(age)", comment: "Approximate age") : age) }
        if cat.sex != .unknown { parts.append(cat.sex.label.lowercased() + (cat.neutered ? ", " + String(localized: "neutered") : "")) }
        if !cat.markings.isEmpty { parts.append(cat.markings) }
        if let weight = cat.latestWeight { parts.append(Fmt.kg(weight.kg)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 18) {
                AvatarCircle(image: cat.profilePhoto?.thumbnailImage, size: 96, species: cat.species)
                VStack(alignment: .leading, spacing: 4) {
                    Text(cat.displayName)
                        .font(.system(size: 30, weight: .bold))
                    if !facts.isEmpty {
                        Text(facts).font(.system(size: 13)).foregroundStyle(muted)
                    }
                    if !cat.microchip.isEmpty {
                        Text("Microchip \(cat.microchip)")
                            .font(.system(size: 12).monospaced())
                            .foregroundStyle(muted)
                    }
                }
                Spacer()
            }

            Rectangle().fill(rule).frame(height: 1)

            if !cat.specialNeeds.isEmpty || !cat.allergies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !cat.specialNeeds.isEmpty { field("Special needs", cat.specialNeeds) }
                    if !cat.allergies.isEmpty { field("Allergies", cat.allergies) }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 1, green: 0.96, blue: 0.86), in: RoundedRectangle(cornerRadius: 8))
            }

            field("Food", foodText)

            if !activeTreatments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    label("Medication & treatments")
                    ForEach(activeTreatments, id: \.persistentModelID) { treatment in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("• \(treatment.name)" + (treatment.summary.isEmpty ? "" : " — \(treatment.summary)"))
                                .font(.system(size: 13))
                            if let due = treatment.nextDue {
                                Text("Next due \(Fmt.date(due))").font(.system(size: 11)).foregroundStyle(muted)
                                    .padding(.leading, 12)
                            }
                            if !treatment.notes.isEmpty {
                                Text(treatment.notes).font(.system(size: 11)).foregroundStyle(muted)
                                    .padding(.leading, 12)
                            }
                        }
                    }
                }
            }

            if !cat.notes.isEmpty { field("Good to know", cat.notes) }

            Spacer(minLength: 0)

            if !contacts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    label("Contacts")
                    ForEach(Array(contacts.enumerated()), id: \.offset) { _, contact in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(contact.role.isEmpty ? String(localized: "Contact") : contact.role)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(muted)
                                .frame(width: 110, alignment: .leading)
                            Text(contact.name).font(.system(size: 13, weight: .medium))
                            Text(contact.phone).font(.system(size: 13))
                            Spacer()
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(rule))
            }

            Text("Updated \(Fmt.date(generated)) · Pet-o-Base")
                .font(.system(size: 10))
                .foregroundStyle(muted)
        }
        .foregroundStyle(ink)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var foodText: String {
        let parts = [cat.foodBrand, cat.foodPortion, cat.foodSchedule].filter { !$0.isEmpty }
        var text = parts.isEmpty ? "—" : parts.joined(separator: ", ")
        if !cat.foodNotes.isEmpty { text += "\n" + cat.foodNotes }
        return text
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .textCase(.uppercase)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(muted)
    }

    private func field(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            label(title)
            Text(value).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension SitterSheetPDF {
    /// Builds the sheet for `cats` (or every cat that isn't archived) with all contacts.
    static func make(in context: ModelContext, cats: [Cat]? = nil) -> URL? {
        let contacts = (try? context.fetch(FetchDescriptor<Contact>(
            sortBy: [SortDescriptor(\.role), SortDescriptor(\.name)]
        ))) ?? []
        let chosen = cats ?? ((try? context.fetch(FetchDescriptor<Cat>(
            predicate: #Predicate { $0.archived == false },
            sortBy: [SortDescriptor(\.name)]
        ))) ?? [])
        return make(cats: chosen, contacts: contacts)
    }
}

#Preview {
    SitterPage(cat: PreviewData.murka, contacts: [], generated: .now)
        .frame(width: 595, height: 842)
        .modelContainer(PreviewData.container)
}
