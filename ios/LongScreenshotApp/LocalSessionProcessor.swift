import Foundation
import LongScreenshotShared

struct LocalSessionProcessor {
    let store: SandboxSessionStore
    let stitcher: LocalImageStitcher

    init(store: SandboxSessionStore, stitcher: LocalImageStitcher = LocalImageStitcher()) {
        self.store = store
        self.stitcher = stitcher
    }

    func stitch(manifest: ImportSessionManifest, resizeMismatchedWidthsToFirst: Bool = false) throws -> (data: Data, manifest: ImportSessionManifest) {
        let orderedImages = manifest.images.sorted { $0.order < $1.order }
        let imageData = try orderedImages.map { image in
            try Data(contentsOf: store.imageURL(sessionID: manifest.sessionID, fileName: image.fileName))
        }
        let result = try stitcher.stitchImageData(imageData, resizeMismatchedWidthsToFirst: resizeMismatchedWidthsToFirst)
        let resultFileName = "result.jpg"
        try result.jpegData.write(to: store.resultURL(sessionID: manifest.sessionID, fileName: resultFileName), options: [.atomic])

        var updatedManifest = manifest
        updatedManifest.resultFileName = resultFileName
        updatedManifest.status = .stitched
        updatedManifest.failureReason = nil
        try store.save(updatedManifest)

        return (result.jpegData, updatedManifest)
    }
}
