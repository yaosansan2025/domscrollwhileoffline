import Foundation
import Combine

struct InstagramProfile: Decodable {
    let id: String
    let username: String
    let name: String?
    let biography: String?
    let profilePictureURL: URL?
    let mediaCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, username, name, biography
        case profilePictureURL = "profile_picture_url"
        case mediaCount = "media_count"
    }
}

struct InstagramMedia: Decodable, Identifiable {
    let id: String
    let caption: String?
    let mediaType: String?
    let mediaURL: URL?
    let thumbnailURL: URL?
    let permalink: URL?
    let username: String?
    let likeCount: Int?
    let commentsCount: Int?

    var isVideo: Bool { mediaType == "VIDEO" && mediaURL != nil }

    enum CodingKeys: String, CodingKey {
        case id, caption, permalink, username
        case mediaType = "media_type"
        case mediaURL = "media_url"
        case thumbnailURL = "thumbnail_url"
        case likeCount = "like_count"
        case commentsCount = "comments_count"
    }
}

enum InstagramAPIError: LocalizedError {
    case response(String)
    case invalidPage

    var errorDescription: String? {
        switch self {
        case .response(let message): return message
        case .invalidPage: return "Instagram returned an invalid media page."
        }
    }
}

@MainActor
final class InstagramStore: ObservableObject {
    @Published private(set) var profile: InstagramProfile?
    @Published private(set) var media: [InstagramMedia] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private var nextPage: URL?
    private let auth: InstagramAuth

    init(auth: InstagramAuth) { self.auth = auth }

    var videos: [InstagramMedia] { media.filter(\.isVideo) }
    var canLoadMore: Bool { nextPage != nil }

    func refresh() async {
        guard auth.isSignedIn, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let token = try await auth.validToken()
            let profileURL = Self.graphURL("me", fields:
                "id,username,name,biography,profile_picture_url,media_count")
            let profile: InstagramProfile = try await get(profileURL, token: token)
            self.profile = profile
            let page: MediaPage = try await get(Self.graphURL("me/media", fields:
                "id,caption,media_type,media_url,thumbnail_url,permalink,username,like_count,comments_count", limit: 25), token: token)
            media = page.data
            nextPage = validated(page.paging?.next)
        } catch { errorMessage = error.localizedDescription }
    }

    func loadMoreIfNeeded(currentID: String) async {
        guard let index = videos.firstIndex(where: { $0.id == currentID }),
              index >= max(0, videos.count - 4) else { return }
        for _ in 0..<3 {
            let previousCount = videos.count
            await loadMore()
            if videos.count > previousCount || !canLoadMore || errorMessage != nil { break }
        }
    }

    func loadMore() async {
        guard let nextPage, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let token = try await auth.validToken()
            let page: MediaPage = try await get(nextPage, token: token)
            let existing = Set(media.map(\.id))
            media.append(contentsOf: page.data.filter { !existing.contains($0.id) })
            self.nextPage = validated(page.paging?.next)
        } catch { errorMessage = error.localizedDescription }
    }

    func clear() {
        profile = nil
        media = []
        nextPage = nil
        errorMessage = nil
    }

    private func get<T: Decodable>(_ url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw InstagramAPIError.invalidPage }
        guard (200...299).contains(http.statusCode) else {
            let graphError = try? JSONDecoder().decode(GraphErrorEnvelope.self, from: data)
            if http.statusCode == 401 || graphError?.error.code == 190 {
                auth.signOut()
                clear()
            }
            throw InstagramAPIError.response(graphError?.error.message ?? "Instagram returned HTTP \(http.statusCode).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func validated(_ url: URL?) -> URL? {
        guard let url, url.scheme == "https", url.host == "graph.instagram.com" else { return nil }
        return url
    }

    private static func graphURL(_ path: String, fields: String, limit: Int? = nil) -> URL {
        var parts = URLComponents(string: "https://graph.instagram.com/\(path)")!
        parts.queryItems = [URLQueryItem(name: "fields", value: fields)]
        if let limit { parts.queryItems?.append(URLQueryItem(name: "limit", value: String(limit))) }
        return parts.url!
    }

    private struct MediaPage: Decodable {
        let data: [InstagramMedia]
        let paging: Paging?
    }
    private struct Paging: Decodable { let next: URL? }
    private struct GraphErrorEnvelope: Decodable { let error: GraphError }
    private struct GraphError: Decodable {
        let message: String
        let code: Int?
    }
}
