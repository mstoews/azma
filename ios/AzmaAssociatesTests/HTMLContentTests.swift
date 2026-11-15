import XCTest
@testable import AZMA

/// The CMS stores pages as WordPress-era HTML; these are excerpts of the real
/// thing from the AZMA site.
final class HTMLContentTests: XCTestCase {
    func testParsesHeadingsParagraphsAndLists() {
        let html = """
        <p class="wp-block-paragraph">In order to satisfy our clients, we work in restricted fields.</p>
        <ul class="wp-block-list">
        <li>Asset Management</li>
        <li>M&amp;A</li>
        </ul>
        <p class="wp-block-paragraph"></p>
        """
        let blocks = HTMLContent.parse(html)
        XCTAssertEqual(blocks.count, 2, "the empty trailing paragraph should be dropped")

        guard case let .paragraph(text) = blocks[0] else { return XCTFail("expected a paragraph") }
        XCTAssertEqual(String(text.characters), "In order to satisfy our clients, we work in restricted fields.")

        guard case let .bullets(items) = blocks[1] else { return XCTFail("expected a list") }
        XCTAssertEqual(items.map { String($0.characters) }, ["Asset Management", "M&A"])
    }

    func testHeadingWithLineBreaks() {
        let html = #"<h2 class="wp-block-heading">鵜飼 重和<br>Managing Director / Consultant<br>Singapore</h2>"#
        guard case let .heading(level, text)? = HTMLContent.parse(html).first else {
            return XCTFail("expected a heading")
        }
        XCTAssertEqual(level, 2)
        XCTAssertEqual(String(text.characters), "鵜飼 重和\nManaging Director / Consultant\nSingapore")
    }

    func testDecodesEntities() {
        XCTAssertEqual(HTMLContent.decodeEntities("Bachelor&#8217;s Degree"), "Bachelor’s Degree")
        XCTAssertEqual(HTMLContent.decodeEntities("M&amp;A &lt;tag&gt;"), "M&A <tag>")
        XCTAssertEqual(HTMLContent.decodeEntities("&#x5e74;"), "年")
        XCTAssertEqual(HTMLContent.decodeEntities("100% &unknown; raw"), "100% &unknown; raw")
    }

    func testKeepsEmphasisAndLinks() {
        let html = #"<p>Contact <strong>us</strong> at <a href="https://example.com/x">example</a>.</p>"#
        guard case let .paragraph(text)? = HTMLContent.parse(html).first else {
            return XCTFail("expected a paragraph")
        }
        XCTAssertEqual(String(text.characters), "Contact us at example.")

        let hasBold = text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
        XCTAssertTrue(hasBold, "<strong> should survive as emphasis")

        let link = text.runs.compactMap(\.link).first
        XCTAssertEqual(link?.absoluteString, "https://example.com/x")
    }

    func testUnwrappedTextStillRenders() {
        let blocks = HTMLContent.parse("Just some text, no tags at all.")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(HTMLContent.plainText("Just some text, no tags at all."), "Just some text, no tags at all.")
    }

    func testEmptyInputProducesNothing() {
        XCTAssertTrue(HTMLContent.parse("").isEmpty)
        XCTAssertTrue(HTMLContent.parse("<p></p><p>&nbsp;</p>").isEmpty)
    }

    func testPlainTextTruncates() {
        let html = "<p>" + String(repeating: "word ", count: 50) + "</p>"
        let text = HTMLContent.plainText(html, limit: 20)
        XCTAssertTrue(text.hasSuffix("…"))
        XCTAssertLessThanOrEqual(text.count, 21)
    }
}
