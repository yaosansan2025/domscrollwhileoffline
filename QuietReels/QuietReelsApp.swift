import SwiftUI

@main
struct QuietReelsApp: App {
    @StateObject private var offline = AuthorizedOfflineStore()

    var body: some Scene {
        WindowGroup {
            AuthorizedOfflineView()
                .environmentObject(offline)
        }
    }
}
