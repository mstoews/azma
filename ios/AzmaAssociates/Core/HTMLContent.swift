import Foundation

/// Pages and consultant biographies are stored in the CMS as the HTML the web
/// site renders. The app does not host a web view for them: this turns that
/// HTML into blocks SwiftUI can lay out with the app's own typography.
///
/// The CMS produces a small, known set of tags (h2, h3, p, ul/li, br, a,
/// strong/em). Anything else is reduced to its text rather than dropped.
enum HTMLBlock: Hashable, Sendable {
    case heading(level: Int, text: AttributedString)
    case paragraph(AttributedString)
    case bullets([AttributedString])
}

enum HTMLContent {
    /// Block-level elements, in document order. Empty blocks — which the CMS
    /// leaves behind in quantity — are dropped.
    static func parse(_ html: String) -> [HTMLBlock] {
        guard !html.trimmed.isEmpty else { return [] }
        var blocks: [HTMLBlock] = []

        let pattern = #"<(h2|h3|h4|p|ul|ol)\b[^>]*>(.*?)</\1\s*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return [.paragraph(inline(html))]
        }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))

        if matches.isEmpty {
            let text = inline(html)
            return text.characters.isEmpty ? [] : [.paragraph(text)]
        }

        for match in matches {
            let tag = ns.substring(with: match.range(at: 1)).lowercased()
            let body = ns.substring(with: match.range(at: 2))
            switch tag {
            case "ul", "ol":
                let items = listItems(body)
                if !items.isEmpty { blocks.append(.bullets(items)) }
            case "p":
                let text = inline(body)
                if !text.characters.isEmpty { blocks.append(.paragraph(text)) }
            default:
                let text = inline(body)
                if !text.characters.isEmpty {
                    let level = Int(tag.dropFirst()) ?? 2
                    blocks.append(.heading(level: level, text: text))
                }
            }
        }
        return blocks
    }

    /// The text of the first paragraph, for previews and accessibility labels.
    static func plainText(_ html: String, limit: Int = .max) -> String {
        let text = parse(html).compactMap { block -> String? in
            switch block {
            case let .paragraph(value), let .heading(_, value): return String(value.characters)
            case let .bullets(items): return items.map { String($0.characters) }.joined(separator: ", ")
            }
        }.joined(separator: "\n\n")
        return text.count > limit ? String(text.prefix(limit)).trimmed + "…" : text
    }

    // MARK: - Inline runs

    private static func listItems(_ html: String) -> [AttributedString] {
        guard let regex = try? NSRegularExpression(pattern: #"<li\b[^>]*>(.*?)</li\s*>"#,
                                                   options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
            .map { inline(ns.substring(with: $0.range(at: 1))) }
            .filter { !$0.characters.isEmpty }
    }

    /// Converts one block's inner HTML into styled text.
    private static func inline(_ html: String) -> AttributedString {
        var result = AttributedString()
        var bold = 0, italic = 0
        var link: URL?
        var pending = ""

        func flush() {
            guard !pending.isEmpty else { return }
            var run = AttributedString(decodeEntities(pending))
            if bold > 0 { run.inlinePresentationIntent = .stronglyEmphasized }
            if italic > 0 {
                run.inlinePresentationIntent = bold > 0 ? [.stronglyEmphasized, .emphasized] : .emphasized
            }
            if let link { run.link = link }
            result.append(run)
            pending = ""
        }

        var index = html.startIndex
        while index < html.endIndex {
            let character = html[index]
            guard character == "<" else {
                pending.append(character)
                index = html.index(after: index)
                continue
            }
            guard let close = html[index...].firstIndex(of: ">") else {
                pending.append(contentsOf: html[index...])
                break
            }
            let tag = String(html[html.index(after: index)..<close])
            flush()
            apply(tag: tag, bold: &bold, italic: &italic, link: &link, into: &result)
            index = html.index(after: close)
        }
        flush()

        // Collapse the runs of whitespace the CMS leaves between tags.
        return trimWhitespace(result)
    }

    private static func apply(
        tag: String, bold: inout Int, italic: inout Int, link: inout URL?, into result: inout AttributedString
    ) {
        let name = tag.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "/" })
            .first.map(String.init)?.lowercased() ?? ""
        let closing = tag.hasPrefix("/")
        switch name {
        case "br":
            result.append(AttributedString("\n"))
        case "strong", "b":
            bold = max(0, bold + (closing ? -1 : 1))
        case "em", "i":
            italic = max(0, italic + (closing ? -1 : 1))
        case "a":
            if closing {
                link = nil
            } else if let href = attribute("href", in: tag) {
                link = AppConfig.assetURL(href)
            }
        default:
            break // every other tag contributes its text only
        }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let range = tag.range(of: "\(name)=", options: .caseInsensitive) else { return nil }
        let rest = tag[range.upperBound...]
        guard let quote = rest.first, quote == "\"" || quote == "'" else {
            return String(rest.prefix(while: { $0 != " " })).trimmed.nilIfBlank
        }
        let body = rest.dropFirst()
        guard let end = body.firstIndex(of: quote) else { return nil }
        return String(body[body.startIndex..<end])
    }

    private static func trimWhitespace(_ value: AttributedString) -> AttributedString {
        var text = String(value.characters)
        // Entity-decoded non-breaking spaces read as blank lines otherwise.
        text = text.replacingOccurrences(of: "\u{00a0}", with: " ")
        guard text.trimmed.isEmpty else {
            var trimmed = value
            while let first = trimmed.characters.first, first.isWhitespace, !trimmed.characters.isEmpty {
                trimmed.removeSubrange(trimmed.startIndex..<trimmed.index(afterCharacter: trimmed.startIndex))
            }
            while let last = trimmed.characters.last, last.isWhitespace, !trimmed.characters.isEmpty {
                let end = trimmed.endIndex
                trimmed.removeSubrange(trimmed.index(beforeCharacter: end)..<end)
            }
            return trimmed
        }
        return AttributedString()
    }

    // MARK: - Entities

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00a0}",
        "hellip": "…", "mdash": "—", "ndash": "–", "rsquo": "’", "lsquo": "‘",
        "ldquo": "“", "rdquo": "”", "middot": "·", "bull": "•", "yen": "¥", "copy": "©",
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "&",
                  let semicolon = text[index...].prefix(12).firstIndex(of: ";")
            else {
                out.append(text[index])
                index = text.index(after: index)
                continue
            }
            let name = String(text[text.index(after: index)..<semicolon])
            if name.hasPrefix("#") {
                let digits = name.dropFirst()
                let scalar: UInt32? = digits.hasPrefix("x") || digits.hasPrefix("X")
                    ? UInt32(digits.dropFirst(), radix: 16)
                    : UInt32(digits)
                if let scalar, let unicode = Unicode.Scalar(scalar) {
                    out.append(Character(unicode))
                    index = text.index(after: semicolon)
                    continue
                }
            } else if let replacement = namedEntities[name.lowercased()] {
                out.append(replacement)
                index = text.index(after: semicolon)
                continue
            }
            out.append(text[index])
            index = text.index(after: index)
        }
        return out
    }
}
