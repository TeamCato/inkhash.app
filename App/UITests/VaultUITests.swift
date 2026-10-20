import InkhashCore
import XCTest
import KennelKit

/// The vault sheets on the iPhone against a real Kennel, started by `make ui-test`. Skipped without it.
final class VaultUITests: XCTestCase {
    private let keyPlaceholder = "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"

    /// The vault sheet opened from the server's settings stays open until the key is in. It used to
    /// be presented three times at once, and the settings closed with it. See PITFALLS.
    @MainActor
    func testOpenVaultFromSettingsAfterPostponing() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["INKHASH_UI_URL"], let url = URL(string: raw) else {
            throw XCTSkip("no server; run make ui-test")
        }
        let (name, recoveryKey) = try await Self.accountWithVault(url: url, setupToken: env["INKHASH_UI_SETUP"] ?? "")

        let app = XCUIApplication()
        app.launch()
        app.buttons["Einstellungen"].firstMatch.tap()
        app.buttons["Server verbinden"].firstMatch.tap()
        let address = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS %@", "kennel.local")).firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        address.typeText(url.absoluteString + "\n")
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText(name)
        let password = app.secureTextFields["Passwort"]
        password.tap()
        password.typeText("secretsecret")
        app.buttons["Anmelden"].firstMatch.tap()
        dismissPasswordPrompt(app)
        XCTAssertTrue(app.buttons["Tresor öffnen…"].waitForExistence(timeout: 10))

        // Closing the settings brings up the vault prompt; put it off.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let done = app.buttons["Fertig"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        let later = app.buttons["Später"]
        XCTAssertTrue(later.waitForExistence(timeout: 10))
        later.tap()

        app.buttons["Einstellungen"].firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch.tap()
        let open = app.buttons["Tresor öffnen…"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let field = app.textFields[keyPlaceholder]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        sleep(2)
        XCTAssertTrue(field.exists, "the vault sheet closed by itself")

        field.tap()
        field.typeText(recoveryKey.display)
        app.buttons["Öffnen"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Notizen gehen verschlüsselt zum Server."].waitForExistence(timeout: 20))
    }

    /// iOS offers to save the password after signing in.
    @MainActor
    private func dismissPasswordPrompt(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for later in [app.buttons["Später"], springboard.buttons["Später"]] where later.waitForExistence(timeout: 3) {
            later.tap()
        }
    }

    /// A new account with a vault, as if another device had made it.
    private static func accountWithVault(url: URL, setupToken: String) async throws -> (String, RecoveryKey) {
        var setup = URLRequest(url: url.appendingPathComponent("v1/setup"))
        setup.httpMethod = "POST"
        setup.setValue("application/json", forHTTPHeaderField: "Content-Type")
        setup.httpBody = try JSONSerialization.data(withJSONObject: ["setupToken": setupToken, "name": "admin", "password": "adminadmin"])
        _ = try await URLSession.shared.data(for: setup)
        let admin = try await KennelClient(address: url).signIn(name: "admin", password: "adminadmin").token

        let name = "u" + UUID().uuidString.prefix(8).lowercased()
        var create = URLRequest(url: url.appendingPathComponent("v1/accounts"))
        create.httpMethod = "POST"
        create.setValue("application/json", forHTTPHeaderField: "Content-Type")
        create.setValue("Bearer \(admin)", forHTTPHeaderField: "Authorization")
        create.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "password": "secretsecret"])
        let (_, response) = try await URLSession.shared.data(for: create)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 201)

        let token = try await KennelClient(address: url).signIn(name: name, password: "secretsecret").token
        let recoveryKey = RecoveryKey.generate()
        let (_, record) = try VaultCrypto.create(recoveryKey: recoveryKey, rounds: 100_000)
        _ = try await APIClient(baseURL: url, token: token).putVault(record)
        return (name, recoveryKey)
    }
}
