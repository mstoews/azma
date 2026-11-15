import SwiftUI

/// The firm: who AZMA are, what they cover, how a search runs, and the
/// consultants who run them — the same content the web site leads with.
struct HomeView: View {
    @Environment(SiteStore.self) private var site
    @Environment(AppSession.self) private var session

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    if site.loadFailed {
                        Notice(.warning, "The firm's pages could not be loaded. Pull to refresh once you are back online.")
                            .padding(.horizontal, Theme.gutter)
                    }
                    paths
                    aboutLinks
                    consultants
                    offices
                }
                .padding(.bottom, 32)
            }
            .brandBackground()
            .scrollIndicators(.hidden)
            .refreshable { await site.load(force: true) }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(site.content.settings.siteName)
                        .font(Theme.display(17, weight: .medium))
                        .foregroundStyle(Theme.ink)
                }
            }
            .navigationDestination(for: SitePage.self) { PageDetailView(page: $0) }
            .navigationDestination(for: ConsultantProfile.self) { ConsultantDetailView(profile: $0) }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeroHeader(
                imagePath: site.content.settings.homeHeaderImage,
                title: site.content.settings.siteName,
                subtitle: site.content.settings.tagline,
                height: 260
            )
            if !site.content.settings.homeDescription.isEmpty {
                Text(site.content.settings.homeDescription)
                    .font(Theme.display(19))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(5)
                    .padding(Theme.gutter)
            }
        }
    }

    /// The two things someone opens this app to do.
    private var paths: some View {
        VStack(spacing: 12) {
            NavigationLink(value: HomeDestination.candidate) {
                PathCard(
                    icon: "doc.text.magnifyingglass",
                    title: "Looking for your next role",
                    message: "Leave your resume with us and apply to the searches we are retained on."
                )
            }
            NavigationLink(value: HomeDestination.employer) {
                PathCard(
                    icon: "person.2.badge.plus",
                    title: "Hiring",
                    message: "Tell us about the position and a consultant will take it from there."
                )
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.gutter)
        .navigationDestination(for: HomeDestination.self) { destination in
            switch destination {
            case .candidate:
                if session.isCandidate { CandidateHomeView() } else { JoinView(preferred: .candidate) }
            case .employer:
                if session.isEmployer { EmployerHomeView() } else { JoinView(preferred: .employer) }
            }
        }
    }

    private var aboutLinks: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "The firm")
            VStack(spacing: 0) {
                ForEach(featuredPages, id: \.id) { page in
                    NavigationLink(value: page) {
                        HStack {
                            Text(page.title)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.secondaryInk)
                        }
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    if page.id != featuredPages.last?.id {
                        Divider().overlay(Theme.hairline)
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
        }
        .padding(.horizontal, Theme.gutter)
    }

    private var featuredPages: [SitePage] {
        [site.aboutPage, site.expertisePage, site.processPage, site.visionPage].compactMap { $0 } + site.otherPages
    }

    @ViewBuilder
    private var consultants: some View {
        if !site.content.profiles.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Our consultants", subtitle: "Tokyo and Singapore")
                    .padding(.horizontal, Theme.gutter)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(site.content.profiles) { profile in
                            NavigationLink(value: profile) {
                                ConsultantCard(profile: profile)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            }
        }
    }

    private var offices: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Offices")
            HStack(alignment: .top, spacing: 12) {
                OfficeCard(city: "Tokyo", lines: ["Morita Building 2F", "3-37-3 Honmachi, Shibuya", "Tokyo 151-0071, Japan"], licence: "13-ユ-312477")
                OfficeCard(city: "Singapore", lines: ["18 Robinson Road", "#20-02, 18 Robinson", "Singapore 048547"], licence: "21S0717")
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

enum HomeDestination: Hashable { case candidate, employer }

private struct PathCard: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.navy)
                .frame(width: 34, height: 34)
                .background(Theme.navy.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.ink)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryInk)
                .padding(.top, 6)
        }
        .brandCard()
    }
}

struct ConsultantCard: View {
    let profile: ConsultantProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RemoteImage(path: profile.thumb)
                .frame(width: 168, height: 190)
                .clipped()
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.title)
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if !profile.role.isEmpty {
                    Text(profile.role)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(1)
                }
                if !profile.office.isEmpty {
                    Text(profile.office)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.gold)
                }
            }
            .padding(12)
            .frame(width: 168, alignment: .leading)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }
}

private struct OfficeCard: View {
    let city: LocalizedStringKey
    let lines: [String]
    let licence: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(city)
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.ink)
            // Postal addresses stay as written.
            ForEach(lines, id: \.self) { line in
                Text(verbatim: line)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
            }
            Text("Licence \(licence)")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryInk.opacity(0.8))
                .padding(.top, 2)
        }
        .brandCard(padding: 14)
    }
}
