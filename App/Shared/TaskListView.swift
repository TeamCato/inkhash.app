import InkhashCore
import SwiftUI

/// All tasks of the workspace on one sheet, read from the notes each time. Ticking and dating act
/// on the note a task comes from; its text opens that note. See ADR 0060.
struct TaskListView: View {
    @Environment(AppModel.self) private var model
    @State private var showsDone = false
    @State private var compact = false

    var body: some View {
        let today = TaskDue.day(of: Date())
        let items = TaskList.items(in: model.library.records.map(\.note))
        let groups = TaskList.grouped(items, today: today)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Aufgaben")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(Ink.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(summary(items))
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.muted)
                    .padding(.top, 4)
                    .padding(.bottom, 18)
                if items.isEmpty {
                    Text("Noch keine Aufgaben. Ein Kästchen im Text (`[ ] ` am Zeilenanfang) oder ein gemaltes Kästchen vor einer Zeile in der Handschrift landet hier.")
                        .font(.system(size: 15))
                        .foregroundStyle(Ink.muted)
                }
                ForEach(groups, id: \.group) { entry in
                    section(entry.group, entry.items, today: today)
                }
            }
            .padding(.horizontal, compact ? 16 : 36)
            .padding(.top, compact ? 16 : 30)
            .padding(.bottom, 60)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Paper.standard.fill.ignoresSafeArea())
        .compactWidth($compact)
        .navigationTitle("")
    }

    private func summary(_ items: [TaskItem]) -> String {
        let open = items.filter { !$0.checked }.count
        let name = model.registry.current.name
        switch open {
        case 0: return "\(name) · nichts offen"
        case 1: return "\(name) · 1 offen"
        default: return "\(name) · \(open) offen"
        }
    }

    @ViewBuilder
    private func section(_ group: TaskList.Group, _ items: [TaskItem], today: String) -> some View {
        if group == .done {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showsDone.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(showsDone ? 90 : 0))
                    Text("\(group.title) (\(items.count))")
                }
                .groupTitle()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showsDone ? "aufgeklappt" : "zugeklappt")
            if showsDone {
                rows(items, today: today)
            }
        } else {
            Text(group.title)
                .groupTitle()
                .foregroundStyle(group == .overdue ? Ink.accent : Ink.muted)
            rows(items, today: today)
        }
    }

    private func rows(_ items: [TaskItem], today: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(items) { item in
                TaskRow(item: item, today: today)
            }
        }
        .padding(.bottom, 14)
    }
}

private extension View {
    func groupTitle() -> some View {
        font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Ink.muted)
            .textCase(.uppercase)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }
}

/// One task: its box, its text with the note below, and its due day.
private struct TaskRow: View {
    @Environment(AppModel.self) private var model
    var item: TaskItem
    var today: String
    @State private var picksDue = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                model.library.setTask(item, checked: !item.checked)
            } label: {
                Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(item.checked ? Ink.accent : Ink.muted)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.checked ? "Erledigt" : "Offen")
            .accessibilityHint(item.checked ? "Wieder öffnen" : "Abhaken")
            Button {
                model.selectedID = item.noteID
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.text.isEmpty ? "Ohne Text" : item.text)
                        .font(.system(size: 16))
                        .foregroundStyle(item.checked ? Ink.muted : Ink.ink)
                        .strikethrough(item.checked, color: Ink.muted)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        Image(systemName: item.kind == .ink ? "pencil.tip" : "doc.text")
                            .font(.system(size: 10))
                        Text(item.noteTitle)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Notiz öffnen")
            DueChip(due: item.due, today: today, open: !item.checked) { picksDue = true }
                .popover(isPresented: $picksDue) {
                    DuePicker(due: item.due) { day in
                        picksDue = false
                        model.library.setTask(item, due: day)
                    }
                }
        }
        .padding(.vertical, 7)
    }
}

/// The due day of a task as a small capsule, or "Fällig…" to set one.
struct DueChip: View {
    var due: String?
    var today: String
    var open = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .medium))
                Text(due.map { DueText.short($0, today: today) } ?? "Fällig…")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .inkSurface(in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(due.map { "Fällig \(DueText.short($0, today: today))" } ?? "Fälligkeit setzen")
    }

    private var color: Color {
        guard let due, open else { return Ink.muted }
        return due <= today ? Ink.accent : Ink.ink
    }
}

/// Beside a task in the text editor: "Fällig…" while it has no day, a calendar to change the day
/// that stands in the line. See ADR 0060.
struct TaskDueButton: View {
    var due: String?
    var choose: (String?) -> Void
    @State private var picks = false

    var body: some View {
        Button { picks = true } label: {
            Group {
                if due == nil {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10, weight: .medium))
                        Text("Fällig…")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                } else {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 24)
                }
            }
            .foregroundStyle(Ink.accent)
            .frame(height: 24)
            .inkSurface(in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(due == nil ? "Fälligkeit setzen" : "Fälligkeit ändern")
        .popover(isPresented: $picks) {
            DuePicker(due: due) { day in
                picks = false
                choose(day)
            }
        }
    }
}

/// Today, tomorrow, in a week or a day from the calendar; or no day at all. See ADR 0060.
struct DuePicker: View {
    var due: String?
    var choose: (String?) -> Void
    @State private var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                quick("Heute", days: 0)
                quick("Morgen", days: 1)
                quick("In einer Woche", days: 7)
            }
            DatePicker("Fällig am", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "de_DE"))
            HStack {
                if due != nil {
                    Button("Entfernen", role: .destructive) { choose(nil) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Ink.muted)
                }
                Spacer()
                Button("Übernehmen") { choose(TaskDue.day(of: date)) }
                    .inkButton()
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            if let due, let current = TaskDue.date(of: due) { date = current }
        }
    }

    private func quick(_ title: String, days: Int) -> some View {
        Button(title) {
            let day = TaskDue.calendar.date(byAdding: .day, value: days, to: Date()) ?? Date()
            choose(TaskDue.day(of: day))
        }
        .font(.system(size: 13, weight: .medium))
        .buttonStyle(.plain)
        .foregroundStyle(Ink.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .inkSurface(in: Capsule())
    }
}

/// A due day in words: Heute, Morgen, Gestern, otherwise "20. Okt.", with the year if it is another.
enum DueText {
    static func short(_ due: String, today: String) -> String {
        guard let date = TaskDue.date(of: due), let now = TaskDue.date(of: today) else { return due }
        let days = TaskDue.calendar.dateComponents([.day], from: now, to: date).day ?? 0
        // Shown in the device's own calendar and language.
        let calendar = Calendar.current
        switch days {
        case 0: return "Heute"
        case 1: return "Morgen"
        case -1: return "Gestern"
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "de_DE")
            formatter.calendar = calendar
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            formatter.setLocalizedDateFormatFromTemplate(sameYear ? "dMMM" : "dMMMyyyy")
            return formatter.string(from: date)
        }
    }
}
