import Foundation

/// Who is signed in. The server has one more role, `admin`, which belongs to
/// AZMA's own consultants.
enum Role: String, Codable, Sendable, CaseIterable {
    case candidate
    case employer
    case admin

    var title: String {
        switch self {
        case .candidate: return String(localized: "Business professional")
        case .employer: return String(localized: "Hiring")
        case .admin: return String(localized: "Consultant")
        }
    }

    var blurb: String {
        switch self {
        case .candidate: return String(localized: "Leave your resume with us and apply for positions we are retained on.")
        case .employer: return String(localized: "Tell us the position you are hiring for and work with a consultant on the search.")
        case .admin: return String(localized: "AZMA & Associates staff.")
        }
    }
}

struct Account: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let email: String
    let name: String
    let role: Role
}

struct AuthResponse: Codable, Sendable {
    let token: String
    let expiresAt: Date
    let user: Account
}

struct MeResponse: Codable, Sendable {
    let user: Account
    let expiresAt: Date
}

/// The vocabulary the server validates against, so every picker in the app
/// offers exactly what the API accepts.
struct ServerOptions: Codable, Sendable, Equatable {
    var sectors: [String] = []
    var employmentTypes: [String] = []
    var currencies: [String] = []
    var offices: [String] = []
    var inquiryKinds: [String] = []
    var jobStatuses: [String] = []
    var applicationStates: [String] = []
    var minPasswordLength: Int = 6
    var maxResumesPerUser: Int = 5
    var resumeMaxBytes: Int64 = 10 << 20

    /// Used until `/options` answers, and if it never does.
    static let fallback = ServerOptions(
        sectors: [
            "Asset Management", "Alternative Investment Management", "Private Equity", "Hedge Fund",
            "Real Estate", "Fund Portfolio Companies", "Trust Bank", "Securities", "Investment Banking",
            "Bank", "M&A", "Information Technology", "Consulting Firms", "Healthcare", "Industrial", "Startup",
        ],
        employmentTypes: ["full_time", "contract", "part_time", "internship"],
        currencies: ["JPY", "SGD", "USD", "EUR", "GBP", "HKD", "AUD"],
        offices: ["tokyo", "singapore"],
        inquiryKinds: ["hiring", "career", "general"],
        jobStatuses: ["draft", "pending", "published", "filled", "closed", "rejected"],
        applicationStates: ["submitted", "under_review", "shortlisted", "interviewing", "offer", "placed", "rejected", "withdrawn"]
    )
}
