import SwiftUI

@main
struct QuietReelsApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var cache = OfflineCacheStore()
    @StateObject private var recommended = RecommendedOfflineStore()
    @StateObject private var instagramWeb = InstagramWebSession()
    @StateObject private var navigation = AppNavigation()

    var body: some Scene {
        WindowGroup {
            TabView(selection: $navigation.selectedTab) {
                SharedReelsView()
                    .tabItem { Label("Shared Reels", systemImage: "play.rectangle") }
                    .tag(AppTab.shared)

                RecommendedOfflineView()
                    .tabItem { Label("Recommended", systemImage: "arrow.down.to.line") }
                    .tag(AppTab.recommended)

                OfflineVideosView()
                    .tabItem { Label("Offline Videos", systemImage: "tray.full") }
                    .tag(AppTab.offline)

                ProfileView()
                    .tabItem { Label("My Profile", systemImage: "person.crop.circle") }
                    .tag(AppTab.profile)

                CacheModeSettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(AppTab.settings)
            }
            .environmentObject(library)
            .environmentObject(cache)
            .environmentObject(recommended)
            .environmentObject(instagramWeb)
            .environmentObject(navigation)
        }
    }
}

enum AppTab: Hashable {
    case recommended
    case shared
    case offline
    case profile
    case settings
}

@MainActor
final class AppNavigation: ObservableObject {
    @Published var selectedTab: AppTab = UserDefaults.standard.bool(forKey: "recommendedCacheMode")
        ? .recommended : .shared
}
