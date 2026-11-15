import Foundation

/// Where the app talks to the AZMA CMS.
///
/// The URL is baked in per build configuration (`AZMA_API_BASE_URL` in
/// project.yml → `AZMAAPIBaseURL` in Info.plist). A value in `UserDefaults`
/// wins, so a build can be pointed at a staging server without rebuilding.
enum AppConfig {
    static let baseURLDefaultsKey = "azma.apiBaseURL"

    /// Falls back to the production service if the bundle has no value, so a
    /// misconfigured build still reaches a real server rather than crashing.
    static let fallbackBaseURL = URL(string: "https://azma-cms-555559211982.asia-northeast1.run.app")!

    static var baseURL: URL {
        if let raw = UserDefaults.standard.string(forKey: baseURLDefaultsKey),
           let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.scheme != nil {
            return url
        }
        if let raw = Bundle.main.object(forInfoDictionaryKey: "AZMAAPIBaseURL") as? String,
           let url = URL(string: raw), url.scheme != nil {
            return url
        }
        return fallbackBaseURL
    }

    /// Images in CMS content are site-relative ("/wp-content/…", "/media/…").
    static func assetURL(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return URL(string: path) }
        return URL(string: path, relativeTo: baseURL)
    }

    static let contactEmail = "company@azma-associates.com"

    /// The language to ask the CMS for: the one the app's own text is shown
    /// in, so the firm's pages match the buttons around them. The server
    /// falls back to English for anything not translated.
    static var contentLanguage: String {
        Bundle.main.preferredLocalizations.first == "ja" ? "ja" : "en"
    }
}
