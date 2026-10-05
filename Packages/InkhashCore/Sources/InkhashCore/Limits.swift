import Foundation

/// What the server accepts, see API.md "Grenzen". The server counts lengths in UTF-16 code units,
/// like JavaScript's `length`, so the app does too; an emoji can take up to eleven of them.
public enum Limits {
    public static let title = 200
    public static let tagsPerNote = 50
    public static let tagLength = 40
    public static let pages = 100
    public static let pageSide = 10_000.0
    public static let workspaceName = 40
}

extension String {
    /// The longest prefix of whole characters that fits into `limit` UTF-16 code units.
    public func clippedUTF16(_ limit: Int) -> String {
        guard utf16.count > limit else { return self }
        var used = 0
        var end = startIndex
        for character in self {
            let width = character.utf16.count
            guard used + width <= limit else { break }
            used += width
            end = index(after: end)
        }
        return String(self[..<end])
    }
}
