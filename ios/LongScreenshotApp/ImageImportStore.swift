import Foundation
import LongScreenshotShared

struct ImageImportStore {
    let store: SandboxSessionStore

    func createSession(from imageData: [Data]) throws -> ImportSessionManifest {
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let sessionID = "\(timestamp)-\(UUID().uuidString)"
        var manifest = ImportSessionManifest(sessionID: sessionID, createdAt: Date())
        let directory = store.sessionDirectory(sessionID: sessionID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (index, data) in imageData.enumerated() {
            let fileName = String(format: "image-%05d.jpg", index + 1)
            try data.write(to: store.imageURL(sessionID: sessionID, fileName: fileName), options: [.atomic])
            manifest.images.append(ImportedImageRecord(fileName: fileName, order: index))
        }

        manifest.status = imageData.isEmpty ? .draft : .ready
        try store.save(manifest)
        return manifest
    }
}
