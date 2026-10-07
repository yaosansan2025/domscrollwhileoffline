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
    case busy

    var errorDescription: String? {
        switch self {
        case .unsupportedVideo: return "Choose a playable MP4, MOV, or M4V video file."
        case .emptyFile: return "The video file was empty."
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
    func importFile(_ source: URL) async {
        await save(id: UUID().uuidString, creator: "Imported video",
                   caption: source.deletingPathExtension().lastPathComponent, source: source)
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
        isSaving = true
        errorMessage = nil
        let ext = source.pathExtension.lowercased()
        let name = UUID().uuidString + ".\(ext)"
        let destination = directory.appendingPathComponent(name)
        do {
            guard source.isFileURL, ["mp4", "mov", "m4v"].contains(ext) else {
                throw OfflineStoreError.unsupportedVideo
            }
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at: source, to: destination)
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
