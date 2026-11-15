import Foundation
import Observation

/// Who is signed in, and the one place the token is set or cleared.
@MainActor
@Observable
final class AppSession {
    enum Phase: Equatable {
        /// Restoring a saved session; the app shows its launch state.
        case starting
        case signedOut
        case signedIn
    }

    private(set) var phase: Phase = .starting
    private(set) var account: Account?
    /// Pickers come from the server so they cannot drift from what it accepts.
    private(set) var options: ServerOptions = .fallback

    let api: APIClient
    private static let tokenKey = "session-token"

    init(api: APIClient = .shared) {
        self.api = api
    }

    var role: Role? { account?.role }
    var isConsultant: Bool { account?.role == .admin }
    var isCandidate: Bool { account?.role == .candidate }
    var isEmployer: Bool { account?.role == .employer }

    /// Called once at launch: restores a saved session and loads the server's
    /// vocabulary. Neither failing stops the app — the public side works
    /// signed out and `ServerOptions.fallback` covers the pickers.
    func start() async {
        async let optionsTask: Void = loadOptions()
        if let token = Keychain.string(for: Self.tokenKey) {
            await api.setToken(token)
            do {
                account = try await api.fetchMe().user
                phase = .signedIn
            } catch APIError.unauthorized {
                await clearSession()
            } catch {
                // Offline with a saved token: stay signed in and let the next
                // request decide, rather than throwing the person out.
                phase = account == nil ? .signedOut : .signedIn
            }
        } else {
            phase = .signedOut
        }
        await optionsTask
    }

    func loadOptions() async {
        if let fetched = try? await api.fetchOptions() { options = fetched }
    }

    func signIn(email: String, password: String) async throws {
        let response = try await api.signIn(email: email.trimmed, password: password)
        await adopt(response)
    }

    func register(email: String, password: String, role: Role, name: String, company: String) async throws {
        let response = try await api.register(
            email: email.trimmed, password: password, role: role,
            name: name.trimmed, company: company.trimmed
        )
        await adopt(response)
    }

    func signOut() async {
        // Best effort: the local session is cleared whether or not the server
        // is reachable to revoke it.
        try? await api.signOut()
        await clearSession()
    }

    /// Called when a request comes back 401: the session died server-side.
    func sessionExpired() async {
        await clearSession()
    }

    func refreshAccount() async {
        guard phase == .signedIn else { return }
        if let me = try? await api.fetchMe() { account = me.user }
    }

    private func adopt(_ response: AuthResponse) async {
        Keychain.set(response.token, for: Self.tokenKey)
        await api.setToken(response.token)
        account = response.user
        phase = .signedIn
    }

    private func clearSession() async {
        Keychain.remove(Self.tokenKey)
        await api.setToken(nil)
        account = nil
        phase = .signedOut
    }
}

extension AppSession {
    /// Turns a thrown error into something worth showing someone — and signs
    /// out first when the server says the session is gone, so the app does not
    /// keep making requests that cannot succeed.
    func message(for error: Error) async -> String {
        if let apiError = error as? APIError {
            if apiError == .unauthorized { await sessionExpired() }
            return apiError.errorDescription ?? "Something went wrong."
        }
        return error.localizedDescription
    }
}
