import SwiftUI

@main
struct AzmaApp: App {
    @State private var session = AppSession()
    @State private var site = SiteStore()
    @State private var candidate = CandidateStore()

    init() {
        // The web site's navy, carried into the bars.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(site)
                .environment(candidate)
                .tint(Theme.navy)
                .task {
                    // The public content and the saved session load together:
                    // neither needs the other.
                    async let restored: Void = session.start()
                    async let loaded: Void = site.load()
                    _ = await (restored, loaded)
                }
        }
    }
}
