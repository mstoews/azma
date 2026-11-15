import SwiftUI

/// Who has applied for a position.
///
/// A client sees the professional summary of everyone who applied, and the
/// person's name, contact details and resume only once a consultant has
/// presented them. A consultant sees everything.
struct ApplicantsView: View {
    let job: Job
    let asConsultant: Bool

    @Environment(AppSession.self) private var session
    @State private var applicants: [Applicant] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var previewURL: URL?
    @State private var previewTitle = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let errorMessage {
                    Notice(kind: .error, message: errorMessage)
                        .padding(.horizontal, Theme.gutter)
                }
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if applicants.isEmpty {
                    EmptyStateView(
                        icon: "person.2",
                        title: "No applicants yet",
                        message: asConsultant
                            ? "Nobody has applied through the board. Candidates on file can still be presented directly."
                            : "We will let you know as soon as someone applies — and a consultant will present the ones worth your time."
                    )
                } else {
                    ForEach(applicants) { applicant in
                        ApplicantCard(
                            applicant: applicant,
                            asConsultant: asConsultant,
                            options: statusOptions,
                            onStatus: { status in await setStatus(applicant, status) },
                            onOpenResume: { await openResume(applicant) }
                        )
                        .padding(.horizontal, Theme.gutter)
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .brandBackground()
        .navigationTitle("Applicants")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: Binding(
            get: { previewURL.map { PreviewItem(url: $0) } },
            set: { if $0 == nil { previewURL = nil } }
        )) { item in
            DocumentPreviewSheet(url: item.url, title: previewTitle)
        }
    }

    private struct PreviewItem: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(job.title)
                .font(Theme.display(22))
                .foregroundStyle(Theme.ink)
            Text(job.company)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryInk)
            if !asConsultant {
                Text("A consultant assesses everyone who applies and presents the shortlist. Contact details come with the introduction.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    /// Clients record their own decisions; shortlisting is ours.
    private var statusOptions: [ApplicationState] {
        asConsultant
            ? ApplicationState.allCases.filter { $0 != .withdrawn }
            : [.under_review, .interviewing, .offer, .placed, .rejected]
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            applicants = try await session.api.fetchApplicants(jobId: job.id, asConsultant: asConsultant).applicants
            errorMessage = nil
        } catch {
            errorMessage = await session.message(for: error)
        }
    }

    private func setStatus(_ applicant: Applicant, _ status: ApplicationState) async {
        do {
            try await session.api.setApplicationStatus(
                id: applicant.id, status: status.rawValue, asConsultant: asConsultant
            )
            await load()
        } catch {
            errorMessage = await session.message(for: error)
        }
    }

    private func openResume(_ applicant: Applicant) async {
        guard let resumeID = applicant.resumeId else { return }
        do {
            previewTitle = applicant.resumeFilename
            previewURL = try await session.api.downloadResume(
                id: resumeID,
                filename: applicant.resumeFilename.nilIfBlank ?? "resume.pdf"
            )
        } catch {
            errorMessage = await session.message(for: error)
        }
    }
}

private struct ApplicantCard: View {
    let applicant: Applicant
    let asConsultant: Bool
    let options: [ApplicationState]
    let onStatus: (ApplicationState) async -> Void
    let onOpenResume: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(applicant.displayName)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.ink)
                    if !applicant.headline.isEmpty {
                        Text(applicant.headline)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                Spacer(minLength: 8)
                Chip(text: applicant.state.label, tint: tint)
            }

            FlowLayout(spacing: 6) {
                if !applicant.currentTitle.isEmpty || !applicant.currentEmployer.isEmpty {
                    Chip(
                        text: [applicant.currentTitle, applicant.currentEmployer]
                            .filter { !$0.isEmpty }.joined(separator: ", "),
                        systemImage: "building.2"
                    )
                }
                if applicant.yearsExperience > 0 {
                    Chip(text: Format.experience(applicant.yearsExperience), systemImage: "clock")
                }
                if !applicant.location.isEmpty {
                    Chip(text: applicant.location, systemImage: "mappin.and.ellipse")
                }
            }

            if !applicant.coverNote.isEmpty {
                Text(applicant.coverNote)
                    .font(.footnote)
                    .foregroundStyle(Theme.ink.opacity(0.9))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.ground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if applicant.presented {
                if !applicant.email.isEmpty {
                    Label(applicant.email, systemImage: "envelope")
                        .font(.footnote)
                        .foregroundStyle(Theme.navy)
                        .textSelection(.enabled)
                }
            } else {
                Notice(.info, "A consultant is assessing this candidate. Their name and resume follow when we present them.")
            }

            HStack(spacing: 14) {
                if asConsultant, applicant.resumeId != nil {
                    AsyncButton {
                        await onOpenResume()
                    } label: {
                        Label("Resume", systemImage: "doc.text")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                Menu {
                    ForEach(options, id: \.self) { state in
                        Button(state.label) { Task { await onStatus(state) } }
                    }
                } label: {
                    Label("Set status", systemImage: "arrow.triangle.branch")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Text(Format.relative(applicant.createdAt))
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
        .brandCard()
    }

    private var tint: Color {
        switch applicant.state {
        case .placed, .offer, .shortlisted: return Theme.successTint
        case .rejected, .withdrawn: return Theme.secondaryInk
        default: return Theme.navy
        }
    }
}
