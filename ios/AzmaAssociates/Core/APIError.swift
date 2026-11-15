import Foundation

/// Everything a request can fail with, in terms the UI can show someone.
enum APIError: LocalizedError, Equatable {
    /// The session is gone; the caller signs out.
    case unauthorized
    /// The server said no, with its own message (`{"error": "…"}`).
    case server(status: Int, message: String)
    case offline
    case network(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return String(localized: "Your session has expired. Please sign in again.")
        case let .server(_, message):
            return message
        case .offline:
            return String(localized: "You appear to be offline. Check your connection and try again.")
        case let .network(detail):
            return String(localized: "The server could not be reached. \(detail)")
        case let .decoding(detail):
            return String(localized: "The server sent something unexpected. \(detail)")
        }
    }

    /// True when retrying the same request might work.
    var isRetryable: Bool {
        switch self {
        case .offline, .network: return true
        case let .server(status, _): return status >= 500
        case .unauthorized, .decoding: return false
        }
    }
}
