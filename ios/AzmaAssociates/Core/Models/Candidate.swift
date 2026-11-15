import Foundation

/// Everything the candidate side of the app needs, in one response.
struct CandidateOverview: Codable, Sendable {
    var profile: CandidateProfile
    var resumes: [Resume]
    var applications: [Application]
    var savedJobs: [Job]
}

struct CandidateProfile: Codable, Sendable, Equatable, Hashable {
    var fullName: String = ""
    var headline: String = ""
    var summary: String = ""
    var location: String = ""
    var phone: String = ""
    var linkedinUrl: String = ""
    var currentEmployer: String = ""
    var currentTitle: String = ""
    var yearsExperience: Int = 0
    var sectors: [String] = []
    var desiredRoles: [String] = []
    var languages: [String] = []
    var workAuthorization: String = ""
    var salaryExpectation: String = ""
    var openToOffers: Bool = true
    var submitted: Bool = false
    var submittedAt: Date?

    /// The fields a consultant needs before the profile is worth presenting.
    var completeness: (done: Int, total: Int) {
        let checks = [
            !fullName.trimmed.isEmpty,
            !headline.trimmed.isEmpty,
            !summary.trimmed.isEmpty,
            !location.trimmed.isEmpty,
            !currentTitle.trimmed.isEmpty,
            yearsExperience > 0,
            !sectors.isEmpty,
            !desiredRoles.isEmpty,
        ]
        return (checks.filter { $0 }.count, checks.count)
    }

    var problem: String? {
        fullName.trimmed.isEmpty ? "Your name is required." : nil
    }
}

struct Resume: Codable, Sendable, Identifiable, Hashable {
    let id: Int64
    let filename: String
    let mimeType: String
    let sizeBytes: Int64
    let createdAt: Date
    let downloadUrl: String
}

/// The candidate's own view of an application.
struct Application: Codable, Sendable, Identifiable, Hashable {
    let id: Int64
    let jobId: Int64
    let jobTitle: String
    let jobCompany: String
    let jobLocation: String
    let jobStatus: String
    let status: String
    let coverNote: String
    let resumeFilename: String
    let createdAt: Date
    let updatedAt: Date

    var state: ApplicationState { ApplicationState(rawValue: status) ?? .submitted }
}

enum ApplicationState: String, Sendable, CaseIterable {
    case submitted, under_review, shortlisted, interviewing, offer, placed, rejected, withdrawn

    var label: String {
        switch self {
        case .submitted: return "Submitted"
        case .under_review: return "Under review"
        case .shortlisted: return "Shortlisted"
        case .interviewing: return "Interviewing"
        case .offer: return "Offer"
        case .placed: return "Placed"
        case .rejected: return "Not progressing"
        case .withdrawn: return "Withdrawn"
        }
    }

    /// Said from the candidate's side.
    var candidateExplanation: String {
        switch self {
        case .submitted: return "With the consultant handling this search."
        case .under_review: return "The client is reviewing your application."
        case .shortlisted: return "You have been presented to the client."
        case .interviewing: return "Interviews are under way."
        case .offer: return "An offer is on the table."
        case .placed: return "Placed — congratulations."
        case .rejected: return "The client is not taking this one forward."
        case .withdrawn: return "You withdrew this application."
        }
    }

    var isOpen: Bool {
        switch self {
        case .rejected, .withdrawn, .placed: return false
        default: return true
        }
    }
}

/// What a client or a consultant sees of someone who applied. Until a
/// consultant has presented the candidate, `presented` is false and the
/// identifying fields are empty: the client sees the professional summary,
/// not the person.
struct Applicant: Codable, Sendable, Identifiable, Hashable {
    let id: Int64
    let jobId: Int64
    let status: String
    let coverNote: String
    let createdAt: Date
    let headline: String
    let location: String
    let currentEmployer: String
    let currentTitle: String
    let yearsExperience: Int
    let name: String
    let email: String
    let resumeId: Int64?
    let resumeFilename: String
    var resumeDownloadUrl: String?
    let presented: Bool

    var state: ApplicationState { ApplicationState(rawValue: status) ?? .submitted }
    var displayName: String { presented && !name.isEmpty ? name : "Candidate #\(id)" }
}

struct ApplicantsResponse: Codable, Sendable {
    let job: Job
    let applicants: [Applicant]
}

/// A consultant's list of the people who asked to be represented.
struct CandidateSummary: Codable, Sendable, Identifiable, Hashable {
    let userId: String
    let email: String
    let profile: CandidateProfile
    let resumeCount: Int
    let applicationCount: Int
    let latestResumeId: Int64?
    let latestResumeFilename: String

    var id: String { userId }
}

struct CandidateDirectoryPage: Codable, Sendable {
    let candidates: [CandidateSummary]
}

struct CandidateDetail: Codable, Sendable {
    let userId: String
    let email: String
    let profile: CandidateProfile
    let resumes: [Resume]
    let applications: [Application]
}
