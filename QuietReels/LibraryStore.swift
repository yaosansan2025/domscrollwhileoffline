import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SharedClip: Codable, Identifiable {
    let id: UUID
    let sender: String
    let conversation: String
    let reelURL: String
    let fileName: String?
    let videoURL: String?
    let importedAt: Date

    var reelID: String {
        String(reelURL.split(separator: "/").last ?? "")
    }
}

enum PostKind: String, Codable {
    case image
    case video
}

struct ProfilePost: Codable, Identifiable {
    let id: UUID
    let title: String
    let fileName: String
    let kind: PostKind
    let importedAt: Date
}

private struct LibrarySnapshot: Codable {
    var profileName: String
    var sharedClips: [SharedClip]
    var profilePosts: [ProfilePost]
}

enum LibraryError: LocalizedError {
    case missingMessageDetails
    case invalidReelURL
    case unsupportedFile
    case invalidVideoURL

    var errorDescription: String? {
        switch self {
        case .missingMessageDetails:
            return "Enter the friend and chat shown in the shared message."
        case .invalidReelURL:
            return "Paste a full https://www.instagram.com/reel/... link from the message."
        case .unsupportedFile:
            return "Choose an image or playable video file of a supported type."
        case .invalidVideoURL:
            return "Enter a direct HTTPS .mp4, .mov, or .m4v video URL, not an Instagram page link."
        }
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var profileName: String = ""
    @Published private(set) var sharedClips: [SharedClip] = []
    @Published private(set) var profilePosts: [ProfilePost] = []

    private let directory: URL

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask)[0]
            .appendingPathComponent("QuietReels", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let index = directory.appendingPathComponent("library.json")
        if let data = try? Data(contentsOf: index),
           let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data) {
            profileName = snapshot.profileName
            sharedClips = snapshot.sharedClips
            profilePosts = snapshot.profilePosts
        }
    }

    func fileURL(named fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    func importSharedClip(from source: URL, sender: String,
                          conversation: String, reelURL: String) throws {
        let sender = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        let conversation = conversation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sender.isEmpty, !conversation.isEmpty else {
            throw LibraryError.missingMessageDetails
        }
        let canonicalURL = try Self.canonicalReelURL(reelURL)
        guard ["mp4", "mov", "m4v"].contains(source.pathExtension.lowercased()) else {
            throw LibraryError.unsupportedFile
        }
        let fileName = try copyFile(from: source, allowedType: .movie)
        let clip = SharedClip(id: UUID(), sender: sender, conversation: conversation,
                              reelURL: canonicalURL, fileName: fileName,
                              videoURL: nil, importedAt: Date())
        let updated = [clip] + sharedClips
        do {
            try save(LibrarySnapshot(profileName: profileName, sharedClips: updated,
                                     profilePosts: profilePosts))
            sharedClips = updated
        } catch {
            try? FileManager.default.removeItem(at: fileURL(named: fileName))
            throw error
        }
    }

    func addRemoteSharedClip(sender: String, conversation: String,
                             reelURL: String, directVideoURL: String) throws {
        let sender = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        let conversation = conversation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sender.isEmpty, !conversation.isEmpty else {
            throw LibraryError.missingMessageDetails
        }
        let canonicalURL = try Self.canonicalReelURL(reelURL)
        let directURL = try Self.validatedDirectVideoURL(directVideoURL)
        let clip = SharedClip(id: UUID(), sender: sender, conversation: conversation,
                              reelURL: canonicalURL, fileName: nil,
                              videoURL: directURL.absoluteString, importedAt: Date())
        let updated = [clip] + sharedClips
        try save(LibrarySnapshot(profileName: profileName, sharedClips: updated,
                                 profilePosts: profilePosts))
        sharedClips = updated
    }

    func playbackURL(for clip: SharedClip) -> URL? {
        if let fileName = clip.fileName { return fileURL(named: fileName) }
        if let videoURL = clip.videoURL { return URL(string: videoURL) }
        return nil
    }

    func importProfilePost(from source: URL) throws {
        guard let type = UTType(filenameExtension: source.pathExtension.lowercased()) else {
            throw LibraryError.unsupportedFile
        }
        let kind: PostKind
        let allowedType: UTType
        if type.conforms(to: .image) {
            kind = .image
            allowedType = .image
        } else if type.conforms(to: .movie) {
            kind = .video
            allowedType = .movie
        } else {
            throw LibraryError.unsupportedFile
        }
        let fileName = try copyFile(from: source, allowedType: allowedType)
        let post = ProfilePost(id: UUID(), title: source.deletingPathExtension().lastPathComponent,
                               fileName: fileName, kind: kind, importedAt: Date())
        let updated = [post] + profilePosts
        do {
            try save(LibrarySnapshot(profileName: profileName, sharedClips: sharedClips,
                                     profilePosts: updated))
            profilePosts = updated
        } catch {
            try? FileManager.default.removeItem(at: fileURL(named: fileName))
            throw error
        }
    }

    func setProfileName(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try save(LibrarySnapshot(profileName: trimmed, sharedClips: sharedClips,
                                 profilePosts: profilePosts))
        profileName = trimmed
    }

    private func copyFile(from source: URL, allowedType: UTType) throws -> String {
        let ext = source.pathExtension.lowercased()
        guard let type = UTType(filenameExtension: ext), type.conforms(to: allowedType) else {
            throw LibraryError.unsupportedFile
        }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let fileName = UUID().uuidString + "." + ext
        try FileManager.default.copyItem(at: source, to: fileURL(named: fileName))
        return fileName
    }

    private func save(_ snapshot: LibrarySnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: directory.appendingPathComponent("library.json"), options: .atomic)
    }

    static func canonicalReelURL(_ input: String) throws -> String {
        guard let parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https",
              ["instagram.com", "www.instagram.com"].contains(parts.host?.lowercased() ?? ""),
              parts.port == nil, parts.user == nil, parts.password == nil else {
            throw LibraryError.invalidReelURL
        }
        let pieces = parts.path.split(separator: "/")
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard pieces.count == 2, pieces[0] == "reel", !pieces[1].isEmpty,
              pieces[1].unicodeScalars.allSatisfy(allowed.contains) else {
            throw LibraryError.invalidReelURL
        }
        return "https://www.instagram.com/reel/\(pieces[1])/"
    }

    static func validatedDirectVideoURL(_ input: String) throws -> URL {
        guard let parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", parts.host != nil,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              let url = parts.url,
              ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased()) else {
            throw LibraryError.invalidVideoURL
        }
        return url
    }
}
