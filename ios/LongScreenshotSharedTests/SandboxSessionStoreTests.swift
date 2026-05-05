import XCTest
@testable import LongScreenshotShared

final class SandboxSessionStoreTests: XCTestCase {
    func testCreatesAndLoadsManifestInInjectedDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = try SandboxSessionStore(rootDirectory: root)

        var manifest = ImportSessionManifest(sessionID: "session-1", createdAt: Date(timeIntervalSince1970: 10))
        manifest.images.append(ImportedImageRecord(fileName: "image-00001.jpg", order: 0))
        manifest.status = .ready

        try store.save(manifest)
        let loaded = try store.loadManifest(sessionID: "session-1")

        XCTAssertEqual(loaded.sessionID, "session-1")
        XCTAssertEqual(loaded.images.count, 1)
        XCTAssertEqual(loaded.images[0].fileName, "image-00001.jpg")
        XCTAssertEqual(loaded.status, .ready)
    }

    func testListsSessionManifestsNewestFirst() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = try SandboxSessionStore(rootDirectory: root)

        try store.save(ImportSessionManifest(sessionID: "older", createdAt: Date(timeIntervalSince1970: 10)))
        try store.save(ImportSessionManifest(sessionID: "newer", createdAt: Date(timeIntervalSince1970: 20)))

        let manifests = try store.listManifests()

        XCTAssertEqual(manifests.map(\.sessionID), ["newer", "older"])
    }
}
