import CoreTransferable
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Adds photos and documents to a cat from raw data: used by drag and drop and
/// Continuity Camera.
@MainActor
enum CatMedia {
    struct Incoming: Sendable {
        let data: Data
        let filename: String
        let type: UTType
    }

    /// Images become photos (resized, cat-detected); everything else becomes a document.
    /// Returns how many photos and documents were added.
    @discardableResult
    static func add(_ items: [Incoming], to cat: Cat, in context: ModelContext) async -> (photos: Int, documents: Int) {
        var photos = 0
        var documents = 0
        for item in items {
            if item.type.conforms(to: .image) {
                let data = item.data
                let prepared = await Task.detached(priority: .userInitiated) {
                    ImageTools.prepare(data)
                }.value
                if let prepared {
                    let photo = CatPhoto.make(from: prepared)
                    context.insert(photo)
                    photo.cat = cat
                    if cat.profilePhotoID == nil { cat.profilePhotoID = photo.uuid }
                    photos += 1
                    continue
                }
                // Not decodable as an image: keep it as a document instead.
            }
            let title = (item.filename as NSString).deletingPathExtension
            let document = CatDocument(title: title.isEmpty ? String(localized: "Document") : title, filename: item.filename,
                                       typeIdentifier: item.type.identifier, data: item.data)
            context.insert(document)
            document.cat = cat
            documents += 1
        }
        try? context.save()
        return (photos, documents)
    }

    // MARK: Drag and drop

    static let dropTypes: [UTType] = [.fileURL, .image, .pdf]

    /// Reads dropped items (Finder files, Photos images, PDFs) and adds them.
    static func handleDrop(_ providers: [NSItemProvider], cat: Cat, context: ModelContext) {
        Task {
            var items: [Incoming] = []
            for provider in providers {
                if let item = await load(provider) { items.append(item) }
            }
            if !items.isEmpty {
                await add(items, to: cat, in: context)
            }
        }
    }

    private static func load(_ provider: NSItemProvider) async -> Incoming? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return continuation.resume(returning: nil) }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    guard let data = try? Data(contentsOf: url) else { return continuation.resume(returning: nil) }
                    let type = UTType(filenameExtension: url.pathExtension) ?? .data
                    continuation.resume(returning: Incoming(data: data, filename: url.lastPathComponent, type: type))
                }
            }
        }
        for type in [UTType.pdf, UTType.image] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            let suggested = provider.suggestedName ?? (type == .pdf ? String(localized: "Document") : String(localized: "Photo"))
            return await withCheckedContinuation { continuation in
                _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                    guard let data else { return continuation.resume(returning: nil) }
                    let ext = type == .pdf ? "pdf" : "jpg"
                    continuation.resume(returning: Incoming(data: data, filename: "\(suggested).\(ext)", type: type))
                }
            }
        }
        return nil
    }
}

/// A photo or PDF arriving from Continuity Camera ("Import from iPhone" on the Mac).
struct ContinuityImport: Transferable {
    let data: Data
    let type: UTType

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .pdf) { ContinuityImport(data: $0, type: .pdf) }
        DataRepresentation(importedContentType: .image) { ContinuityImport(data: $0, type: .image) }
    }

    var incoming: CatMedia.Incoming {
        let day = Date.now.formatted(.iso8601.year().month().day())
        let name = type == .pdf ? String(localized: "Scan \(day)") + ".pdf" : String(localized: "Photo \(day)") + ".jpg"
        return CatMedia.Incoming(data: data, filename: name, type: type)
    }
}
