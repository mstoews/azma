import SwiftUI

/// The tab shell. Which tabs appear depends on who is signed in: a candidate
/// manages their profile, a client their postings, a consultant their desk.
struct RootView: View {
    @Environment(AppSession.self) private var session
    @Environment(CandidateStore.self) private var candidate
    @State private var selection: Tab = .home

    enum Tab: Hashable { case home, positions, role, contact, account }

    var body: some View {
        switch session.phase {
        case .starting:
            LaunchView()
        case .signedOut, .signedIn:
            TabView(selection: $selection) {
                HomeView()
                    .tabItem { Label("Firm", systemImage: "building.columns") }
                    .tag(Tab.home)

                JobBoardView()
                    .tabItem { Label("Positions", systemImage: "briefcase") }
                    .tag(Tab.positions)

                roleTab
                    .tabItem { Label(roleTabTitle, systemImage: roleTabIcon) }
                    .tag(Tab.role)

                ContactView()
                    .tabItem { Label("Contact", systemImage: "bubble.left.and.text.bubble.right") }
                    .tag(Tab.contact)

                AccountView()
                    .tabItem { Label("Account", systemImage: "person.crop.circle") }
                    .tag(Tab.account)
            }
            // The candidate's own data follows whoever is signed in: loaded
            // for a candidate, cleared for anyone else.
            .task(id: session.account?.id) {
                if session.isCandidate {
                    await candidate.load(force: true)
                } else {
                    candidate.reset()
                }
            }
        }
    }

    @ViewBuilder
    private var roleTab: some View {
        switch session.role {
        case .candidate: CandidateHomeView()
        case .employer: EmployerHomeView()
        case .admin: ConsultantDeskView()
        case nil: JoinView()
        }
    }

    private var roleTabTitle: String {
        switch session.role {
        case .candidate: return "My career"
        case .employer: return "Hiring"
        case .admin: return "Desk"
        case nil: return "Join"
        }
    }

    private var roleTabIcon: String {
        switch session.role {
        case .candidate: return "person.text.rectangle"
        case .employer: return "person.badge.plus"
        case .admin: return "tray.full"
        case nil: return "sparkles"
        }
    }
}

/// Shown for the moment it takes to restore a saved session.
struct LaunchView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.navyDeep, Theme.navy], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Text("A")
                    .font(Theme.display(72, weight: .bold))
                    .foregroundStyle(.white)
                Rectangle().fill(Theme.gold).frame(width: 64, height: 2)
                Text("AZMA & Associates")
                    .font(.footnote.weight(.medium))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}
