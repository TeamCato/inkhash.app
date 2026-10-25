import InkhashCore
import SwiftUI

/// The question before „In Kennel löschen“, in the app's own style instead of a system dialog: what is deleted where,
/// what stays on the devices, and that it cannot be undone. See ADR 0083.
struct KennelDeleteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let remote: RemoteWorkspace
    /// The storage it lies in, as the place section names it.
    let storage: String?
    /// Kennel removes the notes and pictures from the storage (Kennel ADR 0063); older servers keep them.
    let removesContent: Bool
    @State private var noteCount: Int?
    @State private var busy = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "trash")
                    .foregroundStyle(Self.danger)
                Text("„\(remote.name)“ in Kennel löschen?")
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                point("externaldrive", storageLine)
                point("ipad.and.iphone", "Auf deinen anderen Geräten gleicht er nicht mehr ab; dort bleibt er nur noch auf dem jeweiligen Gerät.")
                point("checkmark.circle", "Auf diesem Gerät bleiben die Notizen, ohne Abgleich.")
            }
            Text(removesContent ? "Das lässt sich nicht rückgängig machen." : "Zurückholen kann ihn nur ein Admin in Kennel.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(removesContent ? Self.danger : Ink.muted)
            if let failure {
                Text(failure)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.warning)
            }
            HStack(spacing: 10) {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                    .tint(Ink.accent)
                Button(role: .destructive, action: delete) {
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(removesContent ? "Endgültig löschen" : "In Kennel löschen")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Self.danger)
                .disabled(busy)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 460, alignment: .leading)
        #else
        // The whole sheet is paper: a narrower frame showed as a second edge on the iPad.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .presentationDetents([.medium, .large])
        .presentationBackground(Ink.paper)
        #endif
        .background(Ink.paper)
        .interactiveDismissDisabled(busy)
        .task { noteCount = await model.noteCount(of: remote) }
    }

    /// A muted red: clear about the danger, calm on paper.
    static let danger = Color(red: 0.698, green: 0.231, blue: 0.188)

    private var storageLine: String {
        let place = storage.map { "im Speicher „\($0)“" } ?? "in Kennel"
        let notes = switch noteCount {
        case .none, .some(0): "Seine Notizen und Bilder"
        case .some(1): "Seine eine Notiz und ihre Bilder"
        case .some(let count): "Seine \(count) Notizen und ihre Bilder"
        }
        return removesContent
            ? "\(notes) werden \(place) gelöscht, für alle Geräte."
            : "Er verschwindet in Kennel für alle Geräte; \(notes.prefix(1).lowercased() + notes.dropFirst()) bleiben \(place) liegen."
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(Ink.accent)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func delete() {
        busy = true
        failure = nil
        Task {
            failure = await model.deleteInKennel(remote)
            busy = false
            if failure == nil { dismiss() }
        }
    }
}
