import AVFoundation
import Foundation
import SwiftUI

struct RecommendedVideo: Codable, Identifiable {
    let reelID: String
    let reelURL: String
    let cachedAt: Date
    let fileName: String
    let thumbnailFileName: String?
    let byteCount: Int64

    var id: String { reelID }
}

enum BatchPhase: Equatable {
    case idle
    case discovering
    case downloading
    case paused
    case complete
    case failed(String)

    var isActive: Bool {
        self == .discovering || self == .downloading
    }
}

@MainActor
final class RecommendedOfflineStore: ObservableObject {
    @Published private(set) var videos: [RecommendedVideo] = []
    @Published private(set) var phase: BatchPhase = .idle
    @Published private(set) var target = 0
    @Published private(set) var completed = 0
    @Published private(set) var failedCount = 0
    @Published private(set) var alreadyCachedCount = 0
    @Published private(set) var lastFailure: String? = nil

    private enum StopIntent: Equatable { case none, pause, cancel }
    private let directory: URL
    private var task: Task<Void, Never>?
    private var pending: [WebReelCandidate] = []
    private var cookies: [HTTPCookie] = []
    private var webSession: InstagramWebSession?
    private var stopIntent: StopIntent = .none
    private var isRefresh = false
    private var beforeRefresh: Set<String> = []

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask)[0]
            .appendingPathComponent("QuietReels/RecommendedVideos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let files = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                     includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix(".partial-") {
                try? FileManager.default.removeItem(at: file)
            }
        }
        let index = directory.appendingPathComponent("recommended.json")
        let indexExists = FileManager.default.fileExists(atPath: index.path)
        var indexReadable = !indexExists
        if let data = try? Data(contentsOf: index),
           let records = try? JSONDecoder().decode([RecommendedVideo].self, from: data) {
            indexReadable = true
            videos = records.filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
        }
        if indexReadable,
           let files = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                     includingPropertiesForKeys: nil) {
            let retained = Set(videos.flatMap { [$0.fileName, $0.thumbnailFileName].compactMap { $0 } })
            for file in files {
                let name = file.lastPathComponent
                let generated = UUID(uuidString: String(name.prefix(36))) != nil &&
                    ["mp4", "jpg"].contains(file.pathExtension.lowercased())
                if generated && !retained.contains(name) {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    var totalBytes: Int64 { videos.reduce(0) { $0 + $1.byteCount } }

    func fileURL(for video: RecommendedVideo) -> URL {
        directory.appendingPathComponent(video.fileName)
    }

    func thumbnailURL(for video: RecommendedVideo) -> URL? {
        video.thumbnailFileName.map { directory.appendingPathComponent($0) }
    }

    func start(count: Int, refresh: Bool, session: InstagramWebSession) {
        guard !phase.isActive else { return }
        target = count
        completed = 0
        failedCount = 0
        alreadyCachedCount = 0
        lastFailure = nil
        pending = []
        cookies = []
        webSession = session
        stopIntent = .none
        isRefresh = refresh
        beforeRefresh = refresh ? Set(videos.map(\.reelID)) : []
        phase = .discovering
        task = Task { await discoverAndDownload() }
    }

    func pause() {
        guard phase.isActive else { return }
        stopIntent = .pause
        task?.cancel()
    }

    func resume() {
        guard phase == .paused, let webSession else { return }
        stopIntent = .none
        if pending.isEmpty {
            phase = .discovering
            task = Task { await discoverAndDownload() }
        } else {
            phase = .downloading
            task = Task { await downloadPending() }
        }
        self.webSession = webSession
    }

    func cancel() {
        guard phase.isActive || phase == .paused else { return }
        stopIntent = .cancel
        pending = []
        task?.cancel()
        if phase == .paused {
            phase = .idle
            task = nil
        }
    }

    func clearAll() throws {
        guard !phase.isActive, phase != .paused else { throw CacheError.inProgress }
        try save([])
        var firstError: Error?
        for video in videos {
            do { try FileManager.default.removeItem(at: fileURL(for: video)) }
            catch { if firstError == nil { firstError = error } }
            if let thumb = thumbnailURL(for: video) {
                do { try FileManager.default.removeItem(at: thumb) }
                catch { if firstError == nil { firstError = error } }
            }
        }
        videos = []
        if let firstError { throw firstError }
    }

    private func discoverAndDownload() async {
        guard let webSession else { return }
        do {
            let candidates = try await webSession.discover(limit: min(target * 3, 150))
            try Task.checkCancellation()
            cookies = await webSession.sessionCookies()
            alreadyCachedCount = candidates.filter { candidate in
                videos.contains { $0.reelID == candidate.reelID }
            }.count
            pending = candidates.filter { candidate in
                !videos.contains { $0.reelID == candidate.reelID }
            }
            guard !pending.isEmpty else {
                phase = alreadyCachedCount > 0 ? .complete :
                    .failed("No new downloadable recommendations were found in the current web page.")
                task = nil
                return
            }
            phase = .downloading
            await downloadPending()
        } catch {
            if Task.isCancelled {
                settleStop()
            } else {
                phase = .failed(error.localizedDescription)
                task = nil
            }
        }
    }

    private func downloadPending() async {
        while completed < target, !pending.isEmpty {
            if Task.isCancelled { settleStop(); return }
            let candidate = pending.removeFirst()
            do {
                try await download(candidate)
                completed += 1
            } catch {
                if Task.isCancelled {
                    pending.insert(candidate, at: 0)
                    settleStop()
                    return
                }
                failedCount += 1
                if lastFailure == nil { lastFailure = error.localizedDescription }
            }
        }
        if isRefresh && completed > 0 { removeSomeOldVideos() }
        if completed == 0 {
            phase = .failed("No recommended videos could be saved. The web page may use expiring, protected, or authenticated streams.")
        } else if completed < target {
            phase = .failed("Only \(completed) of \(target) requested videos were saved; the web page did not expose enough downloadable Reels.")
        } else {
            phase = .complete
        }
        task = nil
    }

    private func settleStop() {
        phase = stopIntent == .pause ? .paused : .idle
        task = nil
    }

    private func download(_ candidate: WebReelCandidate) async throws {
        let token = UUID().uuidString
        let staged = directory.appendingPathComponent(".partial-\(token).mp4")
        let videoName = "\(token).mp4"
        let final = directory.appendingPathComponent(videoName)
        let thumbnailName = "\(token).jpg"
        let thumbnail = directory.appendingPathComponent(thumbnailName)
        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            for cookie in cookies { configuration.httpCookieStorage?.setCookie(cookie) }
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            var request = URLRequest(url: candidate.mediaURL)
            request.setValue("https://www.instagram.com/", forHTTPHeaderField: "Referer")
            let (temporary, response) = try await session.download(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else {
                throw CacheError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                throw CacheError.httpStatus(http.statusCode)
            }
            let mime = http.mimeType?.lowercased()
            guard ["video/mp4", "video/quicktime", "application/octet-stream",
                   "binary/octet-stream"].contains(mime ?? "") else {
                throw CacheError.invalidResponse
            }
            try FileManager.default.moveItem(at: temporary, to: staged)
            let size = Int64((try staged.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
            guard size > 0 else { throw CacheError.emptyFile }
            let asset = AVURLAsset(url: staged)
            guard try await asset.load(.isPlayable) else { throw CacheError.invalidMedia }
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: staged, to: final)
            let hasThumbnail = await Task.detached(priority: .utility) {
                (try? OfflineCacheStore.createThumbnail(video: final, output: thumbnail)) != nil
            }.value
            try Task.checkCancellation()
            let thumbnailBytes = hasThumbnail
                ? Int64((try? thumbnail.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) : 0
            let record = RecommendedVideo(reelID: candidate.reelID, reelURL: candidate.reelURL,
                                          cachedAt: Date(), fileName: videoName,
                                          thumbnailFileName: hasThumbnail ? thumbnailName : nil,
                                          byteCount: size + thumbnailBytes)
            let updated = [record] + videos
            try save(updated)
            videos = updated
        } catch {
            try? FileManager.default.removeItem(at: staged)
            try? FileManager.default.removeItem(at: final)
            try? FileManager.default.removeItem(at: thumbnail)
            throw error
        }
    }

    private func removeSomeOldVideos() {
        let old = videos.filter { beforeRefresh.contains($0.reelID) }
            .sorted { $0.cachedAt < $1.cachedAt }
        let removalCount = min(completed, max(1, old.count / 2))
        for video in old.prefix(removalCount) {
            let updated = videos.filter { $0.reelID != video.reelID }
            guard (try? save(updated)) != nil else { break }
            videos = updated
            try? FileManager.default.removeItem(at: fileURL(for: video))
            if let thumb = thumbnailURL(for: video) {
                try? FileManager.default.removeItem(at: thumb)
            }
        }
    }

    private func save(_ records: [RecommendedVideo]) throws {
        let data = try JSONEncoder().encode(records)
        try data.write(to: directory.appendingPathComponent("recommended.json"), options: .atomic)
    }
}
