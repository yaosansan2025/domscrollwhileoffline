import SwiftUI

struct CacheModeSettingsView: View {
    @AppStorage("recommendedCacheMode") private var recommendedCacheMode = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Cache source") {
                    Toggle("Recommended Reels Auto Cache", isOn: $recommendedCacheMode)
                    Text(recommendedCacheMode
                         ? "ON · Cache a batch from the Instagram Web recommendations prototype."
                         : "OFF · Cache a Reel you opened from Shared Reels.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("This switch only changes where new caching starts. Saved Shared and Recommended videos stay on your iPhone and remain playable in Offline Videos.")
                        .font(.subheadline)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
