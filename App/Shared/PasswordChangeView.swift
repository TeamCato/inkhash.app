import InkhashCore
import SwiftUI

/// The signed-in account changes its own password. The form says what is missing before it
/// sends anything; the server checks the current password. See ADR 0050.
struct PasswordChangeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var serverID: UUID
    @State private var current = ""
    @State private var new = ""
    @State private var repeated = ""
    @State private var busy = false
    @State private var failure: String?

    private var problem: String? {
        PasswordChange.problem(current: current, new: new, repeated: repeated)
    }

    var body: some View {
        Form {
            Section {
                SecureField("Bisheriges Passwort", text: $current)
                    .textContentType(.password)
                SecureField("Neues Passwort", text: $new)
                    .textContentType(.newPassword)
                SecureField("Neues Passwort wiederholen", text: $repeated)
                    .textContentType(.newPassword)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let failure {
                        Text(failure).foregroundStyle(.red)
                    } else if !new.isEmpty || !repeated.isEmpty, let problem {
                        Text(problem)
                    }
                    Text("Andere Geräte mit diesem Account müssen sich danach neu anmelden. Die Notizen bleiben dort.")
                }
            }
            Section {
                Button {
                    send()
                } label: {
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Passwort ändern")
                    }
                }
                .disabled(busy || problem != nil)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Passwort ändern")
        .onChange(of: current) { failure = nil }
    }

    private func send() {
        busy = true
        failure = nil
        Task {
            let result = await model.sessions.changePassword(on: serverID, current: current, new: new)
            busy = false
            if let result {
                failure = result
            } else {
                dismiss()
            }
        }
    }
}
