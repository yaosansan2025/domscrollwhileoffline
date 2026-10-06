import SwiftUI
import UIKit

private enum ClearTarget {
    case shared
    case recommended
    case all

    var buttonTitle: String {
        switch self {
        case .shared: return "Delete Shared"
        case .recommended: return "Delete Recommended"
        case .all: return "Delete All"
        }
    }

    var message: String {
        switch self {
        case .shared: return "Saved Shared video files and thumbnails will be removed from this iPhone."
        case .recommended: return "Saved Recommended video files and thumbnails will be removed from this iPhone."
        case .all: return "Saved Shared and Recommended video files and thumbnails will be removed from this iPhone."
        }
    }
}

struct OfflineVideosView: View {
    @EnvironmentObject private var cache: OfflineCacheStore
    @EnvironmentObject private var recommended: RecommendedOfflineStore
    @State private var clearTarget: ClearTarget?
    @State private var errorMessage = ""
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            Group {
                if cache.videos.isEmpty && recommended.videos.isEmpty {
                    ContentUnavailableView {
                        Label("No offline videos", systemImage: "arrow.down.circle")
                    } description: {
                        Text("Cache a video from Shared Reels or start a recommended batch. Saved videos from either source will appear here.")
                    }
                } else {
                    List {
                        Section {
                            Text("Total: \(ByteCountFormatter.string(fromByteCount: cache.totalBytes + recommended.totalBytes, countStyle: .file))")
                                .font(.subheadline)
                        }

                        if !cache.videos.isEmpty {
                            Section("Shared") {
                                ForEach(cache.videos) { video in
                                    NavigationLink {
                                        LocalVideoView(videoURL: cache.fileURL(for: video),
                                                       title: "Shared by \(video.sender)",
                                                       subtitle: video.conversation,
                                                       backTitle: "Back to Offline Videos",
                                                       showsBackToShared: true)
                                    } label: {
                                        HStack(spacing: 12) {
                                            sharedThumbnail(for: video)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(video.sender).font(.headline)
                                                Text(video.conversation).font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                Text("Shared · \(video.cachedAt.formatted(date: .abbreviated, time: .omitted))")
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Text(ByteCountFormatter.string(fromByteCount: video.byteCount,
                                                                          countStyle: .file))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .swipeActions {
                                        Button("Delete", role: .destructive) {
                                            do { try cache.delete(video) }
                                            catch { show(error) }
                                        }
                                    }
                                }
                            }
                        }

                        if !recommended.videos.isEmpty {
                            Section("Recommended") {
                                ForEach(recommended.videos) { video in
                                    NavigationLink {
                                        RecommendedPlayerView(videos: recommended.videos,
                                                              initialID: video.id,
                                                              backTitle: "Back to Offline Videos")
                                    } label: {
                                        HStack(spacing: 12) {
                                            recommendedThumbnail(for: video)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Reel \(video.reelID)").font(.headline)
                                                    .lineLimit(1)
                                                Text("Recommended · \(video.cachedAt.formatted(date: .abbreviated, time: .omitted))")
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Text(ByteCountFormatter.string(fromByteCount: video.byteCount,
                                                                          countStyle: .file))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Offline Videos")
            .toolbar {
                if !cache.videos.isEmpty || !recommended.videos.isEmpty {
                    Menu {
                        if !cache.videos.isEmpty {
                            Button("Clear Shared", role: .destructive) {
                                clearTarget = .shared
                            }
                            .disabled(cache.hasActiveTransfer)
                        }
                        if !recommended.videos.isEmpty {
                            Button("Clear Recommended", role: .destructive) {
                                clearTarget = .recommended
                            }
                            .disabled(recommended.phase.isActive || recommended.phase == .paused)
                        }
                        Button("Clear All", role: .destructive) { clearTarget = .all }
                            .disabled(cache.hasActiveTransfer || recommended.phase.isActive
                                      || recommended.phase == .paused)
                    } label: {
                        Label("Manage", systemImage: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Delete offline videos?", isPresented: Binding(
                get: { clearTarget != nil },
                set: { if !$0 { clearTarget = nil } }
            )) {
                if let clearTarget {
                    Button(clearTarget.buttonTitle, role: .destructive) {
                        clear(clearTarget)
                    }
                }
            } message: {
                Text(clearTarget?.message ?? "")
            }
            .alert("Cache deletion failed", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    @ViewBuilder
    private func sharedThumbnail(for video: CachedVideo) -> some View {
        if let url = cache.thumbnailURL(for: video),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable().scaledToFill()
                .frame(width: 56, height: 64)
                .clipped().clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: "play.rectangle.fill")
                .frame(width: 56, height: 64)
        }
    }

    @ViewBuilder
    private func recommendedThumbnail(for video: RecommendedVideo) -> some View {
        if let url = recommended.thumbnailURL(for: video),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable().scaledToFill()
                .frame(width: 56, height: 64)
                .clipped().clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: "play.rectangle.fill")
                .frame(width: 56, height: 64)
        }
    }

    private func show(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }

    private func clear(_ target: ClearTarget) {
        do {
            switch target {
            case .shared: try cache.clearAll()
            case .recommended: try recommended.clearAll()
            case .all:
                try cache.clearAll()
                try recommended.clearAll()
            }
        } catch { show(error) }
    }
}
