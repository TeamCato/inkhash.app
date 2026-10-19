import XCTest

/// The task list on the iPhone, where the split view is a stack. Needs no server.
final class TaskListUITests: XCTestCase {
    /// The tasks button pushes the list over the tree, and does so again after going back. It used
    /// to change only the hidden detail column. See PITFALLS.
    @MainActor
    func testTheTasksButtonOpensTheListOnTheIPhone() {
        let app = XCUIApplication()
        app.launch()
        let summary = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", " · ")).firstMatch
        for _ in 0..<2 {
            let tasks = app.buttons["Aufgaben"].firstMatch
            XCTAssertTrue(tasks.waitForExistence(timeout: 5))
            tasks.tap()
            XCTAssertTrue(summary.waitForExistence(timeout: 5), "the task list did not open")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(tasks.waitForExistence(timeout: 5))
        }
    }
}
