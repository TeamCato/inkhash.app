import InkhashCore
import KennelKit
import KennelKitUI
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Creates a workspace (`workspace` nil) or edits one. A new one asks first where it lies: „Auf diesem Gerät“ or „In
/// Kennel“ with a storage, then name and look (teamCato ADR 0009 point 5). An existing one changes where it lies only
/// in its section „Ort“ (point 6). See ADR 0077.
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
    /// Where a new workspace lies.
    @State private var place: KennelPlacePicker<AnyView>.Choice? = .device
    @State private var storageID: String? = TakeOverPlanner.standardStorage
    @State private var connecting = false
    @State private var newStorage = false
    /// „In Kennel ablegen …“ or „Anderer Speicher …“ of an existing workspace.
    @State private var storageSheet: StorageSheet.Mode?
    @State private var confirmHereOnly = false
    @State private var confirmKennelDelete = false
    @State private var busy = false
    @State private var failure: String?
    @State private var confirmRemoval = false
    @State private var loaded = false
    @State private var exported: ExportedFile?

    /// Where the notes are safe besides the export. See ADR 0051.
    #if os(macOS)
    static let backupFooter = "Eine ZIP-Datei mit allen Notizen als Markdown und PDF und einer Kopie, die „Importieren“ zurückholt. Auf dem Mac sichert Time Machine die Notizen ohnehin mit."
    #else
    static let backupFooter = "Eine ZIP-Datei mit allen Notizen als Markdown und PDF und einer Kopie, die „Importieren“ zurückholt. Ist das iCloud-Backup des Geräts an, liegen die Notizen auch dort."
    #endif
    static let symbols = ["house", "briefcase", "tray", "book", "lightbulb", "graduationcap", "heart", "leaf", "hammer", "paintpalette", "airplane", "cart"]

    var body: some View {
        Form {
            if let workspace {
                lookSections
                placeSection(workspace)
                Section {
                    Button("Exportieren…") { exported = model.exportWorkspace(workspace.id) }
                } header: {
                    Text("Sicherung")
                } footer: {
                    Text(Self.backupFooter)
                }
                if model.registry.workspaces.count > 1 {
                    removeSection(workspace)
                }
            } else {
                KennelPlacePicker(
                    choice: $place, storageID: $storageID, question: "Wo soll er liegen?",
                    deviceSubtitle: "Nur hier, kein Abgleich. Später verschiebbar.",
                    kennelSubtitle: "Auf all deinen Geräten, gesichert im Speicher.",
                    isConnected: model.isSyncEnabled, connect: { connecting = true },
                    storages: model.overview.summaries,
                    newStorage: newStorageAction
                ) {
                    // `AnyView`: the picker's choice type depends on what it holds below.
                    AnyView(Group {
                        lookSections
                        if place == .kennel { alreadyInKennel }
                    })
                }
            }
            if let failure {
                Text(failure)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.warning)
            }
        }
        .formStyle(.grouped)
        .kennelBrand(.inkhash)
        .navigationTitle(workspace == nil ? "Neuer Workspace" : workspace?.name ?? "")
        .toolbar {
            if workspace == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(workspace == nil ? "Anlegen" : "Sichern") { save() }
                    .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty || (place == .kennel && storageID == nil))
            }
        }
        .fileExporter(
            isPresented: Binding(get: { exported != nil }, set: { if !$0 { exported = nil } }),
            document: exported,
            contentType: .zip,
            defaultFilename: exported?.url.lastPathComponent
        ) { result in
            if case .failure = result { model.status = "Die Sicherung ließ sich nicht ablegen." }
            exported = nil
        }
        .onAppear(perform: load)
        .task { await model.refreshKennel() }
        .kennelConnectSheet(isPresented: $connecting)
        .onChange(of: model.isSyncEnabled) { _, connected in
            // Back from „Erst verbinden …“: the Kennel card was what the person wanted.
            guard connected, workspace == nil else { return }
            place = .kennel
            Task { await model.refreshKennel() }
        }
        .sheet(isPresented: $newStorage) {
            NewStorageSheet { storageID = $0.id }
        }
        .sheet(item: $storageSheet) { mode in
            if let workspace { StorageSheet(workspace: workspace, mode: mode) }
        }
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

    /// „Neuer Speicher …“ where Kennel lets a workspace choose its storage.
    private var newStorageAction: (@MainActor () -> Void)? {
        guard model.overview.module?.workspaceStorage == true else { return nil }
        return { newStorage = true }
    }

    // MARK: Look

    @ViewBuilder
    private var lookSections: some View {
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

    // MARK: Place

    /// Kennel workspaces not on this device yet; taking one is the other way to get a workspace „In Kennel“.
    @ViewBuilder
    private var alreadyInKennel: some View {
        let unlinked = model.overview.unlinked(in: model.registry.setup)
        if !unlinked.isEmpty {
            Section {
                ForEach(unlinked) { remote in
                    HStack {
                        Label(remote.name, systemImage: remote.symbol ?? "tray")
                        Spacer()
                        Button("Hinzufügen") { add(remote) }
                            .disabled(busy)
                    }
                }
            } header: {
                Text("Schon in Kennel")
            } footer: {
                Text("Ein hinzugefügter Workspace kommt mit seinen Notizen, seinem Aussehen und seinem Platz in der Reihenfolge.")
            }
        }
    }

    /// „Ort“: where it lies and how to change that, the only place for it (teamCato ADR 0009 point 6).
    @ViewBuilder
    private func placeSection(_ workspace: Workspace) -> some View {
        let current = model.registry.workspace(workspace.id) ?? workspace
        let remote = model.overview.remote(of: current)
        let storage = model.overview.storage(of: remote)
        if model.kennel != nil || current.link != nil {
            KennelPlaceSection(
                place: model.overview.place(of: current), storage: storage?.name, visibility: storage?.visibility,
                actions: placeActions(current, remote: remote)
            ) {
                if current.link?.sealed == true {
                    Text(model.overview.state.conversionText ?? "Verschlüsselt. inkhash wandelt ihn beim nächsten Abgleich in einen unverschlüsselten Workspace auf demselben Speicher um.")
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.muted)
                }
                if let move = remote?.move, !move.isRunning {
                    Text("Der letzte Umzug ist gescheitert\(move.detail.map { " (\($0))" } ?? ""). Die Notizen liegen noch am alten Ort.")
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.warning)
                }
            }
            .confirmationDialog("Nur noch auf diesem Gerät?", isPresented: $confirmHereOnly, titleVisibility: .visible) {
                Button("Nur noch hier") { model.keepOnlyHere(workspace.id) }
            } message: {
                Text("Der Workspace gleicht nicht mehr ab. Seine Notizen bleiben auf diesem Gerät, die Kopie in Kennel bleibt dort.")
            }
            .confirmationDialog("„\(current.name)“ in Kennel löschen?", isPresented: $confirmKennelDelete, titleVisibility: .visible) {
                Button("In Kennel löschen", role: .destructive) {
                    guard let remote else { return }
                    run { await model.deleteInKennel(remote) }
                }
            } message: {
                Text("Er verschwindet in Kennel für alle Geräte; dort bleibt er nur noch auf dem jeweiligen Gerät. Hier bleiben die Notizen, ohne Abgleich. Rückgängig machen kann das nur ein Admin in Kennel.")
            }
        }
    }

    private func placeActions(_ workspace: Workspace, remote: RemoteWorkspace?) -> [KennelPlaceAction] {
        guard let link = workspace.link else {
            guard model.isSyncEnabled else { return [] }
            return [KennelPlaceAction("In Kennel ablegen …") { storageSheet = .place }]
        }
        if remote?.move?.isRunning == true { return [] }
        var actions: [KennelPlaceAction] = []
        if model.isSyncEnabled, !link.sealed, model.overview.module?.workspaceMove == true, let remote {
            actions.append(KennelPlaceAction("Anderer Speicher …") { storageSheet = .move(current: KennelStorages.summaryID(of: remote)) })
        }
        actions.append(KennelPlaceAction("Nur noch auf diesem Gerät …") { confirmHereOnly = true })
        if model.isSyncEnabled, remote != nil, model.overview.remotes.count > 1 {
            actions.append(KennelPlaceAction("In Kennel löschen …", isDestructive: true) { confirmKennelDelete = true })
        }
        return actions
    }

    private func removeSection(_ workspace: Workspace) -> some View {
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
                : "Die Notizen verschwinden von diesem Gerät. In Kennel bleiben sie.")
        }
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        name = workspace?.name ?? ""
        symbol = workspace?.symbol ?? "tray"
    }

    private func add(_ remote: RemoteWorkspace) {
        busy = true
        Task {
            await model.addFromKennel([remote])
            busy = false
            dismiss()
        }
    }

    private func run(_ work: @escaping () async -> String?) {
        busy = true
        failure = nil
        Task {
            failure = await work()
            busy = false
        }
    }

    private func save() {
        busy = true
        failure = nil
        Task {
            if let workspace {
                model.updateWorkspace(workspace.id, name: name, symbol: symbol)
                if imageChanged { model.setWorkspaceImage(workspace.id, png: image) }
            } else {
                let target: WorkspaceTarget = place == .kennel ? .kennel(storageID: KennelStorages.storageID(storageID)) : .local
                if let problem = await model.createWorkspace(
                    name: name, symbol: symbol, image: imageChanged ? image : nil, target: target)
                {
                    failure = problem
                    busy = false
                    return
                }
            }
            busy = false
            dismiss()
        }
    }
}

/// Choosing a storage for a workspace that lies only here („In Kennel ablegen“) or that moves („Anderer Speicher“).
struct StorageSheet: View {
    enum Mode: Identifiable, Hashable {
        case place
        /// `current`: the summary id of the storage it lies in.
        case move(current: String)

        var id: String {
            switch self {
            case .place: "place"
            case .move(let current): "move:" + current
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let workspace: Workspace
    let mode: Mode
    @State private var choice: String?
    @State private var newStorage = false
    @State private var busy = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(model.overview.summaries) { storage in
                        Button {
                            choice = storage.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(storage.title)
                                    Text(storage.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .opacity(choice == storage.id ? 1 : 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isCurrent(storage.id))
                    }
                    if model.overview.module?.workspaceStorage == true {
                        Button("Neuer Speicher …") { newStorage = true }
                    }
                } header: {
                    Text("Speicher")
                } footer: {
                    Text(footer)
                }
                if let failure {
                    Text(failure).foregroundStyle(Ink.warning)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirm) { apply() }
                        .disabled(busy || choice == nil)
                }
            }
            .sheet(isPresented: $newStorage) {
                NewStorageSheet { choice = $0.id }
            }
        }
        .kennelBrand(.inkhash)
        .macSheetSize(minWidth: 440, minHeight: 420)
        .onAppear {
            if case .place = mode, choice == nil { choice = TakeOverPlanner.standardStorage }
        }
    }

    private var title: String {
        if case .place = mode { return "In Kennel ablegen" }
        return "Anderer Speicher"
    }

    private var confirm: String {
        if case .place = mode { return "Ablegen" }
        return "Umziehen"
    }

    private var footer: String {
        switch mode {
        case .place:
            "Alle Notizen von „\(workspace.name)“ gehen in einen neuen Workspace in Kennel und gleichen danach mit deinen anderen Geräten ab. Wer sie sieht, legt der Speicher fest. Hier bleibt alles, wie es ist."
        case .move:
            "Kennel kopiert alle Notizen und Bilder in den neuen Speicher und löscht sie erst danach am alten Ort. So lange heißt der Workspace „Zieht um“ und gleicht nicht ab; lesen und schreiben geht hier weiter. Wer ihn sieht, folgt dem neuen Speicher."
        }
    }

    private func isCurrent(_ id: String) -> Bool {
        if case .move(let current) = mode { return current == id }
        return false
    }

    private func apply() {
        guard let choice else { return }
        busy = true
        failure = nil
        Task {
            switch mode {
            case .place:
                failure = await model.placeInKennel(workspace.id, storageID: KennelStorages.storageID(choice))
            case .move:
                switch await model.moveInKennel(workspace.id, to: KennelStorages.storageID(choice)) {
                case .success:
                    let id = workspace.id
                    Task { await model.watchMove(of: id) }
                case .failure(let problem):
                    failure = problem.message
                }
            }
            busy = false
            if failure == nil { dismiss() }
        }
    }
}

/// „Neuer Speicher …“ from KennelKitUI, only for inkhash (Kennel ADR 0025). `created` hears of the new one.
struct NewStorageSheet: View {
    @Environment(AppModel.self) private var model
    var created: (KennelStorage) -> Void

    var body: some View {
        NavigationStack {
            if let kennel = model.kennel, let client = model.sessions.client(for: kennel.id) {
                KennelNewStorageView(client: client.kennel, module: APIClient.module) { storage in
                    model.addStorage(storage)
                    created(storage)
                }
            } else {
                Text("Nicht mit Kennel verbunden.").foregroundStyle(Ink.muted)
            }
        }
        .kennelBrand(.inkhash)
        .macSheetSize(minWidth: 420, minHeight: 460)
    }
}
