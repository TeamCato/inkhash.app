import Foundation
import KennelKit

/// Where syncing with Kennel stands, as the sidebar's foot and the Kennel page show it with KennelKit's sentences
/// (teamCato ADR 0009 point 7, ADR 0077). Filled by the app's sync; mapped here so the mapping can be tested.
public struct KennelSyncState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Nothing tried yet since the start.
        case idle
        case syncing
        case synced(Date)
        /// Kennel did not answer.
        case unreachable
        /// Kennel answered, but the module inkhash is missing or off (ADR 0067).
        case moduleOff
        case failed(String)
    }

    public var phase: Phase
    /// Kennel no longer knows the session (ADR 0017).
    public var sessionExpired: Bool
    /// Encrypted workspaces Kennel holds notes in this device cannot read without the vault (ADR 0077).
    public var waitingForKey: [String]
    /// Encrypted workspaces that wait for Kennel: it cannot make plain workspaces yet, or they are moving.
    public var waitingForKennel: [String]

    public init(phase: Phase = .idle, sessionExpired: Bool = false, waitingForKey: [String] = [], waitingForKennel: [String] = []) {
        self.phase = phase
        self.sessionExpired = sessionExpired
        self.waitingForKey = waitingForKey
        self.waitingForKennel = waitingForKennel
    }

    /// Title of the attention state while encrypted workspaces wait.
    public static let convertTitle = "Umwandeln"
    /// Its action, which opens the explanation and the vault.
    public static let openVault = "Tresor öffnen …"

    /// The status line; the app shows it only while Kennel is connected. Signing in again beats everything, then the
    /// module, then what keeps the person's notes from Kennel, then the plain sync state.
    public var status: KennelStatus {
        if sessionExpired { return .signInAgain }
        switch phase {
        case .moduleOff: return .moduleOff
        case .unreachable: return .unreachable
        case .syncing: return .syncing
        default: break
        }
        if !waitingForKey.isEmpty { return .attention(title: Self.convertTitle, action: Self.openVault) }
        if !waitingForKennel.isEmpty { return .attention(title: Self.convertTitle, action: nil) }
        switch phase {
        case .idle: return .checking
        case .synced(let date): return .synced(date)
        case .failed(let detail): return .failed(detail: detail)
        case .moduleOff, .unreachable, .syncing: return .checking
        }
    }

    /// What „Umwandeln“ means, for the sheet behind its action and the workspace's „Ort“.
    public var conversionText: String? {
        if !waitingForKey.isEmpty {
            return Self.waitingForKeyText(waitingForKey)
        }
        if !waitingForKennel.isEmpty {
            return "\(Self.list(waitingForKennel)) \(waitingForKennel.count == 1 ? "wartet" : "warten") auf Kennel: Es braucht eine Version, die unverschlüsselte Workspaces anlegt, oder ein Umzug läuft noch. Die Notizen bleiben auf diesem Gerät."
        }
        return nil
    }

    public static func waitingForKeyText(_ names: [String]) -> String {
        let one = names.count == 1
        return "inkhash verschlüsselt in Kennel nicht mehr. \(list(names)) \(one ? "ist" : "sind") noch verschlüsselt und \(one ? "wird" : "werden") zu \(one ? "einem unverschlüsselten Workspace" : "unverschlüsselten Workspaces") auf demselben Speicher. Dazu muss ein Gerät den letzten Stand lesen: eines, auf dem der Tresor offen ist, oder dieses mit dem Wiederherstellungsschlüssel. Bis dahin bleiben die Notizen auf diesem Gerät und es geht nichts verloren."
    }

    static func list(_ names: [String]) -> String {
        let quoted = names.map { "„\($0)“" }
        guard quoted.count > 1, let last = quoted.last else { return quoted.first ?? "" }
        return quoted.dropLast().joined(separator: ", ") + " und " + last
    }
}
