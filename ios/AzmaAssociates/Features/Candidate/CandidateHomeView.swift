import SwiftUI
import UniformTypeIdentifiers

/// The candidate's own tab: the profile a consultant reads, the resume on
/// file, and what has happened to each application.
struct CandidateHomeView: View {
    @Environment(AppSession.self) private var session
    @Environment(CandidateStore.self) private var store
    @State private var editingProfile = false
    @State private var importingResume = false
    @State private var busyMessage: String?
    @State private var errorMessage: String?
    @State private var resumeToDelete: Resume?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    profileCard
                    if let errorMessage {
                        Notice(kind: .error, message: errorMessage)
                            .padding(.horizontal, Theme.gutter)
                    }
                    representation
                    resumes
                    applications
                    saved
                }
                .padding(.vertical, 16)
            }
            .brandBackground()
            .scrollIndicators(.hidden)
            .navigationTitle("My career")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { editingProfile = true }
                }
            }
            .refreshable { await store.load(force: true) }
            .task { await store.load() }
            .sheet(isPresented: $editingProfile) {
                CandidateProfileEditor(profile: store.profile)
            }
            .fileImporter(
                isPresented: $importingResume,
                allowedContentTypes: Self.resumeTypes,
                allowsMultipleSelection: false
            ) { result in
                Task { await handleImport(result) }
            }
            .confirmationDialog(
                "Remove this document?",
                isPresented: Binding(get: { resumeToDelete != nil }, set: { if !$0 { resumeToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let resume = resumeToDelete { Task { await remove(resume) } }
                }
                Button("Keep", role: .cancel) { resumeToDelete = nil }
            } message: {
                Text("Applications you have already sent keep the copy we received.")
            }
            .navigationDestination(for: Job.self) { JobDetailView(job: $0) }
        }
    }

    static var resumeTypes: [UTType] {
        [
            .pdf,
            UTType("com.microsoft.word.doc"),
            UTType("org.openxmlformats.wordprocessingml.document"),
        ].compactMap { $0 }
    }

    // MARK: Sections

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(Theme.navy.opacity(0.1))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Text(initials)
                            .font(Theme.display(20, weight: .medium))
                            .foregroundStyle(Theme.navy)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.profile.fullName.nilIfBlank ?? session.account?.name ?? String(localized: "Your profile"))
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.ink)
                    if !store.profile.headline.isEmpty {
                        Text(store.profile.headline)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    if !store.profile.location.isEmpty {
                        Text(store.profile.location)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                Spacer(minLength: 0)
            }

            let progress = store.profile.completeness
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(progress.done), total: Double(progress.total))
                    .tint(progress.done == progress.total ? Theme.successTint : Theme.navy)
                Text(progress.done == progress.total
                     ? "Your profile is complete."
                     : "\(progress.done) of \(progress.total) sections filled in — the fuller it is, the better we can place you.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
            }

            if !store.profile.sectors.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(store.profile.sectors, id: \.self) { Chip(text: Format.sector($0)) }
                }
            }
        }
        .brandCard()
        .padding(.horizontal, Theme.gutter)
    }

    private var initials: String {
        let name = store.profile.fullName.nilIfBlank ?? session.account?.name ?? "?"
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)) }.joined().uppercased()
    }

    private var representation: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Representation")
            VStack(alignment: .leading, spacing: 12) {
                Text(store.profile.submitted
                     ? "Your profile is with our consultants. We will be in touch when something fits."
                     : "Ask us to represent you and a consultant will review your profile against the searches we are running.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryInk)
                if store.profile.submitted, let since = store.profile.submittedAt {
                    Text("With us since \(since.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryInk)
                }
                AsyncButton {
                    await setSubmitted(!store.profile.submitted)
                } label: {
                    Text(store.profile.submitted ? "Withdraw my profile" : "Ask AZMA to represent me")
                }
                .buttonStyle(store.profile.submitted ? .brandQuiet : .brand)
            }
            .brandCard()
        }
        .padding(.horizontal, Theme.gutter)
    }

    private var resumes: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Resume",
                subtitle: "PDF or Word, up to \(Format.fileSize(session.options.resumeMaxBytes))",
                action: store.resumes.count < session.options.maxResumesPerUser
                    ? (title: "Add", handler: { importingResume = true })
                    : nil
            )
            if let busyMessage {
                Notice(kind: .info, message: busyMessage)
            }
            if store.resumes.isEmpty {
                EmptyStateView(
                    icon: "doc.text",
                    title: "No resume yet",
                    message: "A consultant works from your resume. Add one to apply for positions.",
                    actionTitle: "Choose a file",
                    action: { importingResume = true }
                )
                .brandCard()
            } else {
                VStack(spacing: 10) {
                    ForEach(store.resumes) { resume in
                        ResumeRow(resume: resume) { resumeToDelete = resume }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    private var applications: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Applications")
            if store.applications.isEmpty {
                EmptyStateView(
                    icon: "paperplane",
                    title: "Nothing sent yet",
                    message: "Positions you apply for show here, with where each one stands."
                )
                .brandCard()
            } else {
                VStack(spacing: 10) {
                    ForEach(store.applications) { application in
                        ApplicationRow(application: application) {
                            await withdraw(application)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    @ViewBuilder
    private var saved: some View {
        if !store.savedJobs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Saved positions")
                VStack(spacing: 10) {
                    ForEach(store.savedJobs) { job in
                        NavigationLink(value: job) {
                            JobCard(job: job, isSaved: true, applicationState: store.application(for: job.id)?.state)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }

    // MARK: Actions

    private func setSubmitted(_ value: Bool) async {
        do {
            try await store.setSubmitted(value)
            errorMessage = nil
        } catch {
            errorMessage = await session.message(for: error)
        }
    }

    private func withdraw(_ application: Application) async {
        do {
            try await store.withdraw(application)
            errorMessage = nil
        } catch {
            errorMessage = await session.message(for: error)
        }
    }

    private func remove(_ resume: Resume) async {
        resumeToDelete = nil
        do {
            try await store.removeResume(resume)
            errorMessage = nil
        } catch {
            errorMessage = await session.message(for: error)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) async {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            busyMessage = String(localized: "Uploading \(url.lastPathComponent)…")
            defer { busyMessage = nil }
            // Files chosen in the document picker live outside the sandbox.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                try await store.addResume(
                    fileURL: url,
                    filename: url.lastPathComponent,
                    contentType: contentType(for: url)
                )
                errorMessage = nil
            } catch {
                errorMessage = await session.message(for: error)
            }
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
    }

    private func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        default: return "application/octet-stream"
        }
    }
}

private struct ResumeRow: View {
    let resume: Resume
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: resume.mimeType == "application/pdf" ? "doc.richtext" : "doc.text")
                .font(.title3)
                .foregroundStyle(Theme.navy)
            VStack(alignment: .leading, spacing: 2) {
                Text(resume.filename)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(Format.fileSize(resume.sizeBytes)) · added \(Format.relative(resume.createdAt).lowercased())")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
            }
            Spacer(minLength: 0)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.dangerTint)
            .accessibilityLabel("Remove \(resume.filename)")
        }
        .brandCard(padding: 14)
    }
}

private struct ApplicationRow: View {
    let application: Application
    let onWithdraw: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(application.jobTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(application.jobCompany)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryInk)
                }
                Spacer(minLength: 8)
                Chip(text: application.state.label, tint: tint)
            }
            Text(application.state.candidateExplanation)
                .font(.caption)
                .foregroundStyle(Theme.secondaryInk)
            HStack {
                Text("Sent \(Format.relative(application.createdAt).lowercased())")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryInk)
                Spacer()
                if application.state.isOpen {
                    AsyncButton {
                        await onWithdraw()
                    } label: {
                        Text("Withdraw")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.dangerTint)
                    }
                }
            }
        }
        .brandCard(padding: 14)
    }

    private var tint: Color {
        switch application.state {
        case .placed, .offer, .shortlisted: return Theme.successTint
        case .rejected, .withdrawn: return Theme.secondaryInk
        default: return Theme.navy
        }
    }
}
