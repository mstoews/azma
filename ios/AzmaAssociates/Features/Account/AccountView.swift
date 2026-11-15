import SwiftUI

/// The account tab: signing in and out, the messages you have sent us, and
/// (in development builds) which server the app is pointed at.
struct AccountView: View {
    @Environment(AppSession.self) private var session
    @Environment(CandidateStore.self) private var candidate

    @State private var showingSignIn = false
    @State private var showingJoin = false
    @State private var showingPassword = false
    @State private var inquiries: [Inquiry] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let account = session.account {
                        accountCard(account)
                        messages
                        actions
                    } else {
                        signedOut
                    }
                    serverSection
                }
                .padding(.vertical, 18)
            }
            .brandBackground()
            .scrollIndicators(.hidden)
            .navigationTitle("Account")
            .sheet(isPresented: $showingSignIn) { NavigationStack { SignInView() } }
            .sheet(isPresented: $showingJoin) { NavigationStack { JoinView() } }
            .sheet(isPresented: $showingPassword) { ChangePasswordSheet() }
            .task(id: session.account?.id) { await loadMessages() }
        }
    }

    private func accountCard(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Circle()
                    .fill(Theme.navy.opacity(0.1))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: icon(for: account.role))
                            .foregroundStyle(Theme.navy)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name.nilIfBlank ?? account.email)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.ink)
                    Text(account.email)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryInk)
                }
                Spacer(minLength: 0)
            }
            Chip(text: account.role.title, tint: account.role == .admin ? Theme.gold : Theme.navy)
        }
        .brandCard()
        .padding(.horizontal, Theme.gutter)
    }

    private func icon(for role: Role) -> String {
        switch role {
        case .candidate: return "person.text.rectangle"
        case .employer: return "building.2"
        case .admin: return "briefcase"
        }
    }

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your account")
                    .font(Theme.display(24))
                    .foregroundStyle(Theme.ink)
                Text("Sign in to keep your resume with us, follow your applications, or manage the positions you are hiring for.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryInk)
            }
            Button("Sign in") { showingSignIn = true }
                .buttonStyle(.brand)
            Button("Create an account") { showingJoin = true }
                .buttonStyle(.brandQuiet)
        }
        .padding(.horizontal, Theme.gutter)
    }

    @ViewBuilder
    private var messages: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your messages to us")
            if let errorMessage {
                Notice(kind: .error, message: errorMessage)
            } else if inquiries.isEmpty {
                Text("Nothing yet. The Contact tab reaches a consultant directly.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryInk)
            } else {
                ForEach(inquiries) { inquiry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(inquiry.kindKind.label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Chip(
                                text: InquiryStatus(rawValue: inquiry.status)?.label ?? inquiry.status,
                                tint: inquiry.status == "new" ? Theme.warningTint : Theme.successTint
                            )
                        }
                        Text(inquiry.message)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryInk)
                            .lineLimit(3)
                        Text(Format.relative(inquiry.createdAt))
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    .brandCard(padding: 14)
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button("Change password") { showingPassword = true }
                .buttonStyle(.brandQuiet)
            AsyncButton {
                await session.signOut()
                candidate.reset()
            } label: {
                Text("Sign out")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.dangerTint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    /// Which server this build talks to. Handy on TestFlight, harmless in the
    /// App Store build, where it is read-only.
    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "About")
            VStack(alignment: .leading, spacing: 6) {
                Text("AZMA & Associates")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
                Text(AppConfig.baseURL.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryInk)
                    .textSelection(.enabled)
            }
            .brandCard(padding: 14)
        }
        .padding(.horizontal, Theme.gutter)
    }

    private func loadMessages() async {
        guard session.account != nil else {
            inquiries = []
            return
        }
        do {
            inquiries = try await session.api.fetchMyInquiries()
            errorMessage = nil
        } catch {
            // A failure here is not worth interrupting the screen for.
            inquiries = []
            errorMessage = nil
        }
    }
}

struct ChangePasswordSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var updated = ""
    @State private var errorMessage: String?
    @State private var done = false

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section { Notice(kind: .error, message: errorMessage) }
                }
                if done {
                    Section {
                        Notice(.success, "Password changed. Other devices have been signed out.")
                    }
                } else {
                    Section("Current password") {
                        SecureField("Current password", text: $current)
                            .textContentType(.password)
                    }
                    Section {
                        SecureField("New password", text: $updated)
                            .textContentType(.newPassword)
                    } header: {
                        Text("New password")
                    } footer: {
                        Text("At least \(session.options.minPasswordLength) characters.")
                    }
                }
            }
            .navigationTitle("Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(done ? "Done" : "Cancel") { dismiss() }
                }
                if !done {
                    ToolbarItem(placement: .topBarTrailing) {
                        AsyncButton {
                            await change()
                        } label: {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func change() async {
        guard updated.count >= session.options.minPasswordLength else {
            errorMessage = String(localized: "Passwords need at least \(session.options.minPasswordLength) characters.")
            return
        }
        do {
            try await session.api.changePassword(current: current, new: updated)
            errorMessage = nil
            done = true
        } catch {
            errorMessage = await session.message(for: error)
        }
    }
}
