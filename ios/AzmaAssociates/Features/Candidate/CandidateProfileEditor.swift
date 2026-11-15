import SwiftUI

/// The profile a consultant reads before putting someone forward.
struct CandidateProfileEditor: View {
    @Environment(AppSession.self) private var session
    @Environment(CandidateStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CandidateProfile
    @State private var errorMessage: String?

    init(profile: CandidateProfile) {
        _draft = State(initialValue: profile)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section { Notice(kind: .error, message: errorMessage) }
                }

                Section("You") {
                    TextField("Full name", text: $draft.fullName)
                        .textContentType(.name)
                    TextField("Headline, e.g. Equity PM, Tokyo", text: $draft.headline)
                    TextField("Location", text: $draft.location)
                    TextField("Phone", text: $draft.phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    TextField("LinkedIn URL", text: $draft.linkedinUrl)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Now") {
                    TextField("Current employer", text: $draft.currentEmployer)
                    TextField("Current title", text: $draft.currentTitle)
                    Stepper(
                        "Experience: \(Format.experience(draft.yearsExperience))",
                        value: $draft.yearsExperience, in: 0...70
                    )
                }

                Section {
                    LongTextField(text: $draft.summary)
                } header: {
                    Text("Summary")
                } footer: {
                    Text("What you have run, what you are known for, and what you are looking for next.")
                }

                Section("Market") {
                    MultiSelectField(title: "Sectors", options: session.options.sectors, selection: $draft.sectors, display: Format.sector)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Roles you are open to")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryInk)
                        TokenListField(title: "Roles", placeholder: "e.g. Portfolio Manager", items: $draft.desiredRoles)
                    }
                    .padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Languages")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryInk)
                        TokenListField(title: "Languages", placeholder: "e.g. Japanese", items: $draft.languages)
                    }
                    .padding(.vertical, 4)
                }

                Section("Practicalities") {
                    TextField("Work authorisation", text: $draft.workAuthorization)
                    TextField("Compensation expectation", text: $draft.salaryExpectation)
                    Toggle("Open to approaches", isOn: $draft.openToOffers)
                }
            }
            .navigationTitle("Your profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    AsyncButton {
                        await save()
                    } label: {
                        Text("Save").fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func save() async {
        if let problem = draft.problem {
            errorMessage = problem
            return
        }
        do {
            try await store.save(profile: draft)
            dismiss()
        } catch {
            errorMessage = await session.message(for: error)
        }
    }
}
