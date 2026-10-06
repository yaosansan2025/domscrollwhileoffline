import AVKit
import Combine
import SwiftUI

struct LocalVideoView: View {
    @AppStorage("recommendedCacheMode") private var recommendedCacheMode = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cache: OfflineCacheStore
    @EnvironmentObject private var navigation: AppNavigation
    let videoURL: URL
    let title: String
    let subtitle: String
    let backTitle: String
    let cacheClip: SharedClip?
    let cacheSourceURL: URL?
    let showsBackToShared: Bool

    @State private var player: AVPlayer?
    @State private var finished = false

    init(videoURL: URL, title: String, subtitle: String, backTitle: String,
         cacheClip: SharedClip? = nil, cacheSourceURL: URL? = nil,
         showsBackToShared: Bool = false) {
        self.videoURL = videoURL
        self.title = title
        self.subtitle = subtitle
        self.backTitle = backTitle
        self.cacheClip = cacheClip
        self.cacheSourceURL = cacheSourceURL
        self.showsBackToShared = showsBackToShared
    }

    var body: some View {
        VStack(spacing: 20) {
            if let player {
                NativePlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(spacing: 6) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            if let clip = cacheClip {
                cacheControl(for: clip)
            }

            if finished {
                VStack(spacing: 10) {
                    Button("Replay") {
                        finished = false
                        player?.seek(to: .zero)
                        player?.play()
                    }
                    .buttonStyle(.borderedProminent)
                    Button(backTitle) { dismiss() }
                        .buttonStyle(.bordered)
                    if showsBackToShared {
                        Button("Back to Shared Reels") {
                            dismiss()
                            navigation.selectedTab = .shared
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                Button(backTitle) { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.bottom)
        .background(.black)
        .foregroundStyle(.white)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard player == nil else { return }
            finished = false
            let current = AVPlayer(url: videoURL)
            current.actionAtItemEnd = .pause
            player = current
            current.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let currentItem = player?.currentItem,
                  let endedItem = notification.object as? AVPlayerItem,
                  endedItem === currentItem else { return }
            finished = true
        }
    }

    @ViewBuilder
    private func cacheControl(for clip: SharedClip) -> some View {
        if cache.cachedVideo(for: clip) != nil {
            Label("Cached offline", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
        } else if let state = cache.transfers[clip.reelID] {
            switch state {
            case .copying(let fraction):
                if let fraction {
                    Text("Caching \(Int(fraction * 100))%")
                } else {
                    Text("Caching local video…")
                }
            case .downloading(let fraction):
                if let fraction {
                    Text("Downloading \(Int(fraction * 100))%")
                } else {
                    Text("Downloading…")
                }
            case .failed(let message):
                VStack {
                    Text(message).font(.caption).multilineTextAlignment(.center)
                    if !recommendedCacheMode {
                        Button("Retry Cache") { startCache(clip) }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Text("Switch to Shared Reels Cache in Settings to retry.")
                            .font(.caption).multilineTextAlignment(.center)
                    }
                }
            }
        } else if !recommendedCacheMode {
            Button("Cache Offline") { startCache(clip) }
                .buttonStyle(.borderedProminent)
        } else {
            Text("Shared caching is off. Change the cache mode in Settings to save this Reel.")
                .font(.caption).multilineTextAlignment(.center)
        }
    }

    private func startCache(_ clip: SharedClip) {
        guard !recommendedCacheMode else { return }
        let source = cacheSourceURL ?? videoURL
        Task { await cache.cache(clip, from: source) }
    }
}

struct NativePlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.entersFullScreenWhenPlaybackBegins = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
    }
}
