import SwiftUI

@main
struct QuietReelsApp: App {
    @StateObject private var offline = AuthorizedOfflineStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                AuthorizedOfflineView()
                    .tabItem { Label("Feed", systemImage: "play.rectangle") }
                AccountSourcesView()
                    .tabItem { Label("Accounts", systemImage: "person.2") }
            }
            .environmentObject(offline)
        }
    }
}
