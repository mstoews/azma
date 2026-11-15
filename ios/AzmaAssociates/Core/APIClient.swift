import Foundation

/// The one place HTTP happens.
///
/// The bearer token lives in an actor so it can be read and replaced from any
/// task; everything else here is immutable.
final class APIClient: Sendable {
    private actor TokenBox {
        private var token: String?
        func get() -> String? { token }
        func set(_ value: String?) { token = value }
    }

    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession
    private let tokenBox = TokenBox()

    init(baseURL: URL = AppConfig.baseURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 20
            config.waitsForConnectivity = false
            // Content is cached deliberately in SiteStore; responses here are
            // per-session data that must not come from a shared cache.
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    func setToken(_ token: String?) async { await tokenBox.set(token) }
    func currentToken() async -> String? { await tokenBox.get() }

    // MARK: - Requests

    func get<T: Decodable & Sendable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        try await send(request(path, method: "GET", query: query))
    }

    func post<T: Decodable & Sendable>(_ path: String, body: (some Encodable & Sendable)? = Empty?.none) async throws -> T {
        try await send(request(path, method: "POST", body: body))
    }

    func put<T: Decodable & Sendable>(_ path: String, body: (some Encodable & Sendable)? = Empty?.none) async throws -> T {
        try await send(request(path, method: "PUT", body: body))
    }

    /// For the endpoints that answer 204.
    func send(_ path: String, method: String, body: (some Encodable & Sendable)? = Empty?.none) async throws {
        _ = try await data(for: request(path, method: method, body: body))
    }

    func delete(_ path: String) async throws {
        _ = try await data(for: request(path, method: "DELETE"))
    }

    /// Uploads one file as `multipart/form-data` with a `file` field, the shape
    /// both the media library and the resume endpoint expect.
    func upload<T: Decodable & Sendable>(
        _ path: String, fileURL: URL, filename: String, contentType: String
    ) async throws -> T {
        let boundary = "azma.\(UUID().uuidString)"
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        body.append(try Data(contentsOf: fileURL))
        append("\r\n--\(boundary)--\r\n")

        var req = try request(path, method: "POST")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return try await send(req)
    }

    /// Streams a file (a resume) to a temporary location for previewing.
    func download(_ path: String, suggestedName: String) async throws -> URL {
        let req = try request(path, method: "GET")
        let (data, _) = try await self.data(for: req)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("azma-downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(suggestedName.isEmpty ? "document" : suggestedName)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Plumbing

    struct Empty: Codable, Sendable {}

    private func request(
        _ path: String, method: String, query: [String: String?] = [:],
        body: (some Encodable & Sendable)? = Empty?.none
    ) throws -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path),
            resolvingAgainstBaseURL: true
        )
        let items = query.compactMap { key, value -> URLQueryItem? in
            guard let value, !value.isEmpty else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        if !items.isEmpty { components?.queryItems = items.sorted { $0.name < $1.name } }
        guard let url = components?.url else { throw APIError.network("Bad URL for \(path)") }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = try JSONEncoder.azma.encode(body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func send<T: Decodable & Sendable>(_ request: URLRequest) async throws -> T {
        let (data, _) = try await self.data(for: request)
        if T.self == Empty.self { return APIClient.Empty() as! T }
        do {
            return try JSONDecoder.azma.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    /// Performs the request, attaching the bearer token and turning non-2xx
    /// responses into `APIError`s.
    private func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        if let token = await tokenBox.get() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed, .networkConnectionLost:
                throw APIError.offline
            default:
                throw APIError.network(error.localizedDescription)
            }
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.server(status: http.statusCode, message: Self.message(from: data, status: http.statusCode))
        }
        return (data, http)
    }

    private static func message(from data: Data, status: Int) -> String {
        struct ServerError: Decodable { let error: String }
        if let decoded = try? JSONDecoder().decode(ServerError.self, from: data), !decoded.error.isEmpty {
            // Server messages are written for the person reading them.
            return decoded.error.prefix(1).uppercased() + decoded.error.dropFirst()
        }
        switch status {
        case 403: return "You do not have access to that."
        case 404: return "That is no longer available."
        case 409: return "That conflicts with something that already exists."
        case 413: return "That file is too large."
        case 429: return "Too many requests. Please try again shortly."
        default: return "The server returned an error (\(status))."
        }
    }
}

extension JSONDecoder {
    /// Go's `time.Time` marshals as RFC 3339, with fractional seconds only
    /// when the value has them.
    static let azma: JSONDecoder = {
        let decoder = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: raw) ?? plain.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unrecognised date \(raw)")
            )
        }
        return decoder
    }()
}

extension JSONEncoder {
    static let azma: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
