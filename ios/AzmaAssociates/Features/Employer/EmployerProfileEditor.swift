import SwiftUI

struct EmployerProfileEditor: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var draft: EmployerProfile
    @State private var errorMessage: String?
    private let onSaved: (EmployerProfile) -> Void

    init(profile: EmployerProfile, onSaved: @escaping (EmployerProfile) -> Void) {
        _draft = State(initialValue: profile)
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section { Notice(kind: .error, message: errorMessage) }
                }
                Section("Company") {
                    TextField("Company name", text: $draft.company)
                    TextField("Location", text: $draft.location)
                    TextField("Website", text: $draft.website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Who we speak to") {
                    TextField("Contact name", text: $draft.contactName)
                        .textContentType(.name)
                    TextField("Role, e.g. Head of HR", text: $draft.contactRole)
                    TextField("Phone", text: $draft.phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
                Section {
                    LongTextField(text: $draft.about, minHeight: 110)
                } header: {
                    Text("About the business")
                } footer: {
                    Text("Context a consultant can use when approaching candidates on your behalf.")
                }
            }
            .navigationTitle("Your company")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
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
            let saved = try await session.api.saveEmployerProfile(draft)
            onSaved(saved)
            dismiss()
        } catch {
            errorMessage = await session.message(for: error)
        }
    }
}
