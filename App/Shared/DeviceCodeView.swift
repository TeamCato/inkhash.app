import InkhashCore
import SwiftUI
import KennelKit

/// „Weiteres Gerät verbinden“: a device code of this account as text, join link and QR code,
/// with its expiry and a way to withdraw it. See ADR 0072, teamCato ADR 0005.
struct DeviceCodeView: View {
    @Environment(AppModel.self) private var model
    var serverID: UUID

    @State private var issued: IssuedJoinCode?
    @State private var problem: String?
    @State private var busy = false
    @State private var withdrawn = false

    var body: some View {
        Form {
            if let issued, !withdrawn, let server = model.registry.server(serverID), let url = URL(string: server.url),
               let link = issued.joinLink(on: url)?.absoluteString {
                Section {
                    QRCodeView(text: link, label: "QR-Code zum Verbinden eines Geräts")
                        .frame(maxWidth: 260)
                        .frame(maxWidth: .infinity)
                    Text(issued.code.description)
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                    Text(link)
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.muted)
                        .textSelection(.enabled)
                    ShareLink(item: link) { Label("Link teilen", systemImage: "square.and.arrow.up") }
                } footer: {
                    Text(footer(for: issued))
                }
                Section {
                    Button("Zurückziehen", role: .destructive) { withdraw(issued) }
                        .disabled(busy)
                }
            } else if withdrawn {
                Section {
                    Text("Der Code ist zurückgezogen.")
                    Button("Neuen Code erzeugen") { create() }
                        .disabled(busy)
                }
            } else if let problem {
                Section {
                    Text(problem).foregroundStyle(Ink.muted)
                    Button("Noch einmal") { create() }
                        .disabled(busy)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Weiteres Gerät verbinden")
        .task { if issued == nil { create() } }
    }

    private func footer(for issued: IssuedJoinCode) -> String {
        let until = "Gilt bis \(issued.expiresAt.formatted(date: .omitted, time: .shortened)), einmal. "
        return until + "Auf dem anderen Gerät den QR-Code scannen oder unter „Server verbinden“ Link oder Code eingeben. Ein Passwort braucht es dort nicht."
    }

    private func create() {
        busy = true
        problem = nil
        Task {
            switch await model.sessions.createDeviceCode(on: serverID) {
            case .success(let code):
                issued = code
                withdrawn = false
            case .failure(let failure):
                problem = failure.message
            }
            busy = false
        }
    }

    private func withdraw(_ code: IssuedJoinCode) {
        busy = true
        Task {
            if let failure = await model.sessions.revokeJoinCode(code.id, on: serverID) {
                problem = failure
            } else {
                withdrawn = true
                issued = nil
            }
            busy = false
        }
    }
}
