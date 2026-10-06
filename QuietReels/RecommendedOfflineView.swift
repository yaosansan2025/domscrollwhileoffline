import AVKit
import Combine
import SwiftUI
import UIKit

struct RecommendedOfflineView: View {
    @AppStorage("recommendedCacheMode") private var recommendedCacheMode = false
    @EnvironmentObject private var store: RecommendedOfflineStore
    @EnvironmentObject private var web: InstagramWebSession
    @State private var selectedCount = 10
    @State private var showingLogin = false
    @State private var confirmClear = false
    @State private var errorMessage = ""
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Open Instagram Web Session") { showingLogin = true }
                        .disabled(store.phase.isActive)
                    Text("Sign in here once. This is separate from the Instagram app's login. Only direct video files visible in this web page can be downloaded.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("One-tap batch") {
                    if !recommendedCacheMode {
                        Text("Turn on Recommended Reels Auto Cache in Settings to start a new batch. Saved videos remain available below and in Offline Videos.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Videos", selection: $selectedCount) {
                        Text("10").tag(10)
                        Text("20").tag(20)
                        Text("50").tag(50)
                    }
                    .pickerStyle(.segmented)
                    Button("Download Offline Reels") {
                        guard recommendedCacheMode else { return }
                        store.start(count: selectedCount, refresh: false, session: web)
                    }
                    .disabled(!recommendedCacheMode || store.phase.isActive)
                    Button("Refresh Offline Videos") {
                        guard recommendedCacheMode else { return }
                        store.start(count: selectedCount, refresh: true, session: web)
                    }
                    .disabled(!recommendedCacheMode || store.phase.isActive || store.videos.isEmpty)

                    if store.target > 0 {
                        Text("\(store.completed) / \(store.target) videos downloaded")
                            .font(.subheadline)
                    }
                    if store.failedCount > 0 {
                        Text("\(store.failedCount) unavailable or failed")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if store.alreadyCachedCount > 0 {
                        Text("\(store.alreadyCachedCount) already cached")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let failure = store.lastFailure {
                        Text("First failure: \(failure)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    statusView

                    if store.phase.isActive {
                        HStack {
                            Button("Pause") { store.pause() }
                            Button("Cancel", role: .destructive) { store.cancel() }
                        }
                    } else if store.phase == .paused {
                        HStack {
                            Button("Resume") { store.resume() }
                            Button("Cancel", role: .destructive) { store.cancel() }
                        }
                    }
                }

                Section {
                    if store.videos.isEmpty {
                        Text("No recommended Reels cached yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.videos) { video in
                            NavigationLink {
                                RecommendedPlayerView(videos: store.videos, initialID: video.id)
                            } label: {
                                HStack(spacing: 12) {
                                    thumbnail(for: video)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Reel \(video.reelID)").font(.headline)
                                            .lineLimit(1)
                                        Text(video.cachedAt, style: .date)
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
                } header: {
                    Text("Offline Reels · \(ByteCountFormatter.string(fromByteCount: store.totalBytes, countStyle: .file))")
                }
            }
            .navigationTitle("Offline Reels")
            .background {
                if store.phase.isActive && !showingLogin {
                    InstagramLoginView(session: web, opensLoginPage: false)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                }
            }
            .toolbar {
                if !store.videos.isEmpty {
                    Button("Clear All", role: .destructive) { confirmClear = true }
                        .disabled(store.phase.isActive || store.phase == .paused)
                }
            }
            .sheet(isPresented: $showingLogin) {
                NavigationStack {
                    InstagramLoginView(session: web)
                        .navigationTitle("Instagram Web Session")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            Button("Done") {
                                web.park()
                                showingLogin = false
                            }
                        }
                }
            }
            .confirmationDialog("Delete all recommended offline videos?",
                                isPresented: $confirmClear) {
                Button("Delete All", role: .destructive) {
                    do { try store.clearAll() }
                    catch {
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                }
            }
            .alert("Could not clear cache", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch store.phase {
        case .idle: EmptyView()
        case .discovering: Text("Reading the current Instagram Web page…")
        case .downloading: Text("Downloading and saving video files…")
        case .paused: Text("Paused")
        case .complete: Text("Batch finished")
        case .failed(let message): Text(message).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func thumbnail(for video: RecommendedVideo) -> some View {
        if let url = store.thumbnailURL(for: video),
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
}

struct RecommendedPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: RecommendedOfflineStore
    let videos: [RecommendedVideo]
    let initialID: String
    let backTitle: String
    @State private var index = 0
    @State private var player: AVPlayer?
    @State private var finished = false

    init(videos: [RecommendedVideo], initialID: String,
         backTitle: String = "Back to Offline Reels") {
        self.videos = videos
        self.initialID = initialID
        self.backTitle = backTitle
        _index = State(initialValue: videos.firstIndex { $0.id == initialID } ?? 0)
    }

    var body: some View {
        VStack(spacing: 16) {
            if let player {
                NativePlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text("\(index + 1) / \(videos.count) cached videos")
                .font(.caption)
            HStack {
                Button("Previous Cached") { index -= 1 }
                    .disabled(index == 0)
                Button("Next Cached") { index += 1 }
                    .disabled(index + 1 >= videos.count)
            }
            .buttonStyle(.bordered)
            if finished {
                Button("Replay") {
                    finished = false
                    player?.seek(to: .zero)
                    player?.play()
                }
                .buttonStyle(.borderedProminent)
            }
            Button(backTitle) { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(.bottom)
        .background(.black)
        .foregroundStyle(.white)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            playCurrent()
        }
        .onChange(of: index) { _ in playCurrent() }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let item = player?.currentItem,
                  let ended = note.object as? AVPlayerItem,
                  ended === item else { return }
            finished = true
        }
    }

    private func playCurrent() {
        guard videos.indices.contains(index) else { return }
        player?.pause()
        finished = false
        let current = AVPlayer(url: store.fileURL(for: videos[index]))
        current.actionAtItemEnd = .pause
        player = current
        current.play()
    }
}
