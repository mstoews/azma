import XCTest
@testable import AZMA

/// The app's own checks, which mirror the server's so someone is told what is
/// wrong before a round trip.
final class ValidationTests: XCTestCase {
    private func validJob() -> JobInput {
        var input = JobInput()
        input.title = "Portfolio Manager"
        input.company = "Nippon Asset Management"
        return input
    }

    func testDraftNeedsTitleAndCompany() {
        var input = JobInput()
        XCTAssertNotNil(input.problem)
        input.title = "PM"
        XCTAssertNotNil(input.problem)
        input.company = "Client"
        XCTAssertNil(input.problem)
    }

    func testSubmittingNeedsADescription() {
        var input = validJob()
        input.submit = true
        XCTAssertNotNil(input.problem, "a posting sent for review needs a description")
        input.description = String(repeating: "Detail about the mandate. ", count: 3)
        XCTAssertNil(input.problem)
    }

    func testSalaryRangeIsChecked() {
        var input = validJob()
        input.salaryMin = 30_000_000
        input.salaryMax = 10_000_000
        input.salaryCurrency = "JPY"
        XCTAssertNotNil(input.problem)

        input.salaryMax = 40_000_000
        XCTAssertNil(input.problem)

        input.salaryCurrency = ""
        XCTAssertNotNil(input.problem, "a range without a currency cannot be shown")
    }

    func testInquiryValidation() {
        var input = InquiryInput()
        XCTAssertNotNil(input.problem)
        input.name = "Hiro Sato"
        input.email = "not-an-email"
        XCTAssertNotNil(input.problem)
        input.email = "hiro@example.com"
        XCTAssertNotNil(input.problem, "a message is required")
        input.message = "We are building a Tokyo PE team."
        XCTAssertNil(input.problem)
    }

    func testCandidateProfileCompleteness() {
        var profile = CandidateProfile()
        XCTAssertEqual(profile.completeness.done, 0)
        XCTAssertNotNil(profile.problem)

        profile.fullName = "Kenji Watanabe"
        profile.headline = "Equity PM"
        profile.summary = "Ten years running Japanese equities."
        profile.location = "Tokyo"
        profile.currentTitle = "Senior Analyst"
        profile.yearsExperience = 12
        profile.sectors = ["Asset Management"]
        profile.desiredRoles = ["Portfolio Manager"]

        let progress = profile.completeness
        XCTAssertEqual(progress.done, progress.total)
        XCTAssertNil(profile.problem)
    }

    func testApplicationStateWording() {
        XCTAssertTrue(ApplicationState.shortlisted.isOpen)
        XCTAssertFalse(ApplicationState.withdrawn.isOpen)
        XCTAssertFalse(ApplicationState.placed.isOpen)
        XCTAssertEqual(ApplicationState.under_review.label, "Under review")
    }

    func testJobStatusWording() {
        XCTAssertEqual(JobStatus.pending.label, "In review")
        XCTAssertEqual(JobStatus.published.label, "Live")
        XCTAssertFalse(JobStatus.draft.explanation.isEmpty)
    }
}
