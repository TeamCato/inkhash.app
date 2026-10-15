import CoreGraphics
import XCTest
@testable import InkhashCore

final class TaskDueTests: XCTestCase {
    func testTheDayAtTheEndIsTheDueDay() {
        XCTAssertEqual(TaskDue.split("Angebot schicken 📅 2026-10-20").text, "Angebot schicken")
        XCTAssertEqual(TaskDue.split("Angebot schicken 📅 2026-10-20").due, "2026-10-20")
        XCTAssertEqual(TaskDue.split("Angebot schicken 📅2026-10-20 ").due, "2026-10-20")
    }

    func testADayInTheMiddleOrAnImpossibleDayIsText() {
        XCTAssertNil(TaskDue.split("📅 2026-10-20 Angebot").due)
        XCTAssertNil(TaskDue.split("Angebot 📅 2026-02-30").due)
        XCTAssertNil(TaskDue.split("Angebot 2026-10-20").due)
    }

    /// Days are Gregorian whatever calendar the device shows. Reviewer finding.
    func testDaysAreGregorianAndRoundTrip() throws {
        let date = try XCTUnwrap(TaskDue.date(of: "2026-10-14"))
        XCTAssertEqual(TaskDue.day(of: date), "2026-10-14")
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = .current
        XCTAssertEqual(buddhist.component(.year, from: date), 2569, "the same moment in another calendar")
        XCTAssertEqual(TaskDue.calendar.identifier, .gregorian)
    }

    func testSettingReplacesOrRemovesTheDay() {
        XCTAssertEqual(TaskDue.setting("2026-10-21", in: "Angebot 📅 2026-10-20"), "Angebot 📅 2026-10-21")
        XCTAssertEqual(TaskDue.setting("2026-10-21", in: "Angebot"), "Angebot 📅 2026-10-21")
        XCTAssertEqual(TaskDue.setting(nil, in: "Angebot 📅 2026-10-20"), "Angebot")
    }
}

final class TaskListTests: XCTestCase {
    private func text(_ markdown: String, title: String = "") -> Note {
        var note = Note.newText(now: "2026-10-01T08:00:00Z")
        note.applyMarkdown(markdown)
        if !title.isEmpty { note.setTitle(title) }
        return note
    }

    func testTextTasksWithTheirDays() {
        let note = text("# Woche\n- [ ] Angebot 📅 2026-10-20\n- [x] Rechnung\n- Liste\n")
        let items = TaskList.items(in: [note])
        XCTAssertEqual(items.map(\.text), ["Angebot", "Rechnung"])
        XCTAssertEqual(items.map(\.due), ["2026-10-20", nil])
        XCTAssertEqual(items.map(\.checked), [false, true])
        XCTAssertEqual(items.map(\.place), [.text(index: 0), .text(index: 1)])
        XCTAssertEqual(items.first?.noteTitle, "Woche")
    }

    func testTrashedNotesHaveNoTasks() {
        var note = text("- [ ] Angebot\n")
        note.deletedAt = "2026-10-02T08:00:00Z"
        XCTAssertTrue(TaskList.items(in: [note]).isEmpty)
    }

    func testGroupsByDayAndDoneLast() {
        let note = text("""
        - [ ] Später 📅 2026-10-30
        - [ ] Ohne
        - [x] Fertig 📅 2026-10-01
        - [ ] Heute 📅 2026-10-14
        - [ ] Spät dran 📅 2026-10-10
        - [ ] Früher 📅 2026-10-20

        """)
        let groups = TaskList.grouped(TaskList.items(in: [note]), today: "2026-10-14")
        XCTAssertEqual(groups.map(\.group), [.overdue, .today, .later, .undated, .done])
        XCTAssertEqual(groups[2].items.map(\.text), ["Früher", "Später"])
    }

    func testTickingAndDatingATextTaskWritesTheMarkdown() {
        var note = text("- [ ] Angebot\n- [ ] Rechnung 📅 2026-10-20\n")
        XCTAssertTrue(note.setTextTask(1, checked: true))
        XCTAssertEqual(note.markdown, "- [ ] Angebot\n- [x] Rechnung 📅 2026-10-20\n")
        XCTAssertFalse(note.setTextTask(1, checked: true))
        XCTAssertTrue(note.setTextTask(0, due: "2026-11-01"))
        XCTAssertEqual(note.markdown, "- [ ] Angebot 📅 2026-11-01\n- [x] Rechnung 📅 2026-10-20\n")
        XCTAssertTrue(note.setTextTask(1, due: nil))
        XCTAssertEqual(note.markdown, "- [ ] Angebot 📅 2026-11-01\n- [x] Rechnung\n")
        XCTAssertFalse(note.setTextTask(5, checked: true))
    }

    func testDatingKeepsStyledText() {
        var note = text("- [ ] **Angebot** schicken\n")
        XCTAssertTrue(note.setTextTask(0, due: "2026-11-01"))
        XCTAssertEqual(note.markdown, "- [ ] **Angebot** schicken 📅 2026-11-01\n")
    }

    func testInkTasksAreListedAndKeepTheirDayOverAReading() {
        let task = InkTask(x: 40, y: 100, width: 20, height: 20, text: "Milch")
        var note = Note.newInk(page: InkPage(blob: "a", tasks: [task]), now: "2026-10-01T08:00:00Z")
        let page = note.pages![0].id
        XCTAssertTrue(note.setInkTask(page: page, task: task.id, due: "2026-10-15"))
        let reread = InkTask(x: 41, y: 101, width: 19, height: 21, text: "Milch kaufen", checked: true)
        XCTAssertTrue(note.applyInkReading(pageID: page, transcript: "Milch kaufen", tags: [], tasks: [reread], pageHasInk: true))
        let items = TaskList.items(of: note)
        XCTAssertEqual(items.map(\.text), ["Milch kaufen"])
        XCTAssertEqual(items.first?.due, "2026-10-15")
        XCTAssertEqual(items.first?.checked, true)
        XCTAssertEqual(items.first?.place, .ink(page: page, task: task.id))
    }

    func testInkTasksSurviveJSON() throws {
        let task = InkTask(x: 40, y: 100, width: 20, height: 20, text: "Milch", checked: true, due: "2026-10-15")
        let page = InkPage(blob: "a", tasks: [task])
        let decoded = try InkhashJSON.decode(InkPage.self, from: InkhashJSON.encode(page))
        XCTAssertEqual(decoded.tasks, [task])
    }
}

final class TaskBoxTests: XCTestCase {
    /// A box drawn in one stroke, starting top left, clockwise, a little wobbly.
    private func square(_ rect: CGRect, steps: Int = 10) -> [CGPoint] {
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.minY + 1),
        ]
        var points: [CGPoint] = []
        for (from, to) in zip(corners, corners.dropFirst()) {
            for step in 0..<steps {
                let t = CGFloat(step) / CGFloat(steps)
                points.append(CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t + (step.isMultiple(of: 2) ? 0.4 : -0.4)))
            }
        }
        points.append(corners.last!)
        return points
    }

    private func circle(center: CGPoint, radius: CGFloat) -> [CGPoint] {
        (0...40).map { step in
            let angle = CGFloat(step) / 40 * 2 * .pi
            return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
    }

    private func line(_ from: CGPoint, _ to: CGPoint) -> [CGPoint] {
        (0...10).map { step in
            let t = CGFloat(step) / 10
            return CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        }
    }

    func testASmallSquareIsABoxAndACircleOrALineIsNot() {
        XCTAssertNotNil(TaskBoxes.box(square(CGRect(x: 40, y: 100, width: 20, height: 20))))
        XCTAssertNil(TaskBoxes.box(circle(center: CGPoint(x: 50, y: 110), radius: 10)))
        XCTAssertNil(TaskBoxes.box(line(CGPoint(x: 40, y: 100), CGPoint(x: 90, y: 100))))
    }

    func testAFrameInASketchIsNoBox() {
        XCTAssertNil(TaskBoxes.box(square(CGRect(x: 40, y: 100, width: 200, height: 150))))
        XCTAssertNil(TaskBoxes.box(square(CGRect(x: 40, y: 100, width: 20, height: 50))))
    }

    func testAStrokeInsideTicksTheBoxAndBothStayOutOfTheText() {
        let box = CGRect(x: 40, y: 100, width: 20, height: 20)
        let strokes = [
            square(box),
            TaskBoxes.tick(in: box),
            line(CGPoint(x: 80, y: 110), CGPoint(x: 200, y: 112)),
        ]
        let marks = TaskBoxes.marks(in: strokes)
        XCTAssertEqual(marks.boxes.count, 1)
        XCTAssertEqual(marks.ticked, [true])
        XCTAssertEqual(marks.strokes, [0, 1])
    }

    func testTheLineBesideTheBoxIsTheTask() {
        let size = CGSize(width: 768, height: 1024)
        let box = CGRect(x: 40, y: 100, width: 20, height: 20)
        let marks = TaskBoxes.marks(in: [square(box)])
        let lines = [
            RecognizedWord(text: "Milch kaufen", minX: 80 / 768, minY: 96 / 1024, maxX: 300 / 768, maxY: 124 / 1024),
            RecognizedWord(text: "Andere Zeile", minX: 80 / 768, minY: 200 / 1024, maxX: 300 / 768, maxY: 228 / 1024),
        ]
        let tasks = TaskBoxes.tasks(marks, lines: lines, size: size)
        XCTAssertEqual(tasks.map(\.text), ["Milch kaufen"])
        XCTAssertEqual(tasks.first?.checked, false)
        XCTAssertEqual(tasks.first?.x ?? 0, 40, accuracy: 1)
    }

    func testABoxWithoutALineIsNoTask() {
        let marks = TaskBoxes.marks(in: [square(CGRect(x: 40, y: 100, width: 20, height: 20))])
        XCTAssertTrue(TaskBoxes.tasks(marks, lines: [], size: CGSize(width: 768, height: 1024)).isEmpty)
    }

    func testOpeningFindsTheTicksButNotTheBoxOrTheText() {
        let box = CGRect(x: 40, y: 100, width: 20, height: 20)
        let strokes = [square(box), line(CGPoint(x: 80, y: 110), CGPoint(x: 200, y: 112)), TaskBoxes.tick(in: box)]
        XCTAssertEqual(TaskBoxes.ticks(in: strokes, box: box), [2])
    }

    func testTheDrawnTickIsReadAsATick() {
        let box = CGRect(x: 40, y: 100, width: 20, height: 20)
        let marks = TaskBoxes.marks(in: [square(box), TaskBoxes.tick(in: box)])
        XCTAssertEqual(marks.ticked, [true])
    }
}
