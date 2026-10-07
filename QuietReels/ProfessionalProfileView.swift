import SwiftUI

struct ProfessionalProfileView: View {
    @EnvironmentObject private var auth: InstagramAuth
    @EnvironmentObject private var instagram: InstagramStore

    var body: some View {
        NavigationStack {
            List {
                if let profile = instagram.profile {
                    Section {
                        HStack(alignment: .top, spacing: 16) {
                            AsyncImage(url: profile.profilePictureURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: { Image(systemName: "person.crop.circle.fill") }
                                .frame(width: 76, height: 76).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 5) {
                                Text("@\(profile.username)").font(.headline)
                                if let name = profile.name { Text(name) }
                                if let count = profile.mediaCount {
                                    Text("\(count) posts").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let bio = profile.biography, !bio.isEmpty { Text(bio) }
                    }
                    Section("My posts") {
                        ForEach(instagram.media) { post in
                            NavigationLink {
                                mediaDetail(post)
                            } label: {
                                HStack(spacing: 12) {
                                    AsyncImage(url: post.thumbnailURL ?? post.mediaURL) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: { Image(systemName: "photo") }
                                        .frame(width: 52, height: 52).clipped()
                                    VStack(alignment: .leading) {
                                        Text(post.caption ?? "Untitled post").lineLimit(2)
                                        Text(post.permalink?.path.contains("/reel/") == true
                                             ? "Reel" : (post.mediaType ?? "Media"))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        if instagram.canLoadMore {
                            Button("Load more posts") { Task { await instagram.loadMore() } }
                        }
                    }
                } else {
                    ContentUnavailableView("No professional profile", systemImage: "person.crop.circle",
                        description: Text(auth.isSignedIn
                            ? (instagram.errorMessage ?? "Refresh to load your profile.")
                            : "Sign in with a Business or Creator account in Settings."))
                    Button("Refresh") { Task { await instagram.refresh() } }
                        .disabled(!auth.isSignedIn || instagram.isLoading)
                }
            }
            .navigationTitle("Profile")
            .refreshable { await instagram.refresh() }
        }
    }

    @ViewBuilder
    private func mediaDetail(_ post: InstagramMedia) -> some View {
        if post.isVideo, let url = post.mediaURL {
            ReelFeedView(reels: [PlayableReel(id: post.id, videoURL: url,
                creator: post.username ?? instagram.profile?.username ?? "My video",
                caption: post.caption ?? "", likes: post.likeCount,
                comments: post.commentsCount)])
        } else if let url = post.mediaURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: { ProgressView() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
        } else {
            ContentUnavailableView("Media unavailable", systemImage: "photo")
        }
    }
}
