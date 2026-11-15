import Foundation
import Observation

/// The published web site: settings, pages and the consultants.
///
/// One request covers all of it, and the last good response is kept on disk so
/// the app opens with content rather than a spinner — and still has something
/// to show on a train with no signal.
@MainActor
@Observable
final class SiteStore {
    private(set) var content: SiteContent = .empty
    private(set) var isLoading = false
    private(set) var loadFailed = false
    /// False until either the cache or the network has answered.
    private(set) var hasContent = false

    private let api: APIClient
    private let cacheURL: URL?

    init(api: APIClient = .shared) {
        self.api = api
        cacheURL = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("azma-site.json")
    }

    func load(force: Bool = false) async {
        if !force, hasContent, !loadFailed { return }
        if !hasContent { restoreFromCache() }
        isLoading = true
        defer { isLoading = false }
        do {
            content = try await api.fetchSite()
            hasContent = true
            loadFailed = false
            persist(content)
        } catch {
            loadFailed = !hasContent
        }
    }

    // MARK: Lookups

    func page(slug: String) -> SitePage? {
        content.pages.first { $0.slug == slug }
    }

    func page(titleContains needle: String) -> SitePage? {
        content.pages.first { $0.title.localizedCaseInsensitiveContains(needle) }
    }

    func consultant(slug: String) -> ConsultantProfile? {
        content.profiles.first { $0.slug == slug }
    }

    /// The pages the app links to by name, with the web site's own wording as
    /// the fallback when the CMS has renamed or removed one.
    var aboutPage: SitePage? { page(titleContains: "Who We Are") }
    var expertisePage: SitePage? { page(titleContains: "Expertise") }
    var processPage: SitePage? { page(titleContains: "Search Process") }
    var visionPage: SitePage? { page(titleContains: "Vision") }
    var contactPage: SitePage? { page(titleContains: "Contact") }

    /// Pages that are not already reachable from a dedicated screen.
    var otherPages: [SitePage] {
        let featured = Set([aboutPage?.id, expertisePage?.id, processPage?.id, visionPage?.id, contactPage?.id]
            .compactMap { $0 })
        return content.pages.filter { !featured.contains($0.id) }
    }

    // MARK: Cache

    private func restoreFromCache() {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder.azma.decode(SiteContent.self, from: data)
        else { return }
        content = cached
        hasContent = true
    }

    private func persist(_ content: SiteContent) {
        guard let cacheURL, let data = try? JSONEncoder.azma.encode(content) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
