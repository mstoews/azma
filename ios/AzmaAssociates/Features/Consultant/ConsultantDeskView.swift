import SwiftUI

/// The consultant's desk: postings waiting for a decision, the candidates who
/// have asked to be represented, and the consultation requests that came in.
struct ConsultantDeskView: View {
    enum Desk: String, CaseIterable, Identifiable {
        case review = "Postings"
        case candidates = "Candidates"
        case inquiries = "Requests"
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .review: return "Postings"
            case .candidates: return "Candidates"
            case .inquiries: return "Requests"
            }
        }
    }

    @State private var desk: Desk = .review

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Desk", selection: $desk) {
                    ForEach(Desk.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 10)

                switch desk {
                case .review: ReviewQueueView()
                case .candidates: CandidateDirectoryView()
                case .inquiries: InquiryInboxView()
                }
            }
            .brandBackground()
            .navigationTitle("Desk")
            .navigationDestination(for: Job.self) { job in
                ApplicantsView(job: job, asConsultant: true)
            }
            .navigationDestination(for: CandidateSummary.self) { summary in
                CandidateDetailView(userID: summary.userId)
            }
        }
    }
}

/// Postings an employer has submitted, newest first with pending at the top.
struct ReviewQueueView: View {
    @Environment(AppSession.self) private var session
    @State private var jobs: [Job] = []
    @State private var counts: [String: Int] = [:]
    @State private var filter = "pending"
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var decision: Decision?

    private struct Decision: Identifiable {
        let job: Job
        let approve: Bool
        var id: Int64 { job.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                filterRow
                if let errorMessage {
                    Notice(kind: .error, message: errorMessage)
                        .padding(.horizontal, Theme.gutter)
                }
                if isLoading && jobs.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if jobs.isEmpty {
                    EmptyStateView(
                        icon: "checkmark.circle",
                        title: filter == "pending" ? "Nothing waiting" : "Nothing here",
                        message: filter == "pending"
                            ? "Every posting a client has submitted has been dealt with."
                            : "No postings with this status."
                    )
                } else {
                    ForEach(jobs) { job in
                        ReviewCard(
                            job: job,
                            onApprove: { decision = Decision(job: job, approve: true) },
                            onReject: { decision = Decision(job: job, approve: false) },
                            onTakeDown: { await setStatus(job, status: "closed", note: "") }
                        )
                        .padding(.horizontal, Theme.gutter)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $decision) { decision in
            ReviewDecisionSheet(job: decision.job, approve: decision.approve) { status, note in
                await setStatus(decision.job, status: status, note: note)
            }
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["pending", "published", "draft", "filled", "closed", "rejected"], id: \.self) { status in
                    let label = JobStatus(rawValue: status)?.label ?? status
                    let count = counts[status] ?? 0
                    Button {
                        filter = status
                        Task { await load() }
                    } label: {
                        Text(count > 0 ? "\(label) (\(count))" : label)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                filter == status ? Theme.navy : Theme.card,
                                in: Capsule()
                            )
                            .foregroundStyle(filter == status ? Color.white : Theme.ink)
                            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: filter == status ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await session.api.fetchReviewQueue(status: filter)
            jobs = page.jobs
            counts = page.countsByStatus
            errorMessage = nil
        } catch {
            errorMessage = await session.message(for: error)
        }
    }

    private func setStatus(_ job: Job, status: String, note: String) async {
        do {
            _ = try await session.api.review(jobId: job.id, status: status, note: note)
            await load()
        } catch {
            errorMessage = await session.message(for: error)
        }
    }
}

private struct ReviewCard: View {
    let job: Job
    let onApprove: () -> Void
    let onReject: () -> Void
    let onTakeDown: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.ink)
                    Text(job.company)
                        .font(.subheadline)
                        .foregroundStyle(Theme.navy)
                    if let email = job.employerEmail {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryInk)
                            .textSelection(.enabled)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Chip(text: job.statusKind.label, tint: job.statusKind == .pending ? Theme.warningTint : Theme.secondaryInk)
                    if job.confidential {
                        Chip("Confidential", systemImage: "eye.slash", tint: Theme.secondaryInk)
                    }
                }
            }

            FlowLayout(spacing: 6) {
                if !job.location.isEmpty { Chip(text: job.location, systemImage: "mappin.and.ellipse") }
                if !job.sector.isEmpty { Chip(text: Format.sector(job.sector)) }
                Chip(text: Format.employmentType(job.employmentType))
                if let salary = Format.salary(min: job.salaryMin, max: job.salaryMax, currency: job.salaryCurrency) {
                    Chip(text: salary, tint: Theme.successTint)
                }
            }

            if !job.description.isEmpty {
                Text(job.description)
                    .font(.footnote)
                    .foregroundStyle(Theme.ink.opacity(0.9))
                    .lineLimit(6)
            }
            if !job.requirements.isEmpty {
                Text(job.requirements)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(4)
            }
            if let note = job.reviewNote, !note.isEmpty {
                Notice(.info, "Last note: \(note)")
            }

            HStack(spacing: 14) {
                if job.statusKind == .pending {
                    Button("Publish", action: onApprove)
                        .font(.subheadline.weight(.semibold))
                    Button("Send back", action: onReject)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.dangerTint)
                } else if job.isOnBoard {
                    AsyncButton {
                        await onTakeDown()
                    } label: {
                        Text("Take off the board")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.dangerTint)
                    }
                }
                Spacer()
                if let count = job.applicationCount, count > 0 {
                    NavigationLink(value: job) {
                        Text(count == 1 ? "1 applicant" : "\(count) applicants")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .brandCard()
    }
}

/// Approving needs no words; sending one back does.
private struct ReviewDecisionSheet: View {
    let job: Job
    let approve: Bool
    let onDecide: (String, String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(job.title).font(.headline)
                    Text(job.company).font(.subheadline).foregroundStyle(Theme.secondaryInk)
                }
                Section {
                    LongTextField(text: $note, minHeight: 120)
                } header: {
                    Text(approve ? "Note to the client (optional)" : "Why it is going back")
                } footer: {
                    Text(approve
                         ? "Publishing puts the position on the board straight away."
                         : "The client sees this note on their posting, so say what would make it work.")
                }
            }
            .navigationTitle(approve ? "Publish position" : "Send back")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    AsyncButton {
                        await onDecide(approve ? "published" : "rejected", note)
                        dismiss()
                    } label: {
                        Text(approve ? "Publish" : "Send back").fontWeight(.semibold)
                    }
                    .disabled(!approve && note.trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
