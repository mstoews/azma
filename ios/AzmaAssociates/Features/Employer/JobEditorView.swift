import SwiftUI

/// Writing or editing a position. Saving keeps it private; submitting sends it
/// to a consultant, which is also what takes a live posting back off the board
/// while the change is reviewed.
struct JobEditorView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    private let existing: Job?
    private let onSaved: (Job) -> Void

    @State private var draft: JobInput
    @State private var salaryMin: String
    @State private var salaryMax: String
    @State private var errorMessage: String?

    init(existing: Job?, defaultCompany: String, onSaved: @escaping (Job) -> Void) {
        self.existing = existing
        self.onSaved = onSaved
        var input = existing.map(JobInput.init(job:)) ?? JobInput()
        if input.company.isEmpty { input.company = defaultCompany }
        _draft = State(initialValue: input)
        _salaryMin = State(initialValue: input.salaryMin.map(String.init) ?? "")
        _salaryMax = State(initialValue: input.salaryMax.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section { Notice(kind: .error, message: errorMessage) }
                }
                if existing?.isOnBoard == true {
                    Section {
                        Notice(kind: .warning, message: "This position is live. Submitting changes takes it off the board until a consultant has looked at them.")
                    }
                }

                Section("The position") {
                    TextField("Title", text: $draft.title)
                    TextField("Company", text: $draft.company)
                    Toggle("Confidential search", isOn: $draft.confidential)
                    if draft.confidential {
                        Text("Candidates see “Confidential client” instead of your name. Consultants always see it.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }

                Section("Where and how") {
                    TextField("Location", text: $draft.location)
                    Toggle("Remote possible", isOn: $draft.remote)
                    Picker("Sector", selection: $draft.sector) {
                        Text("Not specified").tag("")
                        ForEach(session.options.sectors, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Type", selection: $draft.employmentType) {
                        ForEach(session.options.employmentTypes, id: \.self) {
                            Text(Format.employmentType($0)).tag($0)
                        }
                    }
                }

                Section {
                    LongTextField(text: $draft.description, minHeight: 150)
                } header: {
                    Text("About the position")
                } footer: {
                    Text("The team, the mandate, who the role reports to, and why it is open.")
                }

                Section {
                    LongTextField(text: $draft.requirements, minHeight: 110)
                } header: {
                    Text("What you are looking for")
                }

                Section {
                    Picker("Currency", selection: $draft.salaryCurrency) {
                        Text("Not shown").tag("")
                        ForEach(session.options.currencies, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Minimum", text: $salaryMin)
                        .keyboardType(.numberPad)
                    TextField("Maximum", text: $salaryMax)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Compensation")
                } footer: {
                    Text("Shown on the board. Leave blank to discuss it with the consultant instead.")
                }
            }
            .navigationTitle(existing == nil ? "New position" : "Edit position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Save as draft") { Task { await save(submit: false) } }
                        Button("Submit for review") { Task { await save(submit: true) } }
                    } label: {
                        Text("Save").fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func save(submit: Bool) async {
        var input = draft
        input.submit = submit
        input.salaryMin = Int(salaryMin.trimmed)
        input.salaryMax = Int(salaryMax.trimmed)
        if let problem = input.problem {
            errorMessage = problem
            return
        }
        do {
            let saved: Job = if let existing {
                try await session.api.updateJob(id: existing.id, input: input)
            } else {
                try await session.api.createJob(input)
            }
            onSaved(saved)
            dismiss()
        } catch {
            errorMessage = await session.message(for: error)
        }
    }
}
