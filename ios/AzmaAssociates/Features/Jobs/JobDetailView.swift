import SwiftUI

/// One position, with everything a candidate needs to decide whether to put
/// themselves forward.
struct JobDetailView: View {
    let job: Job

    @Environment(AppSession.self) private var session
    @Environment(CandidateStore.self) private var candidate
    @State private var showingApply = false
    @State private var showingJoin = false
    @State private var message: String?

    private var application: Application? { candidate.application(for: job.id) }
    private var isSaved: Bool { candidate.savedJobIDs.contains(job.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let message {
                    Notice(kind: .info, message: message)
                        .padding(.horizontal, Theme.gutter)
                }
                if job.confidential {
                    Notice(.info, "This is a confidential search. The client is named once a consultant has spoken with you.")
                        .padding(.horizontal, Theme.gutter)
                }
                details
                if !job.description.isEmpty {
                    section("About the position", body: job.description)
                }
                if !job.requirements.isEmpty {
                    section("What they are looking for", body: job.requirements)
                }
                actions
                processNote
            }
            .padding(.bottom, 40)
        }
        .brandBackground()
        .navigationTitle(job.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.isCandidate {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await candidate.toggleSaved(job) }
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(isSaved ? Theme.gold : Theme.navy)
                    }
                    .accessibilityLabel(isSaved ? "Remove from saved" : "Save this position")
                }
            }
        }
        .sheet(isPresented: $showingApply) {
            ApplySheet(job: job)
        }
        .sheet(isPresented: $showingJoin) {
            NavigationStack { JoinView(preferred: .candidate) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(job.title)
                .font(Theme.display(26))
                .foregroundStyle(Theme.ink)
            Text(job.company)
                .font(.headline)
                .foregroundStyle(job.confidential ? Theme.secondaryInk : Theme.navy)
            FlowLayout(spacing: 6) {
                if !job.location.isEmpty { Chip(text: job.location, systemImage: "mappin.and.ellipse") }
                if job.remote { Chip("Remote", systemImage: "wifi") }
                Chip(text: Format.employmentType(job.employmentType))
                if !job.sector.isEmpty { Chip(text: Format.sector(job.sector)) }
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var details: some View {
        if let salary = Format.salary(min: job.salaryMin, max: job.salaryMax, currency: job.salaryCurrency) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Compensation")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.secondaryInk)
                Text(salary)
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.ink)
            }
            .brandCard()
            .padding(.horizontal, Theme.gutter)
        }
    }

    private func section(_ title: LocalizedStringKey, body text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title)
            Text(text)
                .font(.body)
                .foregroundStyle(Theme.ink.opacity(0.9))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.gutter)
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if let application {
                Notice(
                    kind: application.state.isOpen ? .success : .info,
                    message: String(localized: "You applied \(Format.relative(application.createdAt).lowercased()). \(application.state.candidateExplanation)")
                )
            } else if session.isCandidate {
                Button("Apply for this position") { showingApply = true }
                    .buttonStyle(.brand)
                Button(isSaved ? "Saved" : "Save for later") {
                    Task { await candidate.toggleSaved(job) }
                }
                .buttonStyle(.brandQuiet)
            } else if session.isEmployer || session.isConsultant {
                Notice(.info, session.role == .admin
                    ? "You are signed in to a consultant account. Applications come from candidate accounts."
                    : "You are signed in to a hiring account. Applications come from candidate accounts.")
            } else {
                Button("Create an account to apply") { showingJoin = true }
                    .buttonStyle(.brand)
                Text("Already with us? Sign in from the Account tab.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryInk)
            }

            NavigationLink {
                ContactView(prefill: InquiryInput(
                    kind: InquiryKind.career.rawValue,
                    message: String(localized: "I would like to know more about \(job.title) (reference \(job.id)).")
                ))
            } label: {
                Text("Ask a consultant about this position")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.navy)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, Theme.gutter)
    }

    private var processNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How this works")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("A consultant reviews every application, assesses fit against the brief, and presents a shortlist to the client. Your details are not passed on until we have spoken.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryInk)
        }
        .brandCard()
        .padding(.horizontal, Theme.gutter)
    }
}

/// Choosing which resume to send, and a note to the consultant.
struct ApplySheet: View {
    let job: Job

    @Environment(CandidateStore.self) private var candidate
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var selectedResume: Int64?
    @State private var coverNote = ""
    @State private var errorMessage: String?
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            Group {
                if candidate.resumes.isEmpty {
                    EmptyStateView(
                        icon: "doc.badge.plus",
                        title: "Add your resume first",
                        message: "We present candidates with their resume, so there is one on file before an application goes anywhere.",
                        actionTitle: "Close",
                        action: { dismiss() }
                    )
                } else if didSubmit {
                    EmptyStateView(
                        icon: "checkmark.seal.fill",
                        title: "Application sent",
                        message: "A consultant will read it and come back to you. You can follow it under My career.",
                        actionTitle: "Done",
                        action: { dismiss() }
                    )
                } else {
                    form
                }
            }
            .brandBackground()
            .navigationTitle(didSubmit ? "" : "Apply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !didSubmit {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .onAppear { selectedResume = candidate.latestResume?.id }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.ink)
                    Text(job.company)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                }
                .brandCard()

                if let errorMessage {
                    Notice(kind: .error, message: errorMessage)
                }

                FieldRow(title: "Resume to send") {
                    VStack(spacing: 0) {
                        ForEach(candidate.resumes) { resume in
                            Button {
                                selectedResume = resume.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(resume.filename)
                                            .font(.subheadline)
                                            .foregroundStyle(Theme.ink)
                                            .lineLimit(1)
                                        Text("\(Format.fileSize(resume.sizeBytes)) · \(Format.relative(resume.createdAt))")
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryInk)
                                    }
                                    Spacer()
                                    Image(systemName: selectedResume == resume.id ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(selectedResume == resume.id ? Theme.navy : Theme.secondaryInk)
                                }
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if resume.id != candidate.resumes.last?.id {
                                Divider().overlay(Theme.hairline)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 1)
                    )
                }

                FieldRow(title: "Note to the consultant", hint: Text("Why this position, and anything the resume does not say.")) {
                    TextEditor(text: $coverNote)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Theme.hairline, lineWidth: 1)
                        )
                }

                AsyncButton {
                    await submit()
                } label: {
                    Text("Send application")
                }
                .buttonStyle(.brand)
            }
            .padding(Theme.gutter)
        }
    }

    private func submit() async {
        do {
            try await candidate.apply(to: job, resumeID: selectedResume, coverNote: coverNote)
            didSubmit = true
            errorMessage = nil
        } catch {
            errorMessage = await session.message(for: error)
        }
    }
}
