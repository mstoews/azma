import SwiftUI

/// Creating an account. Which side someone is on decides what the app shows
/// them afterwards, so it is the first thing asked.
struct JoinView: View {
    var preferred: Role = .candidate

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var role: Role
    @State private var name = ""
    @State private var company = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var showingSignIn = false

    init(preferred: Role = .candidate) {
        self.preferred = preferred
        _role = State(initialValue: preferred)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Join AZMA & Associates")
                        .font(Theme.display(26))
                        .foregroundStyle(Theme.ink)
                    Text("One account, either side of a search.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 12)

                VStack(spacing: 10) {
                    ForEach([Role.candidate, Role.employer], id: \.self) { option in
                        Button {
                            role = option
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: role == option ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(role == option ? Theme.navy : Theme.secondaryInk)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                    Text(option.blurb)
                                        .font(.footnote)
                                        .foregroundStyle(Theme.secondaryInk)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .brandCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.gutter)

                VStack(alignment: .leading, spacing: 16) {
                    if let errorMessage {
                        Notice(kind: .error, message: errorMessage)
                    }
                    FieldRow(title: role == .employer ? "Your name" : "Full name") {
                        TextField("Name", text: $name)
                            .textFieldStyle(.brand)
                            .textContentType(.name)
                    }
                    if role == .employer {
                        FieldRow(title: "Company") {
                            TextField("Company", text: $company)
                                .textFieldStyle(.brand)
                                .textContentType(.organizationName)
                        }
                    }
                    FieldRow(title: "Email") {
                        TextField("you@example.com", text: $email)
                            .textFieldStyle(.brand)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    FieldRow(title: "Password", hint: "At least \(session.options.minPasswordLength) characters.") {
                        SecureField("Password", text: $password)
                            .textFieldStyle(.brand)
                            .textContentType(.newPassword)
                    }
                    AsyncButton {
                        await join()
                    } label: {
                        Text("Create account")
                    }
                    .buttonStyle(.brand)

                    Button("I already have an account") { showingSignIn = true }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Theme.gutter)

                Text("By creating an account you agree that AZMA & Associates may hold the details and documents you provide in order to represent you.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryInk)
                    .padding(.horizontal, Theme.gutter)
            }
            .padding(.bottom, 32)
        }
        .brandBackground()
        .navigationTitle("Join")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSignIn) {
            NavigationStack { SignInView() }
        }
    }

    private func join() async {
        guard !name.trimmed.isEmpty else {
            errorMessage = "Your name is required."
            return
        }
        guard email.isValidEmail else {
            errorMessage = "A valid email address is required."
            return
        }
        guard password.count >= session.options.minPasswordLength else {
            errorMessage = "Passwords need at least \(session.options.minPasswordLength) characters."
            return
        }
        if role == .employer, company.trimmed.isEmpty {
            errorMessage = "Your company name is required."
            return
        }
        do {
            try await session.register(email: email, password: password, role: role, name: name, company: company)
            errorMessage = nil
            dismiss()
        } catch {
            errorMessage = await session.message(for: error)
        }
    }
}
