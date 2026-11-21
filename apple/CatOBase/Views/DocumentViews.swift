import PhotosUI
import QuickLook
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DocumentsSection: View {
    @Environment(\.modelContext) private var context
    let cat: Cat

    @State private var importing = false
    @State private var previewURL: URL?
    @State private var renaming: CatDocument?
    @State private var titleDraft = ""
    @State private var importError: String?
    @State private var showingScanner = false
    @State private var showingPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?

    private var documents: [CatDocument] {
        (cat.documents ?? []).sorted { $0.addedAt > $1.addedAt }
    }

    var body: some View {
        Section("Documents") {
            ForEach(documents) { document in
                Button {
                    preview(document)
                } label: {
                    DocumentRow(document: document)
                }
                .buttonStyle(.plain)
                .help("\(document.filename): click to preview. Right-click to rename or delete.")
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        context.delete(document)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        startRename(document)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
                .contextMenu {
                    Button("Open") { preview(document) }
                    Button("Rename") { startRename(document) }
                    Button("Delete", role: .destructive) { context.delete(document) }
                }
            }

            // Presentation modifiers live on this single row: modifiers on a
            // Section would be copied onto every row.
            Menu {
                #if os(iOS)
                if DocumentScanner.isAvailable {
                    Button {
                        showingScanner = true
                    } label: {
                        Label("Scan Document", systemImage: "doc.viewfinder")
                    }
                }
                #endif
                Button {
                    showingPhotoPicker = true
                } label: {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                }
                Button {
                    importing = true
                } label: {
                    Label("Choose File", systemImage: "folder")
                }
            } label: {
                Label("Add Document", systemImage: "plus")
            }
            .help("Scan a paper document, or add a photo or file, like lab results or certificates")
            .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                if let item { addPhotoDocument(item) }
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showingScanner) {
                DocumentScanner { pdf in
                    addScan(pdf)
                }
                .ignoresSafeArea()
            }
            #endif
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.pdf, .image, .plainText, .item],
                          allowsMultipleSelection: true,
                          onCompletion: handleImport)
            .quickLookPreview($previewURL)
            .alert("Rename Document", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("Title", text: $titleDraft)
                Button("Save") {
                    renaming?.title = titleDraft.trimmed
                    try? context.save()
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .alert("Couldn't add a document", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
    }

    /// A scanned PDF, named by date; the rename prompt opens so it can get a proper title.
    private func addScan(_ pdf: Data) {
        let day = Date.now.formatted(.iso8601.year().month().day())
        let document = CatDocument(title: "Scan \(Fmt.date(.now))", filename: "Scan \(day).pdf",
                                   typeIdentifier: UTType.pdf.identifier, data: pdf)
        context.insert(document)
        document.cat = cat
        try? context.save()
        // Wait for the scanner to finish closing before showing the prompt.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            startRename(document)
        }
    }

    private func addPhotoDocument(_ item: PhotosPickerItem) {
        Task {
            defer { photoItem = nil }
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                importError = "Couldn't read that photo."
                return
            }
            let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }) ?? .jpeg
            let ext = type.preferredFilenameExtension ?? "jpg"
            let day = Date.now.formatted(.iso8601.year().month().day())
            let document = CatDocument(title: "Photo \(Fmt.date(.now))", filename: "Photo \(day).\(ext)",
                                       typeIdentifier: type.identifier, data: data)
            context.insert(document)
            document.cat = cat
            try? context.save()
            startRename(document)
        }
    }

    private func startRename(_ document: CatDocument) {
        titleDraft = document.title
        renaming = document
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            var failures: [String] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
                        ?? UTType(filenameExtension: url.pathExtension)
                        ?? .data
                    let document = CatDocument(
                        title: url.deletingPathExtension().lastPathComponent,
                        filename: url.lastPathComponent,
                        typeIdentifier: type.identifier,
                        data: data
                    )
                    context.insert(document)
                    document.cat = cat
                } catch {
                    failures.append(url.lastPathComponent)
                }
            }
            try? context.save()
            if !failures.isEmpty {
                importError = "Couldn't read: " + failures.joined(separator: ", ")
            }
        }
    }

    /// QuickLook needs a file, so write a temporary copy with the original name.
    private func preview(_ document: CatDocument) {
        guard let data = document.data else { return }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("documents", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let name = document.filename.isEmpty ? "Document" : document.filename
        let url = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url)
            previewURL = url
        } catch {
            importError = "Couldn't open \(name)."
        }
    }
}

struct DocumentRow: View {
    let document: CatDocument

    private var type: UTType? { UTType(document.typeIdentifier) }

    private var systemImage: String {
        guard let type else { return "doc" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }

    private var detail: String {
        var parts = [Fmt.date(document.addedAt)]
        if document.byteCount > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(document.byteCount), countStyle: .file))
        }
        if let ext = type?.preferredFilenameExtension?.uppercased() {
            parts.append(ext)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title.isEmpty ? document.filename : document.title)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
