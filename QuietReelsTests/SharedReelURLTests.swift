import XCTest
@testable import QuietReels

@MainActor
final class SharedReelURLTests: XCTestCase {
    func testSharedReelURLKeepsOnlyTheChosenReel() throws {
        let url = try LibraryStore.canonicalReelURL(
            " https://instagram.com/reel/Cabc_123/?igsh=shared "
        )
        XCTAssertEqual(url, "https://www.instagram.com/reel/Cabc_123/")
    }

    func testDiscoveryAndOtherHostsCannotBeAddedAsSharedReels() {
        let blocked = [
            "https://www.instagram.com/explore/",
            "https://www.instagram.com/reels/",
            "https://example.com/reel/Cabc_123/",
            "https://www.instagram.com/reel/Cabc_123/another",
            "http://www.instagram.com/reel/Cabc_123/"
        ]
        for url in blocked {
            XCTAssertThrowsError(try LibraryStore.canonicalReelURL(url), url)
        }
    }

    func testVideoSourceRequiresDirectSecureFileURL() throws {
        let video = try LibraryStore.validatedDirectVideoURL(
            "https://media.example.com/shared.mp4"
        )
        XCTAssertEqual(video.pathExtension, "mp4")

        let blocked = [
            "http://media.example.com/shared.mp4",
            "https://media.example.com/watch?id=123",
            "https://user:password@media.example.com/shared.mp4",
            "https://media.example.com/shared.mp4#fragment"
        ]
        for url in blocked {
            XCTAssertThrowsError(try LibraryStore.validatedDirectVideoURL(url), url)
        }
    }
}
