import Foundation

/// Notes made from inside another note while embedding hang below it in the tree, as long as both
/// lie in the same folder. See ADR 0090.
public enum NoteFamily {
    /// For each note that hangs below another one among `notes`: the id of that other note.
    public static func parents(among notes: [Note]) -> [UUID: UUID] {
        let byID = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var direct: [UUID: UUID] = [:]
        for note in byID.values {
            guard let parent = note.parent, parent != note.id, let above = byID[parent], above.folder == note.folder else { continue }
            direct[note.id] = parent
        }
        // Only a merged or hand-edited library can make a loop. Its notes hang nowhere.
        let looping = Set(direct.keys.filter { id in
            var seen: Set<UUID> = []
            var current = id
            while let next = direct[current], seen.insert(next).inserted {
                if next == id { return true }
                current = next
            }
            return false
        })
        return direct.filter { !looping.contains($0.key) }
    }

    /// Every note hanging below `id`, however deep, nearest first.
    public static func descendants(of id: UUID, among notes: [Note]) -> [UUID] {
        var children: [UUID: [UUID]] = [:]
        for (child, parent) in parents(among: notes) {
            children[parent, default: []].append(child)
        }
        var result: [UUID] = []
        var queue = children[id] ?? []
        while !queue.isEmpty {
            let next = queue.removeFirst()
            result.append(next)
            queue += children[next] ?? []
        }
        return result
    }
}
