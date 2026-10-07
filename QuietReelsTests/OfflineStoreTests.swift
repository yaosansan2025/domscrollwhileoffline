import Foundation
import XCTest
@testable import QuietReels

final class OfflineStoreTests: XCTestCase {
    @MainActor
    func testRejectsNonVideoImportWithoutChangingLibrary() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("not-a-video.txt")
        try Data("not a video".utf8).write(to: source)

        let store = AuthorizedOfflineStore(directory: directory)
        let initialCount = store.reels.count
        await store.importFile(source)

        XCTAssertEqual(store.reels.count, initialCount)
        XCTAssertNotNil(store.errorMessage)
    }

    @MainActor
    func testAccountPersistenceKeepsOlderOfflineIndex() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacyFile = directory.appendingPathComponent("old.mp4")
        try Data([1]).write(to: legacyFile)
        let legacyIndex = """
        [{"id":"old","creator":"Imported video","caption":"old",
          "fileName":"old.mp4","savedAt":0,"byteCount":1}]
        """
        try Data(legacyIndex.utf8).write(to: directory.appendingPathComponent("offline-index.json"))

        let store = AuthorizedOfflineStore(directory: directory)
        XCTAssertEqual(store.reels.count, 1)
        XCTAssertNil(store.reels.first?.accountID)
        try store.addAccount(username: "@Example.Creator")
        XCTAssertEqual(store.accounts.first?.username, "example.creator")
        XCTAssertThrowsError(try store.addAccount(username: "example.creator"))

        let reopened = AuthorizedOfflineStore(directory: directory)
        XCTAssertEqual(reopened.accounts.first?.username, "example.creator")
        try reopened.removeAccount(try XCTUnwrap(reopened.accounts.first))
        XCTAssertEqual(reopened.reels.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyFile.path))
    }
}
