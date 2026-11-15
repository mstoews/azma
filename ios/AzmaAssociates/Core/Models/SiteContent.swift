import Foundation

/// The published web site, as `GET /api/v1/site` returns it: one response for
/// settings, pages, consultant profiles and the menu.
struct SiteContent: Codable, Sendable, Equatable {
    var settings: SiteSettings
    var pages: [SitePage]
    var profiles: [ConsultantProfile]
    var nav: [NavItem]

    static let empty = SiteContent(settings: .placeholder, pages: [], profiles: [], nav: [])
}

struct SiteSettings: Codable, Sendable, Equatable {
    var siteName: String
    var tagline: String
    var homeDescription: String
    var homeHeaderImage: String
    var logo: String

    static let placeholder = SiteSettings(
        siteName: "AZMA & Associates",
        tagline: "We are an APAC professional recruitment firm.",
        homeDescription: "",
        homeHeaderImage: "",
        logo: ""
    )
}

struct SitePage: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: Int64
    let slug: String
    let title: String
    let hero: String
    let content: String
}

struct ConsultantProfile: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: Int64
    let slug: String
    let title: String
    /// Japanese name, role, office — the lines the web site's cards show.
    let excerpt: [String]
    let thumb: String
    let hero: String
    let content: String

    var role: String { excerpt.count > 1 ? excerpt[1] : "" }
    var office: String { excerpt.count > 2 ? excerpt[2] : "" }
    var localName: String { excerpt.first ?? "" }
}

struct NavItem: Codable, Sendable, Equatable, Hashable {
    let label: String
    var link: String?
    var href: String?
}
