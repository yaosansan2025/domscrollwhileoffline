import SwiftUI

struct OwnReelsView: View {
    @EnvironmentObject private var auth: InstagramAuth
    @EnvironmentObject private var instagram: InstagramStore
    @EnvironmentObject private var offline: AuthorizedOfflineStore
    @State private var currentID: String?
    @State private var confirmSave = false
    @State private var saveStatus: String?

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isSignedIn {
                    ContentUnavailableView {
                        Label("Connect Instagram", systemImage: "person.crop.circle.badge.checkmark")
                    } description: {
                        Text("Sign in with a Business or Creator account to watch your own videos. Instagram does not provide a recommendation feed to this app.")
                    } actions: {
                        Button("Sign in") { Task { await auth.signIn() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else if instagram.videos.isEmpty {
                    ContentUnavailableView {
                        Label(instagram.isLoading ? "Loading your media" : "No videos found",
                              systemImage: "play.rectangle")
                    } description: {
                        Text(instagram.errorMessage ?? "This tab shows videos from your professional account. Other post types are visible in Profile.")
                    } actions: {
                        Button("Refresh") { Task { await instagram.refresh() } }
                        if instagram.canLoadMore {
                            Button("Load more media") { Task { await instagram.loadMore() } }
                        }
                    }
                } else {
                    ReelFeedView(reels: instagram.videos.compactMap { media in
                        guard let url = media.mediaURL else { return nil }
                        return PlayableReel(id: media.id, videoURL: url,
                            creator: media.username ?? instagram.profile?.username ?? "My Reel",
                            caption: media.caption ?? "", likes: media.likeCount,
                            comments: media.commentsCount)
                    }) { id in
                        currentID = id
                        Task { await instagram.loadMoreIfNeeded(currentID: id) }
                    }
                }
            }
            .navigationTitle("My Videos")
            .toolbar {
                if auth.isSignedIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Refresh", systemImage: "arrow.clockwise") {
                                Task { await instagram.refresh() }
                            }
                            if instagram.canLoadMore {
                                Button("Load more of my media", systemImage: "arrow.down") {
                                    Task { await instagram.loadMore() }
                                }
                            }
                            Button("Save current video offline", systemImage: "arrow.down.circle") {
                                confirmSave = true
                            }
                            .disabled(currentMedia == nil || offline.isSaving ||
                                      (currentMedia.map { offline.contains($0) } ?? false))
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .confirmationDialog("Save this video offline?", isPresented: $confirmSave) {
                Button("I have the rights to store this video") {
                    if let media = currentMedia {
                        Task {
                            await offline.saveOwnMedia(media)
                            saveStatus = offline.errorMessage ?? "Saved to Offline."
                            offline.errorMessage = nil
                        }
                    }
                }
            } message: {
                Text("Your account may include licensed audio or other rights that do not permit a local copy. Save only content you are authorized to store.")
            }
            .task(id: auth.isSignedIn) {
                if auth.isSignedIn { await instagram.refresh() }
                else { instagram.clear() }
            }
            .alert("My Videos", isPresented: Binding(
                get: { auth.errorMessage != nil || saveStatus != nil },
                set: { if !$0 { auth.errorMessage = nil; saveStatus = nil } }
            )) { Button("OK") { auth.errorMessage = nil; saveStatus = nil } } message: {
                Text(auth.errorMessage ?? saveStatus ?? "")
            }
        }
    }

    private var currentMedia: InstagramMedia? {
        instagram.videos.first { $0.id == (currentID ?? instagram.videos.first?.id) }
    }
}
