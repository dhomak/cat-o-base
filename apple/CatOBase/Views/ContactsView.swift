import SwiftData
import SwiftUI

struct ContactsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Contact.role), SortDescriptor(\Contact.name)])
    private var contacts: [Contact]
    @State private var creating = false
    @State private var editing: Contact?

    var body: some View {
        NavigationStack {
            Group {
                if contacts.isEmpty {
                    ContentUnavailableView {
                        Label("No Contacts", systemImage: "phone")
                    } description: {
                        Text("Add your vet, the nearest 24/7 emergency clinic, insurance and a backup sitter.")
                    } actions: {
                        Button("Add Contact") { creating = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(contacts) { contact in
                            ContactRow(contact: contact)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = contact }
                                .help("Click to edit. Right-click to delete.")
                                .contextMenu {
                                    Button("Edit") { editing = contact }
                                    Button("Delete", role: .destructive) { context.delete(contact) }
                                }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(contacts[index]) }
                        }
                    }
                }
            }
            .navigationTitle("Contacts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        creating = true
                    } label: {
                        Label("Add Contact", systemImage: "plus")
                    }
                    .help("Add a vet, clinic, insurer or sitter")
                }
            }
            .sheet(isPresented: $creating) {
                ContactEditView(contact: nil)
            }
            .sheet(item: $editing) { contact in
                ContactEditView(contact: contact)
            }
        }
    }
}

struct ContactRow: View {
    let contact: Contact

    private var phoneURL: URL? {
        let allowed = Set("+0123456789")
        let digits = contact.phone.filter { allowed.contains($0) }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !contact.role.isEmpty {
                Text(contact.role.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(contact.name).font(.headline)
            if let phoneURL {
                Link(contact.phone, destination: phoneURL)
            }
            if !contact.address.isEmpty {
                Text(contact.address).font(.subheadline).foregroundStyle(.secondary)
            }
            if !contact.notes.isEmpty {
                Text(contact.notes).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ContactEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let contact: Contact?
    @State private var role: String
    @State private var name: String
    @State private var phone: String
    @State private var address: String
    @State private var notes: String

    private static let roleSuggestions = ["Vet", "Emergency vet", "Insurance", "Backup sitter", "Neighbour", "Owner"]

    init(contact: Contact?) {
        self.contact = contact
        _role = State(initialValue: contact?.role ?? "")
        _name = State(initialValue: contact?.name ?? "")
        _phone = State(initialValue: contact?.phone ?? "")
        _address = State(initialValue: contact?.address ?? "")
        _notes = State(initialValue: contact?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Role", text: $role, prompt: Text("e.g. Vet"))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Self.roleSuggestions, id: \.self) { suggestion in
                                Button(suggestion) { role = suggestion }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                }
                Section {
                    TextField("Phone", text: $phone)
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        #endif
                    TextField("Address", text: $address, axis: .vertical)
                    TextField("Notes", text: $notes, prompt: Text("Policy number, opening hours…"), axis: .vertical)
                }
                if let contact {
                    Section {
                        Button("Delete Contact", role: .destructive) {
                            context.delete(contact)
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(contact == nil ? "New Contact" : "Edit Contact")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmed.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 380)
        #endif
    }

    private func save() {
        let target: Contact
        if let contact {
            target = contact
        } else {
            target = Contact()
            context.insert(target)
        }
        target.name = name.trimmed
        target.role = role.trimmed
        target.phone = phone.trimmed
        target.address = address.trimmed
        target.notes = notes.trimmed
        try? context.save()
        dismiss()
    }
}

#Preview {
    ContactsView()
        .modelContainer(PreviewData.container)
}
