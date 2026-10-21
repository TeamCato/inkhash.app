import Foundation
import InkhashCore
import Observation
import KennelKit

/// The one line at the bottom of the sidebar. Every part of the model reports here.
@MainActor
@Observable
final class StatusLine {
    var message = ""

    static let localOnly = "Nur auf diesem Gerät."
    static let synced = "Abgeglichen."

    /// Messages that say nothing is wrong. The sidebar shows its logo instead of them. See ADR 0056.
    static func isRoutine(_ message: String) -> Bool {
        message.isEmpty || message == localOnly || message == synced
    }

    /// A failed request in words for the status line.
    static func describe(_ error: Error) -> String {
        switch error {
        case APIError.unauthorized:
            return "Anmeldung abgelehnt."
        case APIError.slowDown:
            return "Zu viele Versuche. Kurz warten."
        case APIError.notFound:
            return "Kennel kennt diesen Pfad nicht."
        case APIError.badStatus(423, _):
            return "Der Workspace zieht in Kennel gerade um. Der Abgleich geht danach weiter."
        case let APIError.badStatus(code, _):
            return "Kennel antwortete mit \(code)."
        case is URLError, KennelError.unreachable:
            return "Kennel nicht erreichbar."
        case KennelError.unauthorized:
            return "Anmeldung abgelehnt."
        case KennelError.slowDown:
            return "Zu viele Versuche. Kurz warten."
        case let KennelError.rejected(status, _, _, _):
            return "Kennel antwortete mit \(status)."
        case KennelError.invalidReply:
            return "Kennel antwortete unerwartet."
        case is SealError:
            return "Eine Notiz aus Kennel ließ sich nicht entschlüsseln."
        case VaultError.wrongRecoveryKey:
            return "Der Wiederherstellungsschlüssel passt nicht."
        case is VaultError:
            return "Der Tresor ließ sich nicht öffnen."
        case let error as KeychainError:
            return "Die Anmeldung ließ sich nicht im Schlüsselbund sichern (\(error.status))."
        case let KennelSessionStoreError.keychain(status):
            return "Die Anmeldung ließ sich nicht im Schlüsselbund sichern (\(status))."
        default:
            return "Abgleich fehlgeschlagen."
        }
    }
}
