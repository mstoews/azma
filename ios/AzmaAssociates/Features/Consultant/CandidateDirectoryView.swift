import SwiftUI

/// The people who have asked us to represent them.
struct CandidateDirectoryView: View {
    @Environment(AppSession.self) private var session
    @State private var candidates: [CandidateSummary] = []
    @State private var search = ""
    @State private var includeUnsubmitted = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if let errorMessage {
                    Notice(kind: .error, message: errorMessage)
                        .padding(.horizontal, Theme.gutter)
                }
                if isLoading && candidates.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if candidates.isEmpty {
                    EmptyStateView(
                        icon: "person.crop.circle.badge.questionmark",
                        title: "No candidates",
                        message: includeUnsubmitted
                            ? "Nobody has registered yet."
                            : "Nobody has asked to be represented yet. Include registered accounts to see everyone."
                    )
                } else {
                    ForEach(candidates) { candidate in
                        NavigationLink(value: candidate) {
                            CandidateRow(candidate: candidate)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Theme.gutter)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .searchable(text: $search, prompt: "Name, employer or email")
        .onChange(of: search) { _, _ in scheduleSearch() }
        .task { await load() }
        .refreshable { await load() }
    }

    private var controls: some View {
        Toggle("Include accounts not yet submitted", isOn: $includeUnsubmitted)
            .font(.footnote)
            .tint(Theme.navy)
            .padding(.horizontal, Theme.gutter)
            .onChange(of: includeUnsubmitted) { _, _ in Task { await load() } }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            candidates = try await session.api
                .fetchCandidateDirectory(search: search, includeUnsubmitted: includeUnsubmitted)
                .candidates
            errorMessage = nil
        } catch {
            errorMessage = await session.message(for: error)
        }
    }
}

private struct CandidateRow: View {
    let candidate: CandidateSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.profile.fullName.nilIfBlank ?? candidate.email)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.ink)
                    if !candidate.profile.headline.isEmpty {
                        Text(candidate.profile.headline)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                Spacer(minLength: 8)
                if candidate.profile.submitted {
                    Chip(text: "Represented", tint: Theme.successTint)
                } else {
                    Chip(text: "Registered", tint: Theme.secondaryInk)
                }
            }
            FlowLayout(spacing: 6) {
                if !candidate.profile.currentEmployer.isEmpty {
                    Chip(text: candidate.profile.currentEmployer, systemImage: "building.2")
                }
                if candidate.profile.yearsExperience > 0 {
                    Chip(text: "\(candidate.profile.yearsExperience) yrs", systemImage: "clock")
                }
                if candidate.resumeCount > 0 {
                    Chip(text: candidate.resumeCount == 1 ? "1 document" : "\(candidate.resumeCount) documents",
                         systemImage: "doc.text", tint: Theme.navy)
                }
                if candidate.applicationCount > 0 {
                    Chip(
                        text: candidate.applicationCount == 1 ? "1 application" : "\(candidate.applicationCount) applications",
                        systemImage: "paperplane"
                    )
                }
            }
            if !candidate.profile.openToOffers {
                Text("Not in the market right now.")
                    .font(.caption)
                    .foregroundStyle(Theme.warningTint)
            }
        }
        .brandCard()
    }
}

/// One candidate in full: the profile, the documents on file, and where each
/// application stands.
struct CandidateDetailView: View {
    let userID: String

    @Environment(AppSession.self) private var session
    @State private var detail: CandidateDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var previewURL: URL?
    @State private var previewTitle = ""

    private struct PreviewItem: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    var body: some View {
        ScrollView {
            if let detail {
                VStack(alignment: .leading, spacing: 22) {
                    profile(detail)
                    documents(detail)
                    applications(detail)
                }
                .padding(.vertical, 16)
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 60)
            } else if let errorMessage {
                Notice(kind: .error, message: errorMessage).padding(Theme.gutter)
            }
        }
        .brandBackground()
        .navigationTitle(detail?.profile.fullName.nilIfBlank ?? "Candidate")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: Binding(
            get: { previewURL.map { PreviewItem(url: $0) } },
            set: { if $0 == nil { previewURL = nil } }
        )) { item in
            DocumentPreviewSheet(url: item.url, title: previewTitle)
        }
    }

    private func profile(_ detail: CandidateDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.profile.fullName.nilIfBlank ?? detail.email)
                    .font(Theme.display(24))
                    .foregroundStyle(Theme.ink)
                if !detail.profile.headline.isEmpty {
                    Text(detail.profile.headline)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                contactRow(icon: "envelope", value: detail.email)
                if !detail.profile.phone.isEmpty { contactRow(icon: "phone", value: detail.profile.phone) }
                if !detail.profile.location.isEmpty { contactRow(icon: "mappin.and.ellipse", value: detail.profile.location) }
                if !detail.profile.linkedinUrl.isEmpty { contactRow(icon: "link", value: detail.profile.linkedinUrl) }
            }
            if !detail.profile.summary.isEmpty {
                Text(detail.profile.summary)
                    .font(.body)
                    .foregroundStyle(Theme.ink.opacity(0.9))
                    .lineSpacing(4)
            }
            FlowLayout(spacing: 6) {
                ForEach(detail.profile.sectors, id: \.self) { Chip(text: $0) }
                ForEach(detail.profile.desiredRoles, id: \.self) { Chip(text: $0, tint: Theme.gold) }
                ForEach(detail.profile.languages, id: \.self) { Chip(text: $0, tint: Theme.secondaryInk) }
            }
            if !detail.profile.workAuthorization.isEmpty || !detail.profile.salaryExpectation.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if !detail.profile.workAuthorization.isEmpty {
                        Text("Work authorisation: \(detail.profile.workAuthorization)")
                    }
                    if !detail.profile.salaryExpectation.isEmpty {
                        Text("Expectation: \(detail.profile.salaryExpectation)")
                    }
                }
                .font(.footnote)
                .foregroundStyle(Theme.secondaryInk)
            }
        }
        .brandCard()
        .padding(.horizontal, Theme.gutter)
    }

    private func contactRow(icon: String, value: String) -> some View {
        Label(value, systemImage: icon)
            .font(.footnote)
            .foregroundStyle(Theme.navy)
            .textSelection(.enabled)
    }

    private func documents(_ detail: CandidateDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Documents")
            if detail.resumes.isEmpty {
                Text("Nothing on file.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryInk)
            } else {
                ForEach(detail.resumes) { resume in
                    AsyncButton {
                        await open(resume)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(Theme.navy)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(resume.filename)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Text("\(Format.fileSize(resume.sizeBytes)) · \(Format.relative(resume.createdAt))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryInk)
                            }
                            Spacer()
                            Image(systemName: "arrow.down.circle")
                                .foregroundStyle(Theme.navy)
                        }
                        .brandCard(padding: 14)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    private func applications(_ detail: CandidateDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Applications")
            if detail.applications.isEmpty {
                Text("No applications yet.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryInk)
            } else {
                ForEach(detail.applications) { application in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(application.jobTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Chip(text: application.state.label)
                        }
                        Text(application.jobCompany)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryInk)
                        if !application.coverNote.isEmpty {
                            Text(application.coverNote)
                                .font(.footnote)
                                .foregroundStyle(Theme.ink.opacity(0.9))
                                .padding(.top, 2)
                        }
                    }
                    .brandCard(padding: 14)
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await session.api.fetchCandidate(userId: userID)
            errorMessage = nil
        } catch {
            errorMessage = await session.message(for: error)
        }
    }

    private func open(_ resume: Resume) async {
        do {
            previewTitle = resume.filename
            previewURL = try await session.api.downloadResume(id: resume.id, filename: resume.filename)
        } catch {
            errorMessage = await session.message(for: error)
        }
    }
}
