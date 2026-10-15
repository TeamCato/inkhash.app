import Foundation

/// The due day of a task in Markdown: `📅 JJJJ-MM-TT` at the end of the line, as in Obsidian's
/// Tasks plugin. Only the last one at the very end counts. See ADR 0060.
public enum TaskDue {
    public static let marker = "📅"

    private static let trailing = try! NSRegularExpression(pattern: "\\s*📅\\s*(\\d{4}-\\d{2}-\\d{2})\\s*$")

    /// The text without its due day, and the day, if the text ends with a valid one.
    public static func split(_ text: String) -> (text: String, due: String?) {
        guard let range = trailingRange(in: text) else { return (text, nil) }
        let ns = text as NSString
        let day = ns.substring(with: range.day)
        return (ns.substring(to: range.whole.location), day)
    }

    /// The text with `due` at its end, replacing a day it had. Nil removes the day.
    public static func setting(_ due: String?, in text: String) -> String {
        let bare = split(text).text
        guard let due, isDay(due) else { return bare }
        let separator = bare.isEmpty || bare.hasSuffix(" ") ? "" : " "
        return bare + separator + "\(marker) \(due)"
    }

    /// Where the due day stands in `text`, the marker and its leading space included, and the day alone.
    public static func trailingRange(in text: String) -> (whole: NSRange, day: NSRange)? {
        let ns = text as NSString
        guard let match = trailing.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let day = match.range(at: 1)
        guard isDay(ns.substring(with: day)) else { return nil }
        return (match.range, day)
    }

    /// True for a real day written as `JJJJ-MM-TT`.
    public static func isDay(_ value: String) -> Bool {
        guard value.count == 10, let date = parser.date(from: value) else { return false }
        return parser.string(from: date) == value
    }

    /// Days in Markdown are Gregorian, whatever calendar the device shows; the time zone is the device's.
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// The day of `date`, as `JJJJ-MM-TT`.
    public static func day(of date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Noon of `day`, for date pickers.
    public static func date(of day: String) -> Date? {
        guard isDay(day) else { return nil }
        let parts = day.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// A task found on a handwriting page: a drawn box and the line beside it. The ink is the truth;
/// this follows it after every reading. See ADR 0060.
public struct InkTask: Equatable, Sendable, Identifiable, Codable {
    public static let textLimit = 1000
    public static let perPage = 200

    public var id: UUID
    /// Top left corner and size of the box, in page coordinates.
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var text: String
    public var checked: Bool
    public var due: String?

    public init(id: UUID = UUID(), x: Double, y: Double, width: Double, height: Double, text: String, checked: Bool = false, due: String? = nil) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.text = text.clippedUTF16(Self.textLimit)
        self.checked = checked
        self.due = due
    }

    enum CodingKeys: String, CodingKey {
        case id, x, y, width, height, text, checked, due
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = UUID(uuidString: try container.decode(String.self, forKey: .id)) else { throw InkhashError.invalidID }
        self.id = id
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        text = try container.decode(String.self, forKey: .text)
        checked = try container.decode(Bool.self, forKey: .checked)
        due = try container.decodeIfPresent(String.self, forKey: .due).flatMap { TaskDue.isDay($0) ? $0 : nil }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(text, forKey: .text)
        try container.encode(checked, forKey: .checked)
        try container.encodeIfPresent(due, forKey: .due)
    }

    var midX: Double { x + width / 2 }
    var midY: Double { y + height / 2 }

    /// A task read anew keeps the id and due day of the one whose box stood at the same place.
    public static func carryingOver(_ read: [InkTask], from previous: [InkTask]) -> [InkTask] {
        var unclaimed = previous
        return read.map { task in
            var task = task
            let reach = max(task.width, task.height)
            if let index = unclaimed.firstIndex(where: { abs($0.midX - task.midX) < reach && abs($0.midY - task.midY) < reach }) {
                task.id = unclaimed[index].id
                task.due = unclaimed[index].due
                unclaimed.remove(at: index)
            }
            return task
        }
    }
}

/// One task of the list, from a text note or a handwriting page. See ADR 0060.
public struct TaskItem: Identifiable, Equatable, Sendable {
    public enum Place: Hashable, Sendable {
        /// The n-th task of a text note, counted over its checkbox blocks.
        case text(index: Int)
        case ink(page: UUID, task: UUID)
    }

    public var noteID: UUID
    public var noteTitle: String
    public var kind: NoteKind
    public var place: Place
    public var text: String
    public var checked: Bool
    public var due: String?

    public var id: String {
        switch place {
        case .text(let index): "\(noteID.uuidString)/\(index)"
        case .ink(let page, let task): "\(noteID.uuidString)/\(page.uuidString)/\(task.uuidString)"
        }
    }
}

/// All tasks of a workspace, read from its notes each time. Nothing of it is stored. See ADR 0060.
public enum TaskList {
    public enum Group: String, CaseIterable, Sendable {
        case overdue, today, later, undated, done

        public var title: String {
            switch self {
            case .overdue: "Überfällig"
            case .today: "Heute"
            case .later: "Später"
            case .undated: "Ohne Datum"
            case .done: "Erledigt"
            }
        }
    }

    /// The tasks of the notes not in the trash, in the order of the notes given.
    public static func items(in notes: [Note]) -> [TaskItem] {
        notes.filter { $0.deletedAt == nil }.flatMap(items(of:))
    }

    public static func items(of note: Note) -> [TaskItem] {
        switch note.kind {
        case .text:
            let blocks = MarkdownCodec.parse(note.markdown ?? "").filter { $0.type == .checkbox }
            return blocks.enumerated().map { index, block in
                let parts = TaskDue.split(block.plain)
                return TaskItem(
                    noteID: note.id, noteTitle: note.displayTitle, kind: .text, place: .text(index: index),
                    text: parts.text.trimmingCharacters(in: .whitespaces), checked: block.checked, due: parts.due
                )
            }
        case .ink:
            return (note.pages ?? []).flatMap { page in
                page.tasks.map { task in
                    TaskItem(
                        noteID: note.id, noteTitle: note.displayTitle, kind: .ink, place: .ink(page: page.id, task: task.id),
                        text: task.text, checked: task.checked, due: task.due
                    )
                }
            }
        }
    }

    /// Open tasks by due day, the done ones last. Within a group, earlier days first, then the order
    /// of the notes. Empty groups are left out. `today` is a day as `JJJJ-MM-TT`.
    public static func grouped(_ items: [TaskItem], today: String) -> [(group: Group, items: [TaskItem])] {
        var buckets: [Group: [TaskItem]] = [:]
        for item in items {
            buckets[group(of: item, today: today), default: []].append(item)
        }
        return Group.allCases.compactMap { group in
            guard var members = buckets[group], !members.isEmpty else { return nil }
            if group == .overdue || group == .later {
                members = stableSorted(members) { ($0.due ?? "") < ($1.due ?? "") }
            }
            return (group, members)
        }
    }

    public static func group(of item: TaskItem, today: String) -> Group {
        if item.checked { return .done }
        guard let due = item.due else { return .undated }
        if due < today { return .overdue }
        if due == today { return .today }
        return .later
    }

    private static func stableSorted(_ items: [TaskItem], by less: (TaskItem, TaskItem) -> Bool) -> [TaskItem] {
        items.enumerated().sorted { lhs, rhs in
            if less(lhs.element, rhs.element) { return true }
            if less(rhs.element, lhs.element) { return false }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}

extension Note {
    /// Ticks or opens the n-th task of a text note. Returns false if nothing changed.
    @discardableResult
    public mutating func setTextTask(_ index: Int, checked: Bool) -> Bool {
        editTextTask(index) { block in
            guard block.checked != checked else { return false }
            block.checked = checked
            return true
        }
    }

    /// Sets or removes the due day of the n-th task of a text note. Returns false if nothing changed.
    @discardableResult
    public mutating func setTextTask(_ index: Int, due: String?) -> Bool {
        editTextTask(index) { block in
            guard TaskDue.split(block.plain).due != due else { return false }
            block.spans = Self.spans(block.spans, settingDue: due)
            return true
        }
    }

    /// Sets or removes the due day of a task on a handwriting page. Returns false if nothing changed.
    @discardableResult
    public mutating func setInkTask(page pageID: UUID, task taskID: UUID, due: String?) -> Bool {
        editInkTask(page: pageID, task: taskID) { task in
            guard task.due != due else { return false }
            task.due = due
            return true
        }
    }

    /// Marks a handwriting task as ticked or open, while its drawing gets or loses the tick.
    @discardableResult
    public mutating func setInkTask(page pageID: UUID, task taskID: UUID, checked: Bool) -> Bool {
        editInkTask(page: pageID, task: taskID) { task in
            guard task.checked != checked else { return false }
            task.checked = checked
            return true
        }
    }

    public func inkTask(page pageID: UUID, task taskID: UUID) -> InkTask? {
        pages?.first { $0.id == pageID }?.tasks.first { $0.id == taskID }
    }

    private mutating func editTextTask(_ index: Int, _ edit: (inout Block) -> Bool) -> Bool {
        guard kind == .text else { return false }
        var blocks = MarkdownCodec.parse(markdown ?? "")
        let positions = blocks.indices.filter { blocks[$0].type == .checkbox }
        guard positions.indices.contains(index) else { return false }
        guard edit(&blocks[positions[index]]) else { return false }
        return applyMarkdown(MarkdownCodec.serialize(blocks))
    }

    private mutating func editInkTask(page pageID: UUID, task taskID: UUID, _ edit: (inout InkTask) -> Bool) -> Bool {
        guard var pages, let pageIndex = pages.firstIndex(where: { $0.id == pageID }),
              let taskIndex = pages[pageIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        guard edit(&pages[pageIndex].tasks[taskIndex]) else { return false }
        self.pages = pages
        return true
    }

    /// The spans with the due day at the end replaced. The day is plain text in its own span.
    static func spans(_ spans: [InlineSpan], settingDue due: String?) -> [InlineSpan] {
        let plain = spans.map(\.text).joined()
        var kept = spans
        if let range = TaskDue.trailingRange(in: plain)?.whole {
            // Cut the old day off the end, span by span.
            var remaining = (plain as NSString).length - range.location
            while remaining > 0, var last = kept.popLast() {
                let length = (last.text as NSString).length
                if length > remaining {
                    last.text = (last.text as NSString).substring(to: length - remaining)
                    kept.append(last)
                    remaining = 0
                } else {
                    remaining -= length
                }
            }
        }
        guard let due, TaskDue.isDay(due) else { return kept }
        let rest = kept.map(\.text).joined()
        let separator = rest.isEmpty || rest.hasSuffix(" ") ? "" : " "
        kept.append(InlineSpan(text: separator + "\(TaskDue.marker) \(due)"))
        return kept
    }
}
