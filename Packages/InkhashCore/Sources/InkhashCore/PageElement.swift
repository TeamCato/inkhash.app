import Foundation

/// Something on a handwriting page besides ink: a photo, a shape, a strip of tape or a link area.
/// Center-based like Scweble; coordinates are page coordinates like the strokes. See ADR 0028.
public struct PageElement: Equatable, Sendable, Identifiable, Codable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case image, shape, tape, link
        /// A window onto another note: a page rectangle or text. `link` is its target. See ADR 0037.
        case excerpt
    }

    public enum ShapeForm: String, Codable, Sendable, CaseIterable {
        case line, rect, ellipse, triangle
    }

    public struct Frame: Equatable, Sendable, Codable {
        public enum Style: String, Codable, Sendable, CaseIterable {
            case none, solid, polaroid
        }

        public var style: Style
        public var color: String
        public var width: Double
        public var shadow: Bool

        public init(style: Style, color: String = "#FFFFFF", width: Double = 12, shadow: Bool = true) {
            self.style = style
            self.color = color
            self.width = width
            self.shadow = shadow
        }

        public static let classic = Frame(style: .solid)
    }

    public struct Point: Equatable, Sendable, Codable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public struct Mask: Equatable, Sendable, Codable {
        public enum Kind: String, Codable, Sendable, CaseIterable {
            case circle, rectangle, freehand
        }

        public var kind: Kind
        /// Freehand outline, 0…1 in the photo area.
        public var points: [Point]

        public init(kind: Kind, points: [Point] = []) {
            self.kind = kind
            self.points = points
        }

        enum CodingKeys: String, CodingKey { case kind, points }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decode(Kind.self, forKey: .kind)
            points = try container.decodeIfPresent([Point].self, forKey: .points) ?? []
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            if kind == .freehand { try container.encode(points, forKey: .points) }
        }
    }

    public var id: UUID
    public var kind: Kind
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    /// Radians, around the center.
    public var rotation: Double
    public var z: Int
    public var blob: String?
    public var frame: Frame?
    public var mask: Mask?
    public var shape: ShapeForm?
    public var stroke: String?
    public var strokeWidth: Double?
    public var fill: String?
    public var fillOpacity: Double?
    public var color: String?
    /// `https://…`, `mailto:…` or `inkhash://note/<id>`. On an excerpt, its target (`ExcerptTarget`).
    public var link: String?

    public init(
        id: UUID = UUID(), kind: Kind, x: Double, y: Double, width: Double, height: Double,
        rotation: Double = 0, z: Int = 0, blob: String? = nil, frame: Frame? = nil, mask: Mask? = nil,
        shape: ShapeForm? = nil, stroke: String? = nil, strokeWidth: Double? = nil, fill: String? = nil,
        fillOpacity: Double? = nil, color: String? = nil, link: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.z = z
        self.blob = blob
        self.frame = frame
        self.mask = mask
        self.shape = shape
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        self.fill = fill
        self.fillOpacity = fillOpacity
        self.color = color
        self.link = link
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, x, y, width, height, rotation, z, blob, frame, mask, shape
        case stroke, strokeWidth, fill, fillOpacity, color, link
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = UUID(uuidString: try container.decode(String.self, forKey: .id)) else { throw InkhashError.invalidID }
        self.id = id
        kind = try container.decode(Kind.self, forKey: .kind)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        z = try container.decodeIfPresent(Int.self, forKey: .z) ?? 0
        blob = try container.decodeIfPresent(String.self, forKey: .blob)
        frame = try container.decodeIfPresent(Frame.self, forKey: .frame)
        mask = try container.decodeIfPresent(Mask.self, forKey: .mask)
        shape = try container.decodeIfPresent(ShapeForm.self, forKey: .shape)
        stroke = try container.decodeIfPresent(String.self, forKey: .stroke)
        strokeWidth = try container.decodeIfPresent(Double.self, forKey: .strokeWidth)
        fill = try container.decodeIfPresent(String.self, forKey: .fill)
        fillOpacity = try container.decodeIfPresent(Double.self, forKey: .fillOpacity)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        // Older versions stored addresses without a scheme, which the server refuses. See ADR 0031.
        link = try container.decodeIfPresent(String.self, forKey: .link).flatMap(LinkTarget.repaired)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(z, forKey: .z)
        try container.encodeIfPresent(blob, forKey: .blob)
        try container.encodeIfPresent(frame, forKey: .frame)
        try container.encodeIfPresent(mask, forKey: .mask)
        try container.encodeIfPresent(shape, forKey: .shape)
        // A shape without contour or fill says so with null, see API.md.
        if kind == .shape {
            try container.encode(stroke, forKey: .stroke)
            try container.encodeIfPresent(strokeWidth, forKey: .strokeWidth)
            try container.encode(fill, forKey: .fill)
            try container.encodeIfPresent(fillOpacity, forKey: .fillOpacity)
        }
        try container.encodeIfPresent(color, forKey: .color)
        try container.encodeIfPresent(link, forKey: .link)
    }

    /// An excerpt of another note on the page. See ADR 0037.
    public static func excerpt(_ target: ExcerptTarget, center: (x: Double, y: Double), width: Double, height: Double) -> PageElement {
        PageElement(kind: .excerpt, x: center.x, y: center.y, width: width, height: height, link: target.target)
    }

    /// What an excerpt element shows.
    public var excerptTarget: ExcerptTarget? {
        kind == .excerpt ? link.flatMap(ExcerptTarget.init(target:)) : nil
    }
}

/// Targets of links in text and on pages. See ADR 0027.
public enum NoteLink {
    public static let prefix = "inkhash://note/"

    public static func target(for id: UUID) -> String {
        prefix + id.uuidString.lowercased()
    }

    /// The note a target points to, if it is a note link.
    public static func noteID(in target: String) -> UUID? {
        guard target.lowercased().hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(target.dropFirst(prefix.count)))
    }
}

extension InkPage {
    /// Every blob the page needs: its drawing and the photos on it. Sync and import move all of them.
    public var blobNames: [String] {
        [blob] + elements.compactMap(\.blob)
    }
}
