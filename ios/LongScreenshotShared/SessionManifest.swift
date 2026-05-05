import Foundation

public enum ImportSessionStatus: String, Codable, Equatable {
    case draft
    case ready
    case uploading
    case stitched
    case saved
    case failed
}

public struct ImportedImageRecord: Codable, Equatable {
    public let fileName: String
    public let order: Int

    public init(fileName: String, order: Int) {
        self.fileName = fileName
        self.order = order
    }
}

public struct ImportSessionManifest: Codable, Equatable {
    public let sessionID: String
    public let createdAt: Date
    public var status: ImportSessionStatus
    public var images: [ImportedImageRecord]
    public var resultFileName: String?
    public var failureReason: String?

    public init(sessionID: String, createdAt: Date) {
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.status = .draft
        self.images = []
        self.resultFileName = nil
        self.failureReason = nil
    }
}
