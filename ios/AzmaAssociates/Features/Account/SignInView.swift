import SwiftUI

struct SignInView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sign in")
                        .font(Theme.display(26))
                        .foregroundStyle(Theme.ink)
                    Text("Candidates, clients and AZMA consultants all sign in here.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                }
                .padding(.top, 12)

                if let errorMessage {
                    Notice(kind: .error, message: errorMessage)
                }

                FieldRow(title: "Email") {
                    TextField("you@example.com", text: $email)
                        .textFieldStyle(.brand)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                FieldRow(title: "Password") {
                    SecureField("Password", text: $password)
                        .textFieldStyle(.brand)
                        .textContentType(.password)
                        .onSubmit { Task { await signIn() } }
                }
                AsyncButton {
                    await signIn()
                } label: {
                    Text("Sign in")
                }
                .buttonStyle(.brand)
            }
            .padding(Theme.gutter)
        }
        .brandBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
        }
    }

    private func signIn() async {
        guard email.isValidEmail, !password.isEmpty else {
            errorMessage = "Enter your email address and password."
            return
        }
        do {
            try await session.signIn(email: email, password: password)
            errorMessage = nil
            dismiss()
        } catch {
            errorMessage = await session.message(for: error)
        }
    }
}
