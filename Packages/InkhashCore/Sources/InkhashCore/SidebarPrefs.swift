import Foundation

/// How the sidebar of one workspace is arranged. Lives next to the library, on this device only. See ADR 0022.
public struct SidebarPrefs: Codable, Equatable, Sendable {
    /// Tree nodes someone folded shut. Everything else is open.
    public var collapsed: [String]

    public init(collapsed: [String] = []) {
        self.collapsed = collapsed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        collapsed = try container.decodeIfPresent([String].self, forKey: .collapsed) ?? []
    }
}
