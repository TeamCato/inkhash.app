import Foundation

/// Folder paths: segments joined by "/". A note lies in exactly one folder or in none (""). See ADR 0020.
public enum Folders {
    public static let maxLength = 200
    public static let maxSegment = 60

    /// Cleans up a single folder name typed by someone. Nil if nothing usable is left.
    public static func segment(_ raw: String) -> String? {
        let cleaned = raw
            .replacingOccurrences(of: "/", with: "-")
            .filter { !$0.isNewline && $0.unicodeScalars.allSatisfy { $0.value >= 32 } }
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        return cleaned.clippedUTF16(maxSegment).trimmingCharacters(in: .whitespaces)
    }

    /// A whole path as someone types it: "project xy / meeting z". Segments are cleaned, empty ones
    /// dropped. Nil only if the result is still too long. Empty input is the root.
    public static func path(_ raw: String) -> String? {
        let joined = raw.split(separator: "/").compactMap { segment(String($0)) }.joined(separator: "/")
        return isValid(joined) ? joined : nil
    }

    /// The path as shown to someone: segments with " / " between them.
    public static func display(_ path: String) -> String {
        path.split(separator: "/").joined(separator: " / ")
    }

    public static func join(_ parent: String, _ name: String) -> String {
        parent.isEmpty ? name : parent + "/" + name
    }

    public static func name(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    public static func parent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    public static func depth(of path: String) -> Int {
        path.isEmpty ? 0 : path.split(separator: "/").count - 1
    }

    /// The path and every folder above it, outermost first.
    public static func lineage(of path: String) -> [String] {
        guard !path.isEmpty else { return [] }
        var result: [String] = []
        var current = ""
        for segment in path.split(separator: "/") {
            current = join(current, String(segment))
            result.append(current)
        }
        return result
    }

    /// True if `path` is `folder` itself or lies somewhere below it.
    public static func contains(_ folder: String, _ path: String) -> Bool {
        path == folder || path.hasPrefix(folder + "/")
    }

    /// Where `path` ends up when `folder` moves to `target`. Unrelated paths stay.
    public static func moved(_ path: String, from folder: String, to target: String) -> String {
        guard contains(folder, path) else { return path }
        return target + path.dropFirst(folder.count)
    }

    public static func isValid(_ path: String) -> Bool {
        if path.isEmpty { return true }
        guard path.utf16.count <= maxLength else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { segment in
            !segment.isEmpty && segment.utf16.count <= maxSegment && segment == segment.trimmingCharacters(in: .whitespaces)
        }
    }

    /// Every folder that exists: the ones kept on their own plus those notes lie in, with their parents.
    /// Sorted like a tree: parents before children, siblings by name.
    public static func tree(kept: [String], used: [String]) -> [String] {
        var all = Set<String>()
        for path in kept + used where isValid(path) {
            all.formUnion(lineage(of: path))
        }
        return all.sorted { lhs, rhs in
            let a = lhs.split(separator: "/").map { $0.lowercased() }
            let b = rhs.split(separator: "/").map { $0.lowercased() }
            return a.lexicographicallyPrecedes(b)
        }
    }
}
