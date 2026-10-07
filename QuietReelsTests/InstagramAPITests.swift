import Foundation
import XCTest
@testable import QuietReels

final class InstagramAPITests: XCTestCase {
    func testOwnMediaSeparatesPlayableVideosFromOtherPosts() throws {
        let payload = """
        [
          {"id":"1","media_type":"VIDEO",
           "media_url":"https://cdn.example.com/own.mp4","caption":"My reel",
           "username":"creator","like_count":12,"comments_count":2},
          {"id":"2","media_type":"IMAGE","media_url":"https://cdn.example.com/photo.jpg"},
          {"id":"3","media_type":"VIDEO"}
        ]
        """
        let media = try JSONDecoder().decode([InstagramMedia].self, from: Data(payload.utf8))
        XCTAssertEqual(media.filter(\.isVideo).map(\.id), ["1"])
        XCTAssertEqual(media[0].likeCount, 12)
        XCTAssertEqual(media[0].caption, "My reel")
    }
}
