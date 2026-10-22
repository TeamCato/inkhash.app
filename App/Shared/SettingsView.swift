import InkhashCore
import SwiftUI
import KennelKit
import KennelKitUI

/// The settings: „Kennel“ first, then text, then the workspaces of this device with where each lies. Kennel has
/// its own page (teamCato ADR 0009 point 3); workspaces stay here and in the sidebar. See ADR 0077.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        KennelSettingsView()
                    } label: {
                        LabeledContent {
                            Text(kennelSummary)
                        } label: {
                            Label("Kennel", systemImage: "house")
                        }
                    }
                }
                TextSettingsSection()
                Section {
                    ForEach(model.registry.workspaces) { workspace in
                        NavigationLink {
                            WorkspaceEditor(workspace: workspace)
                        } label: {
                            HStack {
                                Label {
                                    Text(workspace.name)
                                } icon: {
                                    WorkspaceIcon(workspace: workspace)
                                }
                                Spacer()
                                if model.kennel != nil {
                                    KennelPlaceBadge(model.overview.place(of: workspace))
                                }
                            }
                        }
                        .contextMenu {
                            Button("Nach oben", systemImage: "arrow.up") { model.moveWorkspace(workspace.id, by: -1) }
                                .disabled(workspace.id == model.registry.workspaces.first?.id)
                            Button("Nach unten", systemImage: "arrow.down") { model.moveWorkspace(workspace.id, by: 1) }
                                .disabled(workspace.id == model.registry.workspaces.last?.id)
                        }
                    }
                    .onMove { model.moveWorkspaces(fromOffsets: $0, toOffset: $1) }
                    NavigationLink {
                        WorkspaceEditor(workspace: nil)
                    } label: {
                        Label("Workspace anlegen", systemImage: "plus")
                    }
                } header: {
                    Text("Workspaces")
                } footer: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Jeder Workspace hat eigene Notizen, Ordner und Schlagwörter. Wo er liegt, änderst du in seinem Abschnitt „Ort“. Die Reihenfolge änderst du durch Ziehen oder im Kontextmenü.")
                        MadeByTeamCato()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Einstellungen")
            .preferredColorScheme(.light)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .inkButton()
                }
            }
        }
        .macSheetSize(minWidth: 480, minHeight: 480)
    }

    /// „kennel.local“ while connected, else „Nicht verbunden“.
    private var kennelSummary: String {
        guard let kennel = model.kennel else { return "Nicht verbunden" }
        return ServerAddress.host(kennel.url)
    }
}

/// Font and size of text notes on this device: first in the settings, and on the Mac also under
/// Inkhash > Einstellungen (Cmd+,). See ADR 0061.
struct TextSettingsSection: View {
    @AppStorage(TextAppearance.familyKey) private var family = TextFamily.standard.rawValue
    @AppStorage(TextAppearance.sizeKey) private var size = TextAppearance.defaultSize

    var body: some View {
        Section {
            Picker("Schrift", selection: $family) {
                ForEach(TextFamily.allCases) { family in
                    Text(family.title).tag(family.rawValue)
                }
            }
            HStack(spacing: 12) {
                Text("Größe")
                Slider(value: $size, in: TextAppearance.sizes, step: 1)
                Text("\(Int(size)) pt")
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.muted)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            Text("So sieht Text in deinen Notizen aus.")
                .font(preview)
                .foregroundStyle(Ink.ink)
            if family != TextFamily.standard.rawValue || size != TextAppearance.defaultSize {
                Button("Standard wiederherstellen") {
                    family = TextFamily.standard.rawValue
                    size = TextAppearance.defaultSize
                }
            }
        } header: {
            Text("Text")
        } footer: {
            Text("Gilt für alle Textnotizen auf diesem Gerät. Überschriften bleiben in der Serif, Code in Monospace. Auf iPad und iPhone kommt die Textgröße des Systems dazu.")
        }
        .onAppear {
            // A value from outside the range shows as what the editor uses.
            size = TextAppearance.current.size
        }
    }

    private var preview: Font {
        let design: Font.Design = switch TextFamily(rawValue: family) ?? .standard {
        case .standard: .default
        case .serif: .serif
        case .rounded: .rounded
        case .mono: .monospaced
        }
        return .system(size: size, design: design)
    }
}

/// "made by teamCato" at the foot of the settings, like in the other apps of the family. Links to the
/// teamCato website.
struct MadeByTeamCato: View {
    @ScaledMetric(relativeTo: .footnote) private var logoHeight: CGFloat = 20

    /// Fraction of the logo height where the "teamCato" wordmark sits on its baseline.
    private nonisolated static let logoBaselineRatio: CGFloat = 0.79
    private static let website = URL(string: "https://teamcato.de")!

    var body: some View {
        Link(destination: Self.website) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("made by")
                // Template image, tinted like the text.
                Image("TeamCatoLogo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: logoHeight)
                    .alignmentGuide(.firstTextBaseline) { $0.height * Self.logoBaselineRatio }
                    .accessibilityLabel("teamCato")
            }
            .font(.footnote)
            .foregroundStyle(Ink.muted)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
