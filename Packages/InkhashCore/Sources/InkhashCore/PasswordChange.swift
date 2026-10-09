import Foundation

/// What the app checks before it asks the server to change a password. The server checks the
/// same lengths again; see API.md and ADR 0050.
public enum PasswordChange {
    public static let minimum = 8
    public static let maximum = 200

    /// Why the form cannot be sent yet, in words for the form, or nil if it can.
    public static func problem(current: String, new: String, repeated: String) -> String? {
        if current.isEmpty { return "Das bisherige Passwort fehlt." }
        if new.count < minimum { return "Das neue Passwort braucht mindestens \(minimum) Zeichen." }
        if new.count > maximum { return "Das neue Passwort hat höchstens \(maximum) Zeichen." }
        if new != repeated { return "Die Wiederholung passt nicht." }
        if new == current { return "Das neue Passwort ist das alte." }
        return nil
    }
}
