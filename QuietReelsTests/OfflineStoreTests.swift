import Foundation
import XCTest
@testable import QuietReels

final class OfflineStoreTests: XCTestCase {
    @MainActor
    func testRejectsNonVideoImportWithoutChangingLibrary() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".txt")
        try Data("not a video".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let store = AuthorizedOfflineStore()
        let initialCount = store.reels.count
        await store.importFile(source)

        XCTAssertEqual(store.reels.count, initialCount)
        XCTAssertNotNil(store.errorMessage)
    }
}
