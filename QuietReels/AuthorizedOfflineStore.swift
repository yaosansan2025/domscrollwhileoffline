import AVFoundation
import Foundation
import SwiftUI

struct OfflineReel: Codable, Identifiable {
    let id: String
    let creator: String
    let caption: String
    let fileName: String
    let savedAt: Date
    let byteCount: Int64
}

enum OfflineStoreError: LocalizedError {
    case unsupportedVideo
    case emptyFile
    case duplicate
    case http(Int)
    case busy

    var errorDescription: String? {
        switch self {
        case .unsupportedVideo: return "This source is not a playable video file that can be saved offline."
        case .emptyFile: return "The video file was empty."
        case .duplicate: return "This video is already saved offline."
        case .http(let status): return "The video server returned HTTP \(status). The media URL may have expired."
        case .busy: return "Wait for the current save operation to finish."
        }
    }
}

@MainActor
final class AuthorizedOfflineStore: ObservableObject {
    @Published private(set) var reels: [OfflineReel] = []
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("offline-index.json") }

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory,
            in: .userDomainMask)[0].appendingPathComponent("QuietReels/AuthorizedOffline", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let files = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix(".deleting-") {
                try? FileManager.default.removeItem(at: file)
            }
        }
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([OfflineReel].self, from: data) {
            reels = saved.filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
        }
    }

    var totalBytes: Int64 { reels.reduce(0) { $0 + $1.byteCount } }
    func fileURL(for reel: OfflineReel) -> URL { directory.appendingPathComponent(reel.fileName) }
    func contains(_ media: InstagramMedia) -> Bool { reels.contains { $0.id == media.id } }

    func importFile(_ source: URL) async {
        await save(id: UUID().uuidString, creator: "Imported video",
                   caption: source.deletingPathExtension().lastPathComponent, source: source)
    }

    func saveOwnMedia(_ media: InstagramMedia) async {
        guard let url = media.mediaURL else {
            errorMessage = OfflineStoreError.unsupportedVideo.localizedDescription
            return
        }
        await save(id: media.id, creator: media.username ?? "My Instagram media",
                   caption: media.caption ?? "", source: url)
    }

    func delete(_ reel: OfflineReel) throws {
        guard !isSaving else { throw OfflineStoreError.busy }
        let updated = reels.filter { $0.id != reel.id }
        let original = fileURL(for: reel)
        let staged = directory.appendingPathComponent(".deleting-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: original, to: staged)
        do { try writeIndex(updated) }
        catch {
            try? FileManager.default.moveItem(at: staged, to: original)
            throw error
        }
        reels = updated
        try FileManager.default.removeItem(at: staged)
    }

    func clearAll() throws {
        guard !isSaving else { throw OfflineStoreError.busy }
        for reel in reels { try delete(reel) }
    }

    private func save(id: String, creator: String, caption: String, source: URL) async {
        guard !isSaving else { errorMessage = OfflineStoreError.busy.localizedDescription; return }
        guard !reels.contains(where: { $0.id == id }) else {
            errorMessage = OfflineStoreError.duplicate.localizedDescription; return
        }
        isSaving = true
        errorMessage = nil
        let ext = ["mp4", "mov", "m4v"].contains(source.pathExtension.lowercased())
            ? source.pathExtension.lowercased() : "mp4"
        let name = UUID().uuidString + ".\(ext)"
        let destination = directory.appendingPathComponent(name)
        do {
            if source.isFileURL {
                let allowed = ["mp4", "mov", "m4v"]
                guard allowed.contains(source.pathExtension.lowercased()) else {
                    throw OfflineStoreError.unsupportedVideo
                }
                let scoped = source.startAccessingSecurityScopedResource()
                defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                try FileManager.default.copyItem(at: source, to: destination)
            } else {
                guard source.scheme == "https" else { throw OfflineStoreError.unsupportedVideo }
                let (temporary, response) = try await URLSession.shared.download(from: source)
                guard let http = response as? HTTPURLResponse else { throw OfflineStoreError.unsupportedVideo }
                guard (200...299).contains(http.statusCode) else { throw OfflineStoreError.http(http.statusCode) }
                guard ["video/mp4", "video/quicktime", "application/octet-stream"]
                    .contains(http.mimeType?.lowercased() ?? "") else { throw OfflineStoreError.unsupportedVideo }
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
            let bytes = Int64((try destination.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
            guard bytes > 0 else { throw OfflineStoreError.emptyFile }
            guard try await AVURLAsset(url: destination).load(.isPlayable) else {
                throw OfflineStoreError.unsupportedVideo
            }
            let record = OfflineReel(id: id, creator: creator, caption: caption,
                                     fileName: name, savedAt: Date(), byteCount: bytes)
            let updated = [record] + reels
            try writeIndex(updated)
            reels = updated
        } catch {
            try? FileManager.default.removeItem(at: destination)
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func writeIndex(_ records: [OfflineReel]) throws {
        let data = try JSONEncoder().encode(records)
        try data.write(to: indexURL, options: .atomic)
    }
}
