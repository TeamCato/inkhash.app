import XCTest
@testable import InkhashCore

final class PasswordChangeTests: XCTestCase {
    func testAGoodChangePasses() {
        XCTAssertNil(PasswordChange.problem(current: "altesalt", new: "neuesneu", repeated: "neuesneu"))
    }

    func testEachProblemIsNamed() {
        XCTAssertEqual(PasswordChange.problem(current: "", new: "neuesneu", repeated: "neuesneu"), "Das bisherige Passwort fehlt.")
        XCTAssertEqual(PasswordChange.problem(current: "altesalt", new: "kurz", repeated: "kurz"), "Das neue Passwort braucht mindestens 8 Zeichen.")
        let long = String(repeating: "x", count: 201)
        XCTAssertEqual(PasswordChange.problem(current: "altesalt", new: long, repeated: long), "Das neue Passwort hat höchstens 200 Zeichen.")
        XCTAssertEqual(PasswordChange.problem(current: "altesalt", new: "neuesneu", repeated: "neuesnei"), "Die Wiederholung passt nicht.")
        XCTAssertEqual(PasswordChange.problem(current: "gleichgleich", new: "gleichgleich", repeated: "gleichgleich"), "Das neue Passwort ist das alte.")
    }
}
