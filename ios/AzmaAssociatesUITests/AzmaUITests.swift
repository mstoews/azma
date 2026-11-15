import XCTest

/// End-to-end passes through the app against a local server.
///
/// Start the stack first, from the repo root:
///
///     cd server && go run ./cmd/devdb          # terminal 1
///     DB_SOURCE=… go run ./cmd/server          # terminal 2
///
/// and seed the demo accounts (ios/README.md lists them). Without a server on
/// :8080 these tests skip rather than fail, so they stay usable on a machine
/// that only has the app checked out.
final class AzmaUITests: XCTestCase {
    private let baseURL = "http://localhost:8080"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchApp() throws -> XCUIApplication {
        try XCTSkipUnless(serverIsUp(), "No AZMA server on \(baseURL)")
        let app = XCUIApplication()
        app.launchArguments = ["-azma.apiBaseURL", baseURL]
        app.launch()
        return app
    }

    private func serverIsUp() -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/health") else { return false }
        let semaphore = DispatchSemaphore(value: 0)
        var reachable = false
        URLSession.shared.dataTask(with: url) { _, response, _ in
            reachable = (response as? HTTPURLResponse)?.statusCode == 200
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 5)
        return reachable
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func signIn(_ app: XCUIApplication, email: String, password: String) {
        app.tabBars.buttons["Account"].tap()
        let signIn = app.buttons["Sign in"].firstMatch
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        signIn.tap()

        let emailField = app.textFields["you@example.com"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText(password)

        app.buttons["Sign in"].firstMatch.tap()
    }

    /// The public side: the firm, the board, a position, and the contact form.
    func testPublicTour() throws {
        let app = try launchApp()

        XCTAssertTrue(app.staticTexts["AZMA & Associates"].firstMatch.waitForExistence(timeout: 10))
        capture(app, "01-firm")

        app.tabBars.buttons["Positions"].tap()
        XCTAssertTrue(app.staticTexts["Portfolio Manager, Japan Equities"].waitForExistence(timeout: 10),
                      "the published position should be on the board")
        XCTAssertTrue(app.staticTexts["Confidential client"].exists,
                      "a confidential client must not be named on the board")
        capture(app, "02-positions")

        app.staticTexts["Portfolio Manager, Japan Equities"].tap()
        XCTAssertTrue(app.staticTexts["About the position"].waitForExistence(timeout: 5))
        capture(app, "03-position-detail")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Contact"].tap()
        XCTAssertTrue(app.buttons["Send to AZMA"].waitForExistence(timeout: 5))
        capture(app, "04-contact")

        app.tabBars.buttons["Join"].tap()
        XCTAssertTrue(app.staticTexts["Join AZMA & Associates"].waitForExistence(timeout: 5))
        capture(app, "05-join")
    }

    /// A candidate: their profile, resume and applications.
    func testCandidateTour() throws {
        let app = try launchApp()
        signIn(app, email: "kenji.watanabe@example.com", password: "a long enough password")

        app.tabBars.buttons["My career"].tap()
        XCTAssertTrue(app.staticTexts["Kenji Watanabe"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Representation"].exists)
        capture(app, "06-candidate-home")

        app.swipeUp()
        app.swipeUp()
        capture(app, "07-candidate-applications")
    }

    /// A client: their company, postings and the review feedback on one.
    func testEmployerTour() throws {
        let app = try launchApp()
        signIn(app, email: "aiko.tanaka@nippon-asset.example", password: "a long enough password")

        app.tabBars.buttons["Hiring"].tap()
        XCTAssertTrue(app.staticTexts["Nippon Asset Management"].firstMatch.waitForExistence(timeout: 10))
        capture(app, "08-employer-home")

        app.swipeUp()
        capture(app, "09-employer-postings")

        // The client sees who applied, but not who they are: a candidate's
        // identity is released only once a consultant has presented them.
        let applicants = app.buttons.containing(NSPredicate(format: "label CONTAINS 'applicant'")).firstMatch
        XCTAssertTrue(applicants.waitForExistence(timeout: 5))
        applicants.tap()
        XCTAssertTrue(app.staticTexts["Applicants"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Kenji Watanabe"].exists,
                       "an un-presented candidate must not be named to the client")
        XCTAssertTrue(app.staticTexts["Portfolio Manager, Japan Equities"].firstMatch.exists)
        capture(app, "09b-employer-applicants")
    }

    /// A consultant: the review queue, the candidates and the inbox.
    func testConsultantTour() throws {
        let app = try launchApp()
        signIn(app, email: "consultant@azma-associates.com", password: "consultant password 2026")

        app.tabBars.buttons["Desk"].tap()
        XCTAssertTrue(app.buttons["Candidates"].waitForExistence(timeout: 10))
        capture(app, "10-desk-postings")

        app.buttons["Candidates"].tap()
        XCTAssertTrue(app.staticTexts["Kenji Watanabe"].firstMatch.waitForExistence(timeout: 10))
        capture(app, "11-desk-candidates")

        app.buttons["Requests"].tap()
        XCTAssertTrue(app.staticTexts["Hiro Sato"].waitForExistence(timeout: 10))
        capture(app, "12-desk-requests")
    }
}
