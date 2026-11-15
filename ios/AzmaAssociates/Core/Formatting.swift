import Foundation

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var nilIfBlank: String? { trimmed.isEmpty ? nil : trimmed }

    /// Deliberately permissive: the server is the authority, this only stops
    /// obvious typos before a round trip.
    var isValidEmail: Bool {
        let value = trimmed
        guard value.count >= 6, value.count <= 254, !value.contains(" ") else { return false }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }
}

enum Format {
    /// "Full-time", "Part-time" — the server's snake_case made readable.
    static func employmentType(_ raw: String) -> String {
        switch raw {
        case "full_time": return "Full-time"
        case "part_time": return "Part-time"
        case "contract": return "Contract"
        case "internship": return "Internship"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func office(_ raw: String) -> String {
        switch raw {
        case "tokyo": return "Tokyo"
        case "singapore": return "Singapore"
        default: return raw.isEmpty ? "Either office" : raw.capitalized
        }
    }

    /// "¥25,000,000 – ¥35,000,000", or one side of it, or nothing at all.
    static func salary(min: Int?, max: Int?, currency: String) -> String? {
        guard min != nil || max != nil else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let symbol = currencySymbol(currency)
        func amount(_ value: Int) -> String {
            let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
            return symbol.isEmpty ? "\(number) \(currency)" : "\(symbol)\(number)"
        }
        switch (min, max) {
        case let (minimum?, maximum?): return "\(amount(minimum)) – \(amount(maximum))"
        case let (minimum?, nil): return "From \(amount(minimum))"
        case let (nil, maximum?): return "Up to \(amount(maximum))"
        default: return nil
        }
    }

    static func currencySymbol(_ code: String) -> String {
        switch code {
        case "JPY": return "¥"
        case "USD": return "US$"
        case "SGD": return "S$"
        case "HKD": return "HK$"
        case "AUD": return "A$"
        case "EUR": return "€"
        case "GBP": return "£"
        default: return ""
        }
    }

    static func fileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// "3 days ago" for recent things, a date for older ones.
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 7 * 24 * 3600 {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: date, relativeTo: now)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func experience(_ years: Int) -> String {
        switch years {
        case 0: return "Experience not given"
        case 1: return "1 year of experience"
        default: return "\(years) years of experience"
        }
    }
}
