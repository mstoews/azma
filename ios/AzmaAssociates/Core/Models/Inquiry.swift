import Foundation

/// A consultation request — the app's version of the web site's Contact page.
struct Inquiry: Codable, Sendable, Identifiable, Hashable {
    let id: Int64
    let kind: String
    let name: String
    let email: String
    let phone: String
    let company: String
    let office: String
    let message: String
    let status: String
    let handledAt: Date?
    let createdAt: Date
    var accountEmail: String?

    var kindKind: InquiryKind { InquiryKind(rawValue: kind) ?? .general }
}

enum InquiryKind: String, Codable, Sendable, CaseIterable {
    case hiring, career, general

    var label: String {
        switch self {
        case .hiring: return String(localized: "I am hiring")
        case .career: return String(localized: "My career")
        case .general: return String(localized: "Something else")
        }
    }

    var prompt: String {
        switch self {
        case .hiring: return String(localized: "Tell us about the position, the team and when you need someone in the seat.")
        case .career: return String(localized: "Tell us what you are looking for next, and what would make a move worthwhile.")
        case .general: return String(localized: "How can we help?")
        }
    }
}

struct InquiryInput: Codable, Sendable, Equatable {
    var kind: String = InquiryKind.hiring.rawValue
    var name: String = ""
    var email: String = ""
    var phone: String = ""
    var company: String = ""
    var office: String = ""
    var message: String = ""

    var problem: String? {
        if name.trimmed.isEmpty { return String(localized: "Your name is required.") }
        if !email.isValidEmail { return String(localized: "A valid email address is required.") }
        if message.trimmed.isEmpty { return String(localized: "Please tell us what you would like to discuss.") }
        return nil
    }
}

struct InquiriesPage: Codable, Sendable {
    let inquiries: [Inquiry]
    let countsByStatus: [String: Int]
}

enum InquiryStatus: String, Sendable, CaseIterable {
    case new, in_progress, closed

    var label: String {
        switch self {
        case .new: return String(localized: "New")
        case .in_progress: return String(localized: "In progress")
        case .closed: return String(localized: "Closed")
        }
    }
}
