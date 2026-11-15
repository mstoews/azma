import SwiftUI

/// One CMS page — Who We Are, Our Expertise, Search Process, Vision & Mission.
struct PageDetailView: View {
    let page: SitePage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !page.hero.isEmpty {
                    HeroHeader(imagePath: page.hero, title: page.title, height: 200)
                } else {
                    Text(page.title)
                        .font(Theme.hero)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, 8)
                }
                RichText(html: page.content)
                    .padding(.horizontal, Theme.gutter)
            }
            .padding(.bottom, 36)
        }
        .brandBackground()
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A consultant's biography.
struct ConsultantDetailView: View {
    let profile: ConsultantProfile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HeroHeader(
                    imagePath: profile.hero.isEmpty ? profile.thumb : profile.hero,
                    title: profile.title,
                    subtitle: [profile.role, profile.office].filter { !$0.isEmpty }.joined(separator: " · "),
                    height: 280
                )
                RichText(html: profile.content)
                    .padding(.horizontal, Theme.gutter)
            }
            .padding(.bottom, 36)
        }
        .brandBackground()
        .navigationTitle(profile.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
