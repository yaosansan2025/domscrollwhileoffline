import AVFoundation
import Foundation
import SwiftUI
import UIKit

struct CachedVideo: Codable, Identifiable {
    let reelID: String
    let reelURL: String
    let sender: String
    let conversation: String
    let cachedAt: Date
    let fileName: String
    let thumbnailFileName: String?
    let byteCount: Int64

    var id: String { reelID }
}

enum CacheTransferState: Equatable {
    case copying(Double?)
    case downloading(Double?)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .copying, .downloading: return true
        case .failed: return false
        }
    }
}

enum CacheError: LocalizedError {
    case invalidMedia
    case emptyFile
    case invalidResponse
    case httpStatus(Int)
    case inProgress

    var errorDescription: String? {
        switch self {
        case .invalidMedia: return "The source is not a playable, downloadable video file."
        case .emptyFile: return "The downloaded video was empty."
        case .invalidResponse: return "The server did not return a video file."
        case .httpStatus(let code): return "The video server returned HTTP \(code)."
        case .inProgress: return "Wait for the current cache operation to finish."
        }
    }
}

@MainActor
final class OfflineCacheStore: ObservableObject {
    @Published private(set) var videos: [CachedVideo] = []
    @Published private(set) var transfers: [String: CacheTransferState] = [:]

    private let directory: URL

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask)[0]
            .appendingPathComponent("QuietReels/OfflineVideos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let files = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                     includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix(".partial-") {
                try? FileManager.default.removeItem(at: file)
            }
        }
        let index = directory.appendingPathComponent("offline.json")
        let indexExists = FileManager.default.fileExists(atPath: index.path)
        var indexReadable = !indexExists
        if let data = try? Data(contentsOf: index),
           let decoded = try? JSONDecoder().decode([CachedVideo].self, from: data) {
            indexReadable = true
            videos = decoded.filter {
                FileManager.default.fileExists(atPath: fileURL(for: $0).path)
            }
        }
        if indexReadable,
           let files = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                     includingPropertiesForKeys: nil) {
            let retained = Set(videos.flatMap { [$0.fileName, $0.thumbnailFileName].compactMap { $0 } })
            for file in files {
                let name = file.lastPathComponent
                let generated = UUID(uuidString: String(name.prefix(36))) != nil &&
                    ["mp4", "mov", "m4v", "jpg"].contains(file.pathExtension.lowercased())
                if generated && !retained.contains(name) {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    var totalBytes: Int64 { videos.reduce(0) { $0 + $1.byteCount } }
    var hasActiveTransfer: Bool { transfers.values.contains { $0.isActive } }

    func cachedVideo(for clip: SharedClip) -> CachedVideo? {
        videos.first { $0.reelID == clip.reelID }
    }

    func fileURL(for video: CachedVideo) -> URL {
        directory.appendingPathComponent(video.fileName)
    }

    func thumbnailURL(for video: CachedVideo) -> URL? {
        video.thumbnailFileName.map { directory.appendingPathComponent($0) }
    }

    func cache(_ clip: SharedClip, from source: URL) async {
        let id = clip.reelID
        guard cachedVideo(for: clip) == nil, transfers[id]?.isActive != true else { return }
        let ext = source.pathExtension.lowercased()
        guard ["mp4", "mov", "m4v"].contains(ext) else {
            transfers[id] = .failed(CacheError.invalidMedia.localizedDescription)
            return
        }
        let token = UUID().uuidString
        let staged = directory.appendingPathComponent(".partial-\(token).\(ext)")
        let fileName = "\(token).\(ext)"
        let final = directory.appendingPathComponent(fileName)
        let thumbnailName = "\(token).jpg"
        let thumbnail = directory.appendingPathComponent(thumbnailName)

        do {
            if source.isFileURL {
                transfers[id] = .copying(0)
                try await Task.detached(priority: .userInitiated) {
                    try Self.copyLocalVideo(from: source, to: staged) { [weak self] fraction in
                        Task { @MainActor in
                            guard self?.transfers[id]?.isActive == true else { return }
                            self?.transfers[id] = .copying(fraction)
                        }
                    }
                }.value
            } else {
                transfers[id] = .downloading(0)
                let downloader = DirectVideoDownloader(destination: staged) { [weak self] fraction in
                    Task { @MainActor in
                        guard self?.transfers[id]?.isActive == true else { return }
                        self?.transfers[id] = .downloading(fraction)
                    }
                }
                try await downloader.download(from: source)
            }

            let videoBytes = Int64((try staged.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
            guard videoBytes > 0 else { throw CacheError.emptyFile }
            let asset = AVURLAsset(url: staged)
            guard try await asset.load(.isPlayable) else { throw CacheError.invalidMedia }
            try FileManager.default.moveItem(at: staged, to: final)

            let madeThumbnail = await Task.detached(priority: .utility) {
                (try? Self.createThumbnail(video: final, output: thumbnail)) != nil
            }.value
            let thumbnailBytes = madeThumbnail
                ? Int64((try? thumbnail.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) : 0
            let record = CachedVideo(reelID: id, reelURL: clip.reelURL,
                                     sender: clip.sender, conversation: clip.conversation,
                                     cachedAt: Date(), fileName: fileName,
                                     thumbnailFileName: madeThumbnail ? thumbnailName : nil,
                                     byteCount: videoBytes + thumbnailBytes)
            let updated = [record] + videos
            try save(updated)
            videos = updated
            transfers.removeValue(forKey: id)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            try? FileManager.default.removeItem(at: final)
            try? FileManager.default.removeItem(at: thumbnail)
            transfers[id] = .failed(error.localizedDescription)
        }
    }

    func delete(_ video: CachedVideo) throws {
        guard !hasActiveTransfer else { throw CacheError.inProgress }
        let updated = videos.filter { $0.reelID != video.reelID }
        let original = fileURL(for: video)
        let trash = directory.appendingPathComponent(".partial-delete-\(UUID().uuidString)")
        let oldThumbnail = thumbnailURL(for: video)
        let trashThumbnail = directory.appendingPathComponent(".partial-delete-\(UUID().uuidString).jpg")
        var movedThumbnail = false
        try FileManager.default.moveItem(at: original, to: trash)
        do {
            if let oldThumbnail, FileManager.default.fileExists(atPath: oldThumbnail.path) {
                try FileManager.default.moveItem(at: oldThumbnail, to: trashThumbnail)
                movedThumbnail = true
            }
            try save(updated)
        } catch {
            try? FileManager.default.moveItem(at: trash, to: original)
            if movedThumbnail, let oldThumbnail {
                try? FileManager.default.moveItem(at: trashThumbnail, to: oldThumbnail)
            }
            throw error
        }
        videos = updated
        try? FileManager.default.removeItem(at: trash)
        if movedThumbnail { try? FileManager.default.removeItem(at: trashThumbnail) }
    }

    func clearAll() throws {
        guard !hasActiveTransfer else { throw CacheError.inProgress }
        for video in videos { try delete(video) }
    }

    private func save(_ records: [CachedVideo]) throws {
        let data = try JSONEncoder().encode(records)
        try data.write(to: directory.appendingPathComponent("offline.json"), options: .atomic)
    }

    nonisolated private static func copyLocalVideo(from source: URL, to destination: URL,
                                                   progress: (Double?) -> Void) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        _ = FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        let total = Int64((try source.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
        var copied: Int64 = 0
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
            copied += Int64(chunk.count)
            progress(total > 0 ? min(1, Double(copied) / Double(total)) : nil)
        }
    }

    nonisolated static func createThumbnail(video: URL, output: URL) throws {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        let image = try generator.copyCGImage(at: .zero, actualTime: nil)
        guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.72) else {
            throw CacheError.invalidMedia
        }
        try data.write(to: output, options: .atomic)
    }
}

private final class DirectVideoDownloader: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let progress: (Double?) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var downloadError: Error?

    init(destination: URL, progress: @escaping (Double?) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func download(from url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .ephemeral, delegate: self,
                                     delegateQueue: OperationQueue.main)
            self.session = session
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        progress(totalBytesExpectedToWrite > 0
                 ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse else {
            downloadError = CacheError.invalidResponse
            return
        }
        guard (200...299).contains(response.statusCode) else {
            downloadError = CacheError.httpStatus(response.statusCode)
            return
        }
        if let mime = response.mimeType?.lowercased(),
           !["video/mp4", "video/quicktime", "application/octet-stream", "binary/octet-stream"].contains(mime) {
            downloadError = CacheError.invalidResponse
            return
        }
        do {
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            downloadError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        let failure: Error?
        if let error { failure = error }
        else if let downloadError { failure = downloadError }
        else if !FileManager.default.fileExists(atPath: destination.path) {
            failure = CacheError.invalidResponse
        } else { failure = nil }
        if let failure {
            continuation?.resume(throwing: failure)
        } else {
            continuation?.resume()
        }
        continuation = nil
        self.session?.finishTasksAndInvalidate()
        self.session = nil
    }
}
