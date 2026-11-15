import SwiftUI

/// The client's tab: the company we have on file, and every position they have
/// asked us to fill.
struct EmployerHomeView: View {
    @Environment(AppSession.self) private var session
    @State private var model = EmployerModel()
    @State private var editingProfile = false
    @State private var composing = false
    @State private var editingJob: Job?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    companyCard
                    if let message = model.errorMessage {
                        Notice(kind: .error, message: message)
                            .padding(.horizontal, Theme.gutter)
                    }
                    postings
                }
                .padding(.vertical, 16)
            }
            .brandBackground()
            .scrollIndicators(.hidden)
            .navigationTitle("Hiring")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        composing = true
                    } label: {
                        Label("Post a position", systemImage: "plus")
                    }
                }
            }
            .task { await model.load() }
            .refreshable { await model.load(force: true) }
            .sheet(isPresented: $editingProfile) {
                EmployerProfileEditor(profile: model.profile) { saved in
                    model.profile = saved
                }
            }
            .sheet(isPresented: $composing) {
                JobEditorView(existing: nil, defaultCompany: model.profile.company) { _ in
                    Task { await model.load(force: true) }
                }
            }
            .sheet(item: $editingJob) { job in
                JobEditorView(existing: job, defaultCompany: model.profile.company) { _ in
                    Task { await model.load(force: true) }
                }
            }
            .navigationDestination(for: Job.self) { job in
                ApplicantsView(job: job, asConsultant: false)
            }
        }
    }

    private var companyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.profile.company.nilIfBlank ?? "Your company")
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.ink)
                    Text([model.profile.contactName, model.profile.contactRole]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                    if !model.profile.location.isEmpty {
                        Text(model.profile.location)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                Spacer(minLength: 8)
                Button("Edit") { editingProfile = true }
                    .font(.subheadline.weight(.semibold))
            }
            if model.profile.company.isEmpty {
                Notice(kind: .info, message: "Add your company details — they appear on every posting a consultant reviews.")
            }
        }
        .brandCard()
        .padding(.horizontal, Theme.gutter)
    }

    private var postings: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Positions",
                subtitle: model.jobs.isEmpty ? nil : "\(model.liveCount) live · \(model.jobs.count) in total"
            )
            if model.isLoading && model.jobs.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
            } else if model.jobs.isEmpty {
                EmptyStateView(
                    icon: "doc.badge.plus",
                    title: "No positions yet",
                    message: "Describe the role you are hiring for. A consultant reviews it, then it goes on the board.",
                    actionTitle: "Post a position",
                    action: { composing = true }
                )
                .brandCard()
            } else {
                VStack(spacing: 12) {
                    ForEach(model.jobs) { job in
                        EmployerJobCard(
                            job: job,
                            onEdit: { editingJob = job },
                            onStatus: { status in await model.setStatus(job: job, status: status) },
                            onDelete: { await model.delete(job) }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

private struct EmployerJobCard: View {
    let job: Job
    let onEdit: () -> Void
    let onStatus: (String) async -> Void
    let onDelete: () async -> Void

    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.ink)
                    Text([job.location.nilIfBlank, Format.employmentType(job.employmentType)]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryInk)
                }
                Spacer(minLength: 8)
                Chip(text: job.statusKind.label, tint: statusTint)
            }

            Text(job.statusKind.explanation)
                .font(.caption)
                .foregroundStyle(Theme.secondaryInk)

            if job.statusKind == .rejected, let note = job.reviewNote, !note.isEmpty {
                Notice(kind: .warning, message: note)
            }

            if let count = job.applicationCount, count > 0 {
                NavigationLink(value: job) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2")
                        Text(count == 1 ? "1 applicant" : "\(count) applicants")
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.navy)
                }
            } else if job.isOnBoard {
                Text("No applicants yet.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
            }

            HStack(spacing: 14) {
                Button("Edit", action: onEdit)
                    .font(.subheadline.weight(.semibold))
                Menu {
                    if job.statusKind == .draft || job.statusKind == .rejected {
                        Button("Submit for review") { Task { await onStatus("pending") } }
                    }
                    if job.statusKind == .pending {
                        Button("Back to draft") { Task { await onStatus("draft") } }
                    }
                    if job.isOnBoard {
                        Button("Mark as filled") { Task { await onStatus("filled") } }
                        Button("Close this search") { Task { await onStatus("closed") } }
                    }
                    if job.statusKind == .filled || job.statusKind == .closed {
                        Button("Reopen for review") { Task { await onStatus("pending") } }
                    }
                    Divider()
                    Button("Delete", role: .destructive) { confirmingDelete = true }
                } label: {
                    Label("Manage", systemImage: "ellipsis.circle")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Text("Updated \(Format.relative(job.updatedAt).lowercased())")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
        .brandCard()
        .confirmationDialog("Delete this posting?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await onDelete() } }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("Applications already received are deleted with it.")
        }
    }

    private var statusTint: Color {
        switch job.statusKind {
        case .published: return Theme.successTint
        case .pending: return Theme.warningTint
        case .rejected: return Theme.dangerTint
        default: return Theme.secondaryInk
        }
    }
}

@MainActor
@Observable
final class EmployerModel {
    var profile = EmployerProfile()
    private(set) var jobs: [Job] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var errorMessage: String?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    var liveCount: Int { jobs.filter(\.isOnBoard).count }

    func load(force: Bool = false) async {
        if hasLoaded, !force { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let overview = try await api.fetchEmployerOverview()
            profile = overview.profile
            jobs = overview.jobs
            hasLoaded = true
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func setStatus(job: Job, status: String) async {
        do {
            let updated = try await api.setJobStatus(id: job.id, status: status)
            replace(updated)
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func delete(_ job: Job) async {
        do {
            try await api.deleteJob(id: job.id)
            jobs.removeAll { $0.id == job.id }
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func replace(_ job: Job) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            // The list query carries an application count the single-job
            // responses do not, so it is kept.
            var updated = job
            updated.applicationCount = jobs[index].applicationCount
            jobs[index] = updated
        }
    }
}
