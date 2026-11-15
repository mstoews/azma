import XCTest
@testable import AZMA

final class FormattingTests: XCTestCase {
    func testSalaryRanges() {
        XCTAssertEqual(Format.salary(min: 25_000_000, max: 35_000_000, currency: "JPY"), "¥25,000,000 – ¥35,000,000")
        XCTAssertEqual(Format.salary(min: 120_000, max: nil, currency: "SGD"), "From S$120,000")
        XCTAssertEqual(Format.salary(min: nil, max: 90_000, currency: "USD"), "Up to US$90,000")
        XCTAssertNil(Format.salary(min: nil, max: nil, currency: "JPY"))
    }

    func testSalaryWithoutAKnownSymbolNamesTheCurrency() {
        XCTAssertEqual(Format.salary(min: 1000, max: nil, currency: "CHF"), "From 1,000 CHF")
    }

    func testEmploymentTypeLabels() {
        XCTAssertEqual(Format.employmentType("full_time"), "Full-time")
        XCTAssertEqual(Format.employmentType("internship"), "Internship")
        XCTAssertEqual(Format.employmentType("something_new"), "Something New")
    }

    func testExperienceWording() {
        XCTAssertEqual(Format.experience(0), "Experience not given")
        XCTAssertEqual(Format.experience(1), "1 year of experience")
        XCTAssertEqual(Format.experience(12), "12 years of experience")
    }

    func testRelativeDates() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(Format.relative(now.addingTimeInterval(-10), now: now), "Just now")
        XCTAssertTrue(Format.relative(now.addingTimeInterval(-2 * 24 * 3600), now: now).contains("2 days"))
        // Older than a week falls back to a date, which has no "ago" in it.
        XCTAssertFalse(Format.relative(now.addingTimeInterval(-40 * 24 * 3600), now: now).contains("ago"))
    }

    func testEmailValidation() {
        for good in ["kenji@example.com", "a.b+c@sub.example.co.jp"] {
            XCTAssertTrue(good.isValidEmail, good)
        }
        for bad in ["", "nobody", "no@domain", "two @spaces.com", "@example.com"] {
            XCTAssertFalse(bad.isValidEmail, bad)
        }
    }

    func testTrimmedHelpers() {
        XCTAssertEqual("  hello \n".trimmed, "hello")
        XCTAssertNil("   ".nilIfBlank)
        XCTAssertEqual(" x ".nilIfBlank, "x")
    }
}
