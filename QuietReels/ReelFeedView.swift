import AVKit
import Combine
import SwiftUI

struct PlayableReel: Identifiable {
    let id: String
    let videoURL: URL
    let creator: String
    let caption: String
    let likes: Int?
    let comments: Int?
}

struct ReelFeedView: View {
    let reels: [PlayableReel]
    var reached: ((String) -> Void)? = nil
    @State private var visibleID: String?

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(reels) { reel in
                        ReelPageView(reel: reel, active: visibleID == reel.id,
                                     preload: nextID(after: visibleID) == reel.id)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .id(reel.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visibleID)
            .background(.black)
        }
        .onAppear { if visibleID == nil { visibleID = reels.first?.id } }
        .onChange(of: reels.map(\.id)) { _, ids in
            if let visibleID, !ids.contains(visibleID) { self.visibleID = ids.first }
        }
        .onChange(of: visibleID) { _, value in
            if let value { reached?(value) }
        }
    }

    private func nextID(after id: String?) -> String? {
        guard let id, let index = reels.firstIndex(where: { $0.id == id }),
              index + 1 < reels.count else { return nil }
        return reels[index + 1].id
    }
}

private struct ReelPageView: View {
    @Environment(\.scenePhase) private var scenePhase
    let reel: PlayableReel
    let active: Bool
    let preload: Bool
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(reel.creator).font(.headline)
                if !reel.caption.isEmpty {
                    Text(reel.caption).font(.subheadline).lineLimit(3)
                }
                HStack(spacing: 16) {
                    if let likes = reel.likes { Label("\(likes)", systemImage: "heart") }
                    if let comments = reel.comments { Label("\(comments)", systemImage: "bubble") }
                }
                .font(.caption)
            }
            .foregroundStyle(.white)
            .shadow(radius: 4)
            .padding(20)
            .padding(.bottom, 14)
        }
        .onAppear {
            prepareIfNeeded()
            if active { player?.play() }
        }
        .onDisappear { player?.pause() }
        .onChange(of: active) { _, isActive in
            prepareIfNeeded()
            if isActive { player?.play() } else { player?.pause() }
        }
        .onChange(of: preload) { _, shouldPreload in
            if shouldPreload { prepareIfNeeded() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && active { player?.play() }
            else { player?.pause() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard active, let item = note.object as? AVPlayerItem,
                  item === player?.currentItem else { return }
            player?.seek(to: .zero)
            player?.play()
        }
    }

    private func prepareIfNeeded() {
        guard player == nil else { return }
        let newPlayer = AVPlayer(url: reel.videoURL)
        newPlayer.actionAtItemEnd = .pause
        player = newPlayer
        if active { newPlayer.play() }
    }
}
