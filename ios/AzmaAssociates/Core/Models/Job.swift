import Foundation

/// A position. The same shape serves the public board, the client's own list
/// and a consultant's review queue; the extra fields are present only for the
/// people entitled to them.
struct Job: Codable, Sendable, Identifiable, Hashable {
    let id: Int64
    var title: String
    var company: String
    var confidential: Bool
    var location: String
    var remote: Bool
    var sector: String
    var employmentType: String
    var description: String
    var requirements: String
    var salaryMin: Int?
    var salaryMax: Int?
    var salaryCurrency: String
    var status: String
    var reviewNote: String?
    var publishedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var applicationCount: Int?
    var employerEmail: String?
    var employerCompany: String?

    var statusKind: JobStatus { JobStatus(rawValue: status) ?? .draft }
    var isOnBoard: Bool { statusKind == .published }
}

enum JobStatus: String, Sendable, CaseIterable {
    case draft, pending, published, filled, closed, rejected

    var label: String {
        switch self {
        case .draft: return "Draft"
        case .pending: return "In review"
        case .published: return "Live"
        case .filled: return "Filled"
        case .closed: return "Closed"
        case .rejected: return "Not approved"
        }
    }

    /// What the state means to the person looking at it.
    var explanation: String {
        switch self {
        case .draft: return "Only you can see this. Submit it when you are ready for a consultant to look."
        case .pending: return "A consultant is reviewing this posting."
        case .published: return "Live on the board and open to applications."
        case .filled: return "Marked as filled."
        case .closed: return "Closed, and no longer taking applications."
        case .rejected: return "A consultant sent this back with a note."
        }
    }
}

struct JobsPage: Codable, Sendable {
    var jobs: [Job]
    var total: Int
    var limit: Int
    var offset: Int
}

struct AdminJobsPage: Codable, Sendable {
    var jobs: [Job]
    var countsByStatus: [String: Int]
}

/// What a client fills in for a position. `submit` is the difference between
/// saving a draft and asking a consultant to take it on.
struct JobInput: Codable, Sendable, Equatable {
    var title: String = ""
    var company: String = ""
    var confidential: Bool = false
    var location: String = ""
    var remote: Bool = false
    var sector: String = ""
    var employmentType: String = "full_time"
    var description: String = ""
    var requirements: String = ""
    var salaryMin: Int?
    var salaryMax: Int?
    var salaryCurrency: String = ""
    var submit: Bool = false

    init() {}

    init(job: Job) {
        title = job.title
        company = job.company
        confidential = job.confidential
        location = job.location
        remote = job.remote
        sector = job.sector
        employmentType = job.employmentType
        description = job.description
        requirements = job.requirements
        salaryMin = job.salaryMin
        salaryMax = job.salaryMax
        salaryCurrency = job.salaryCurrency
    }

    /// Mirrors the server's own checks so the app can explain the problem
    /// before a round trip. The server validates independently.
    var problem: String? {
        if title.trimmed.isEmpty { return "Give the position a title." }
        if company.trimmed.isEmpty { return "Name the hiring company." }
        if let min = salaryMin, let max = salaryMax, max < min {
            return "The top of the range is below the bottom."
        }
        if (salaryMin != nil || salaryMax != nil) && salaryCurrency.isEmpty {
            return "Choose a currency for the salary range."
        }
        if submit && description.trimmed.count < 40 {
            return "Describe the position in a few sentences before submitting it for review."
        }
        return nil
    }
}
