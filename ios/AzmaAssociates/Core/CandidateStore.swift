import Foundation
import Observation

/// The signed-in candidate's own data: profile, resumes, applications and
/// saved positions.
///
/// The job board needs to know what has been saved or applied for, and so does
/// the candidate tab, so this is shared rather than owned by one screen.
@MainActor
@Observable
final class CandidateStore {
    private(set) var profile = CandidateProfile()
    private(set) var resumes: [Resume] = []
    private(set) var applications: [Application] = []
    private(set) var savedJobs: [Job] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var errorMessage: String?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    var savedJobIDs: Set<Int64> { Set(savedJobs.map(\.id)) }

    /// Applications that still count as live, by position.
    var applicationsByJob: [Int64: Application] {
        Dictionary(applications.map { ($0.jobId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func application(for jobID: Int64) -> Application? { applicationsByJob[jobID] }

    var latestResume: Resume? { resumes.first }

    func reset() {
        profile = CandidateProfile()
        resumes = []
        applications = []
        savedJobs = []
        hasLoaded = false
        errorMessage = nil
    }

    func load(force: Bool = false) async {
        if hasLoaded, !force { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let overview = try await api.fetchCandidateOverview()
            profile = overview.profile
            resumes = overview.resumes
            applications = overview.applications
            savedJobs = overview.savedJobs
            hasLoaded = true
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func save(profile updated: CandidateProfile) async throws {
        profile = try await api.saveCandidateProfile(updated)
    }

    func setSubmitted(_ submitted: Bool) async throws {
        profile = try await api.setProfileSubmitted(submitted)
    }

    func addResume(fileURL: URL, filename: String, contentType: String) async throws {
        let resume = try await api.uploadResume(fileURL: fileURL, filename: filename, contentType: contentType)
        resumes.insert(resume, at: 0)
    }

    func removeResume(_ resume: Resume) async throws {
        try await api.deleteResume(id: resume.id)
        resumes.removeAll { $0.id == resume.id }
    }

    /// Optimistic: the bookmark should feel instant, and the list is reloaded
    /// if the server disagrees.
    func toggleSaved(_ job: Job) async {
        let wasSaved = savedJobIDs.contains(job.id)
        if wasSaved {
            savedJobs.removeAll { $0.id == job.id }
        } else {
            savedJobs.insert(job, at: 0)
        }
        do {
            if wasSaved {
                try await api.unsaveJob(id: job.id)
            } else {
                try await api.saveJob(id: job.id)
            }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            await load(force: true)
        }
    }

    func apply(to job: Job, resumeID: Int64?, coverNote: String) async throws {
        try await api.apply(jobId: job.id, resumeId: resumeID, coverNote: coverNote)
        await load(force: true)
    }

    func withdraw(_ application: Application) async throws {
        try await api.withdraw(applicationId: application.id)
        await load(force: true)
    }
}
