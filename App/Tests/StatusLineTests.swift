import XCTest
@testable import Inkhash

@MainActor
final class StatusLineTests: XCTestCase {
    func testRoutineMessagesLeaveTheLogo() {
        XCTAssertTrue(StatusLine.isRoutine(""))
        XCTAssertTrue(StatusLine.isRoutine(StatusLine.localOnly))
        XCTAssertTrue(StatusLine.isRoutine(StatusLine.synced))
    }

    func testProblemsAndNewsAreShown() {
        XCTAssertFalse(StatusLine.isRoutine("Konflikt mit Kennel."))
        XCTAssertFalse(StatusLine.isRoutine("Der Import ist fehlgeschlagen."))
        XCTAssertFalse(StatusLine.isRoutine(StatusLine.describe(URLError(.notConnectedToInternet))))
    }
}
