import XCTest
@testable import AZMA

/// Exercises the client against a stubbed URL protocol: the bearer token, the
/// query it builds, and how it turns the server's replies into `APIError`s.
final class APIClientTests: XCTestCase {
    private var client: APIClient!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        client = APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            session: URLSession(configuration: configuration)
        )
    }

    override func tearDown() {
        StubURLProtocol.reset()
        client = nil
        super.tearDown()
    }

    func testBuildsQueryAndDecodesJobs() async throws {
        StubURLProtocol.respond { _ in
            (200, Data("""
            {"jobs":[{"id":7,"title":"Portfolio Manager","company":"Nippon Asset","confidential":false,
            "location":"Tokyo","remote":false,"sector":"Asset Management","employmentType":"full_time",
            "description":"d","requirements":"r","salaryMin":25000000,"salaryMax":null,"salaryCurrency":"JPY",
            "status":"published","publishedAt":"2026-11-14T09:00:00Z","createdAt":"2026-11-01T09:00:00.512Z",
            "updatedAt":"2026-11-02T09:00:00Z"}],"total":1,"limit":25,"offset":0}
            """.utf8))
        }
        let page = try await client.fetchJobs(search: "japan equities", sector: "Asset Management", remoteOnly: true)
        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.jobs.first?.title, "Portfolio Manager")
        XCTAssertEqual(page.jobs.first?.salaryMin, 25_000_000)
        XCTAssertNil(page.jobs.first?.salaryMax)
        XCTAssertNotNil(page.jobs.first?.publishedAt, "RFC 3339 without fractional seconds must decode")
        XCTAssertNotNil(page.jobs.first?.createdAt)

        let query = StubURLProtocol.lastRequest?.url?.query ?? ""
        XCTAssertTrue(query.contains("q=japan%20equities") || query.contains("q=japan+equities"), query)
        XCTAssertTrue(query.contains("remote=1"), query)
        XCTAssertFalse(query.contains("employmentType"), "empty filters are left out: \(query)")
    }

    func testSendsBearerTokenOnceSet() async throws {
        StubURLProtocol.respond { _ in (200, Data(#"{"user":{"id":"1","email":"a@b.com","name":"A","role":"candidate"},"expiresAt":"2026-11-14T09:00:00Z"}"#.utf8)) }
        await client.setToken("secret-token")
        _ = try await client.fetchMe()
        XCTAssertEqual(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")

        await client.setToken(nil)
        _ = try await client.fetchMe()
        XCTAssertNil(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    func testUnauthorizedIsItsOwnError() async {
        StubURLProtocol.respond { _ in (401, Data(#"{"error":"session invalid or expired"}"#.utf8)) }
        do {
            _ = try await client.fetchCandidateOverview()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
    }

    func testServerMessageIsShownToThePerson() async {
        StubURLProtocol.respond { _ in (409, Data(#"{"error":"you have already applied for this position"}"#.utf8)) }
        do {
            try await client.apply(jobId: 1, resumeId: nil, coverNote: "")
            XCTFail("expected an error")
        } catch let error as APIError {
            XCTAssertEqual(error.errorDescription, "You have already applied for this position")
            XCTAssertFalse(error.isRetryable)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testServerErrorsAreRetryable() async {
        StubURLProtocol.respond { _ in (503, Data()) }
        do {
            _ = try await client.fetchSite()
            XCTFail("expected an error")
        } catch let error as APIError {
            XCTAssertTrue(error.isRetryable)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testPostSendsAJSONBody() async throws {
        StubURLProtocol.respond { _ in
            (201, Data(#"{"id":1,"kind":"hiring","name":"Hiro","email":"h@example.com","phone":"","company":"","office":"tokyo","message":"m","status":"new","handledAt":null,"createdAt":"2026-11-14T09:00:00Z"}"#.utf8))
        }
        var input = InquiryInput()
        input.name = "Hiro"
        input.email = "h@example.com"
        input.message = "m"
        input.office = "tokyo"
        let inquiry = try await client.sendInquiry(input)

        XCTAssertEqual(inquiry.status, "new")
        XCTAssertEqual(StubURLProtocol.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(StubURLProtocol.lastBody)
        let decoded = try JSONDecoder().decode(InquiryInput.self, from: body)
        XCTAssertEqual(decoded.office, "tokyo")
    }

    func testOfflineIsReportedAsSuch() async {
        StubURLProtocol.fail(with: URLError(.notConnectedToInternet))
        do {
            _ = try await client.fetchSite()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .offline)
        }
    }
}

/// A URLProtocol that answers from a closure, and remembers what it was asked.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private struct State {
        var handler: ((URLRequest) -> (Int, Data))?
        var failure: Error?
        var lastRequest: URLRequest?
        var lastBody: Data?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var state = State()

    static func respond(_ handler: @escaping (URLRequest) -> (Int, Data)) {
        lock.withLock { state.handler = handler; state.failure = nil }
    }

    static func fail(with error: Error) {
        lock.withLock { state.failure = error; state.handler = nil }
    }

    static func reset() {
        lock.withLock { state = State() }
    }

    static var lastRequest: URLRequest? { lock.withLock { state.lastRequest } }
    static var lastBody: Data? { lock.withLock { state.lastBody } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLProtocol strips httpBody into a stream, so it is read back here.
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let size = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: size)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            body = data
        }
        let outcome: (handler: ((URLRequest) -> (Int, Data))?, failure: Error?) = Self.lock.withLock {
            Self.state.lastRequest = request
            Self.state.lastBody = body
            return (Self.state.handler, Self.state.failure)
        }

        if let failure = outcome.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let (status, data) = outcome.handler?(request) ?? (200, Data())
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
