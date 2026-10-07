import SwiftUI

@main
struct QuietReelsApp: App {
    @StateObject private var auth: InstagramAuth
    @StateObject private var instagram: InstagramStore
    @StateObject private var offline = AuthorizedOfflineStore()

    init() {
        let auth = InstagramAuth()
        _auth = StateObject(wrappedValue: auth)
        _instagram = StateObject(wrappedValue: InstagramStore(auth: auth))
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                OwnReelsView()
                    .tabItem { Label("My Videos", systemImage: "play.rectangle") }
                AuthorizedOfflineView()
                    .tabItem { Label("Offline", systemImage: "arrow.down.circle") }
                ProfessionalProfileView()
                    .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                ProfessionalSettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .environmentObject(auth)
            .environmentObject(instagram)
            .environmentObject(offline)
        }
    }
}
