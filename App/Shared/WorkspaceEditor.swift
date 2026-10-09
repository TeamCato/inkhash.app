import InkhashCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Creates a workspace (`workspace` nil) or edits one: name, symbol or picture, and where it syncs.
struct WorkspaceEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var workspace: Workspace?

    @State private var name = ""
    @State private var symbol = "tray"
    /// A newly chosen picture, already normalized. Only counts when `imageChanged`.
    @State private var image: Data?
    @State private var imageChanged = false
    @State private var imageError = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showsPhotos = false
    @State private var showsFiles = false
    @State private var serverChoice: UUID?
    @State private var remoteChoice = WorkspaceEditor.newRemote
    @State private var remotes: [RemoteWorkspace] = []
    @State private var loadingRemotes = false
    @State private var busy = false
    @State private var confirmRemoval = false
    @State private var loaded = false

    private static let newRemote = "+new"
    static let symbols = ["house", "briefcase", "tray", "book", "lightbulb", "graduationcap", "heart", "leaf", "hammer", "paintpalette", "airplane", "cart"]

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name, prompt: Text("z. B. Arbeit"))
                    .labelsHidden()
                    .autocorrectionDisabled()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(Self.symbols, id: \.self) { item in
                        let chosen = preview == nil && symbol == item
                        Button {
                            symbol = item
                            if preview != nil {
                                image = nil
                                imageChanged = true
                            }
                        } label: {
                            Image(systemName: item)
                                .font(.system(size: 15))
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(chosen ? Ink.accent.opacity(0.16) : Color.clear)
                                )
                                .foregroundStyle(chosen ? Ink.accent : Ink.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
                pictureRow
            } header: {
                Text("Name")
            } footer: {
                if !imageError.isEmpty { Text(imageError) }
            }
            Section {
                Picker("Abgleich", selection: $serverChoice) {
                    Text("Nur dieses Gerät").tag(UUID?.none)
                    ForEach(signedInServers) { server in
                        Text("\(ServerAddress.host(server.url)) · \(server.accountName)").tag(UUID?.some(server.id))
                    }
                }
                if serverChoice != nil {
                    if loadingRemotes {
                        ProgressView().controlSize(.small)
                    } else {
                        Picker("Workspace auf dem Server", selection: $remoteChoice) {
                            Text("Neu anlegen").tag(Self.newRemote)
                            ForEach(remotes) { remote in
                                Text(remote.name).tag(remote.id)
                                    .disabled(isTaken(remote))
                            }
                        }
                    }
                }
            } header: {
                Text("Abgleich")
            } footer: {
                Text(syncFooter)
            }
            if let workspace, model.registry.workspaces.count > 1 {
                Section {
                    Button("Vom Gerät entfernen", role: .destructive) { confirmRemoval = true }
                    .confirmationDialog("Workspace vom Gerät entfernen?", isPresented: $confirmRemoval, titleVisibility: .visible) {
                        Button("Entfernen", role: .destructive) {
                            model.removeWorkspace(workspace.id)
                            dismiss()
                        }
                        Button("Abbrechen", role: .cancel) {}
                    }
                } footer: {
                    Text(workspace.link == nil
                        ? "Die Notizen dieses Workspace liegen nur hier und wären danach weg."
                        : "Die Notizen verschwinden von diesem Gerät. Auf dem Server bleiben sie.")
                }
            }
            if !model.status.isEmpty, model.status != StatusLine.localOnly, model.status != "Abgeglichen." {
                Text(model.status)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.muted)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(workspace == nil ? "Neuer Workspace" : workspace?.name ?? "")
        .toolbar {
            if workspace == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(workspace == nil ? "Anlegen" : "Sichern") { save() }
                    .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear(perform: load)
        .onChange(of: serverChoice) { _, _ in Task { await loadRemotes() } }
        .photosPicker(isPresented: $showsPhotos, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await adopt(data)
                } else {
                    imageError = "Das Foto ließ sich nicht laden."
                }
                photoItem = nil
            }
        }
        .fileImporter(isPresented: $showsFiles, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                imageError = "Die Datei ließ sich nicht öffnen."
                return
            }
            Task { await adopt(data) }
        }
    }

    /// The picture the workspace will show: a newly chosen one, or the one it has.
    private var preview: PlatformImage? {
        if imageChanged { return image.flatMap(PlatformImage.init(data:)) }
        return workspace.flatMap { model.registry.image(of: $0) }
    }

    private var pictureRow: some View {
        HStack(spacing: 12) {
            if let preview {
                WorkspacePicture(image: preview, size: 34)
                    .overlay(
                        RoundedRectangle(cornerRadius: 34 * 0.25, style: .continuous)
                            .strokeBorder(Ink.accent, lineWidth: 2)
                    )
                    .accessibilityLabel("Eigenes Bild")
            }
            Menu(preview == nil ? "Eigenes Bild …" : "Anderes Bild …") {
                Button("Aus Fotos", systemImage: "photo.on.rectangle") { showsPhotos = true }
                Button("Aus Dateien", systemImage: "folder") { showsFiles = true }
            }
            .fixedSize()
            if preview != nil {
                Spacer()
                Button("Entfernen", role: .destructive) {
                    image = nil
                    imageChanged = true
                }
            }
        }
    }

    private func adopt(_ data: Data) async {
        do {
            let png = try await Task.detached { try WorkspaceImage.normalize(data) }.value
            image = png
            imageChanged = true
            imageError = ""
        } catch {
            imageError = "Das Bild ließ sich nicht lesen."
        }
    }

    private var signedInServers: [ServerEntry] {
        model.registry.servers.filter { model.sessions.isSignedIn($0.id) }
    }

    private var syncFooter: String {
        if model.registry.servers.isEmpty {
            return "Noch kein Server verbunden. Der Workspace bleibt auf diesem Gerät."
        }
        guard serverChoice != nil else { return "Notizen bleiben auf diesem Gerät." }
        if let workspace, let link = workspace.link, link.server == serverChoice, link.remote == remoteChoice {
            return "Gleicht mit diesem Workspace ab."
        }
        return workspace == nil
            ? "Die Notizen gleichen mit diesem Workspace auf dem Server ab."
            : "Beim Sichern wandern alle Notizen dieses Workspace dorthin. Was dort schon liegt, kommt dazu."
    }

    /// A server workspace another local workspace already syncs with. Two would mirror each other.
    private func isTaken(_ remote: RemoteWorkspace) -> Bool {
        model.registry.workspaces.contains { other in
            other.id != workspace?.id && other.link?.server == serverChoice && other.link?.remote == remote.id
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        name = workspace?.name ?? ""
        symbol = workspace?.symbol ?? "tray"
        if let link = workspace?.link {
            serverChoice = link.server
            remoteChoice = link.remote
        }
    }

    private func loadRemotes() async {
        guard let server = serverChoice else {
            remotes = []
            return
        }
        loadingRemotes = true
        remotes = await model.sessions.remoteWorkspaces(on: server)
        loadingRemotes = false
        if remoteChoice != Self.newRemote, !remotes.contains(where: { $0.id == remoteChoice }) {
            remoteChoice = Self.newRemote
        }
    }

    private var target: WorkspaceTarget {
        guard let serverChoice else { return .local }
        return .server(serverChoice, remote: remoteChoice == Self.newRemote ? nil : remoteChoice)
    }

    private func save() {
        busy = true
        Task {
            if let workspace {
                model.updateWorkspace(workspace.id, name: name, symbol: symbol)
                if imageChanged { model.setWorkspaceImage(workspace.id, png: image) }
                let current = workspace.link.map { WorkspaceTarget.server($0.server, remote: $0.remote) } ?? .local
                if target != current { await model.relink(workspace.id, to: target) }
            } else {
                await model.createWorkspace(name: name, symbol: symbol, image: imageChanged ? image : nil, target: target)
            }
            busy = false
            dismiss()
        }
    }
}
