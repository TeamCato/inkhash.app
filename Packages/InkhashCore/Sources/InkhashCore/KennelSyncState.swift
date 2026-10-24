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
    /// Encrypted workspaces that do not sync here while the vault is not open on this device (ADR 0082).
    public var waitingForKey: [String]
    /// Kept for the conversions of ADR 0077 still running on older devices; inkhash starts none anymore.
    public var waitingForKennel: [String]

    public init(phase: Phase = .idle, sessionExpired: Bool = false, waitingForKey: [String] = [], waitingForKennel: [String] = []) {
        self.phase = phase
        self.sessionExpired = sessionExpired
        self.waitingForKey = waitingForKey
        self.waitingForKennel = waitingForKennel
    }

    /// Title of the attention state while encrypted workspaces are locked (ADR 0082). Only then the vault is mentioned.
    public static let lockedTitle = "Verschlüsselte Workspaces gesperrt"
    /// Its action, which opens the vault.
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
        if !waitingForKey.isEmpty { return .attention(title: Self.lockedTitle, action: Self.openVault) }
        switch phase {
        case .idle: return .checking
        case .synced(let date): return .synced(date)
        case .failed(let detail): return .failed(detail: detail)
        case .moduleOff, .unreachable, .syncing: return .checking
        }
    }

    /// What a locked encrypted workspace says where it is shown.
    public static let lockedHint = "Zum Ansehen den Tresor öffnen."

    /// Whether this workspace is locked here.
    public func isLocked(_ name: String) -> Bool {
        waitingForKey.contains(name)
    }

    static func list(_ names: [String]) -> String {
        let quoted = names.map { "„\($0)“" }
        guard quoted.count > 1, let last = quoted.last else { return quoted.first ?? "" }
        return quoted.dropLast().joined(separator: ", ") + " und " + last
    }
}
