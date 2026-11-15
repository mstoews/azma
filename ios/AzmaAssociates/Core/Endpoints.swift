import Foundation

/// Every route the app calls, in one place, so a path change is a one-line fix.
extension APIClient {
    // MARK: Public

    func fetchSite() async throws -> SiteContent {
        try await get("/api/v1/site")
    }

    func fetchOptions() async throws -> ServerOptions {
        try await get("/api/v1/options")
    }

    func fetchJobs(
        search: String = "", sector: String = "", employmentType: String = "",
        remoteOnly: Bool = false, limit: Int = 25, offset: Int = 0
    ) async throws -> JobsPage {
        try await get("/api/v1/jobs", query: [
            "q": search.nilIfBlank,
            "sector": sector.nilIfBlank,
            "employmentType": employmentType.nilIfBlank,
            "remote": remoteOnly ? "1" : nil,
            "limit": String(limit),
            "offset": String(offset),
        ])
    }

    func fetchJob(id: Int64) async throws -> Job {
        try await get("/api/v1/jobs/\(id)")
    }

    func sendInquiry(_ input: InquiryInput) async throws -> Inquiry {
        try await post("/api/v1/inquiries", body: input)
    }

    // MARK: Account

    func signIn(email: String, password: String) async throws -> AuthResponse {
        struct Body: Encodable, Sendable { let email: String; let password: String }
        return try await post("/api/v1/auth/login", body: Body(email: email, password: password))
    }

    func register(email: String, password: String, role: Role, name: String, company: String) async throws -> AuthResponse {
        struct Body: Encodable, Sendable {
            let email: String, password: String, role: String, name: String, company: String
        }
        return try await post("/api/v1/auth/register", body: Body(
            email: email, password: password, role: role.rawValue, name: name, company: company
        ))
    }

    func fetchMe() async throws -> MeResponse {
        try await get("/api/v1/auth/me")
    }

    func signOut() async throws {
        try await send("/api/v1/auth/logout", method: "POST")
    }

    func changePassword(current: String, new: String) async throws {
        struct Body: Encodable, Sendable { let currentPassword: String; let newPassword: String }
        try await send("/api/v1/auth/password", method: "PUT", body: Body(currentPassword: current, newPassword: new))
    }

    func fetchMyInquiries() async throws -> [Inquiry] {
        try await get("/api/v1/my/inquiries")
    }

    // MARK: Candidate

    func fetchCandidateOverview() async throws -> CandidateOverview {
        try await get("/api/v1/candidate/me")
    }

    func saveCandidateProfile(_ profile: CandidateProfile) async throws -> CandidateProfile {
        try await put("/api/v1/candidate/profile", body: profile)
    }

    func setProfileSubmitted(_ submitted: Bool) async throws -> CandidateProfile {
        struct Body: Encodable, Sendable { let submitted: Bool }
        return try await post("/api/v1/candidate/profile/submit", body: Body(submitted: submitted))
    }

    func uploadResume(fileURL: URL, filename: String, contentType: String) async throws -> Resume {
        try await upload("/api/v1/candidate/resumes", fileURL: fileURL, filename: filename, contentType: contentType)
    }

    func deleteResume(id: Int64) async throws {
        try await delete("/api/v1/candidate/resumes/\(id)")
    }

    func apply(jobId: Int64, resumeId: Int64?, coverNote: String) async throws {
        struct Body: Encodable, Sendable { let jobId: Int64; let resumeId: Int64?; let coverNote: String }
        try await send("/api/v1/candidate/applications", method: "POST",
                       body: Body(jobId: jobId, resumeId: resumeId, coverNote: coverNote))
    }

    func withdraw(applicationId: Int64) async throws {
        try await send("/api/v1/candidate/applications/\(applicationId)/withdraw", method: "POST")
    }

    func saveJob(id: Int64) async throws {
        try await send("/api/v1/candidate/saved-jobs/\(id)", method: "PUT")
    }

    func unsaveJob(id: Int64) async throws {
        try await delete("/api/v1/candidate/saved-jobs/\(id)")
    }

    // MARK: Employer

    func fetchEmployerOverview() async throws -> EmployerOverview {
        try await get("/api/v1/employer/me")
    }

    func saveEmployerProfile(_ profile: EmployerProfile) async throws -> EmployerProfile {
        try await put("/api/v1/employer/profile", body: profile)
    }

    func createJob(_ input: JobInput) async throws -> Job {
        try await post("/api/v1/employer/jobs", body: input)
    }

    func updateJob(id: Int64, input: JobInput) async throws -> Job {
        try await put("/api/v1/employer/jobs/\(id)", body: input)
    }

    func setJobStatus(id: Int64, status: String) async throws -> Job {
        struct Body: Encodable, Sendable { let status: String }
        return try await put("/api/v1/employer/jobs/\(id)/status", body: Body(status: status))
    }

    func deleteJob(id: Int64) async throws {
        try await delete("/api/v1/employer/jobs/\(id)")
    }

    func fetchApplicants(jobId: Int64, asConsultant: Bool) async throws -> ApplicantsResponse {
        let base = asConsultant ? "/api/v1/admin/jobs" : "/api/v1/employer/jobs"
        return try await get("\(base)/\(jobId)/applications")
    }

    func setApplicationStatus(id: Int64, status: String, asConsultant: Bool) async throws {
        struct Body: Encodable, Sendable { let status: String }
        let base = asConsultant ? "/api/v1/admin/applications" : "/api/v1/employer/applications"
        try await send("\(base)/\(id)/status", method: "PUT", body: Body(status: status))
    }

    // MARK: Consultant

    func fetchReviewQueue(status: String) async throws -> AdminJobsPage {
        try await get("/api/v1/admin/jobs", query: ["status": status.nilIfBlank, "limit": "100"])
    }

    func review(jobId: Int64, status: String, note: String) async throws -> Job {
        struct Body: Encodable, Sendable { let status: String; let reviewNote: String }
        return try await put("/api/v1/admin/jobs/\(jobId)/status", body: Body(status: status, reviewNote: note))
    }

    func fetchCandidateDirectory(search: String, includeUnsubmitted: Bool) async throws -> CandidateDirectoryPage {
        try await get("/api/v1/admin/candidates", query: [
            "q": search.nilIfBlank,
            "all": includeUnsubmitted ? "1" : nil,
            "limit": "100",
        ])
    }

    func fetchCandidate(userId: String) async throws -> CandidateDetail {
        try await get("/api/v1/admin/candidates/\(userId)")
    }

    func fetchInquiries(status: String) async throws -> InquiriesPage {
        try await get("/api/v1/admin/inquiries", query: ["status": status.nilIfBlank, "limit": "100"])
    }

    func setInquiryStatus(id: Int64, status: String) async throws -> Inquiry {
        struct Body: Encodable, Sendable { let status: String }
        return try await put("/api/v1/admin/inquiries/\(id)/status", body: Body(status: status))
    }

    func downloadResume(id: Int64, filename: String) async throws -> URL {
        try await download("/api/v1/resumes/\(id)/file", suggestedName: filename)
    }
}
