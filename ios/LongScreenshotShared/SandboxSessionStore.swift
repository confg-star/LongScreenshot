import Foundation

public final class SandboxSessionStore {
    public let rootDirectory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public convenience init(fileManager: FileManager = .default) throws {
        let root = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("LongScreenshotSessions", isDirectory: true)
        try self.init(rootDirectory: root, fileManager: fileManager)
    }

    public init(rootDirectory: URL, fileManager: FileManager = .default) throws {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
        try fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    }

    public var sessionsDirectory: URL {
        rootDirectory.appendingPathComponent("sessions", isDirectory: true)
    }

    public func sessionDirectory(sessionID: String) -> URL {
        sessionsDirectory.appendingPathComponent(sessionID, isDirectory: true)
    }

    public func imageURL(sessionID: String, fileName: String) -> URL {
        sessionDirectory(sessionID: sessionID).appendingPathComponent(fileName)
    }

    public func resultURL(sessionID: String, fileName: String) -> URL {
        sessionDirectory(sessionID: sessionID).appendingPathComponent(fileName)
    }

    public func manifestURL(sessionID: String) -> URL {
        sessionDirectory(sessionID: sessionID).appendingPathComponent("manifest.json")
    }

    public func save(_ manifest: ImportSessionManifest) throws {
        let directory = sessionDirectory(sessionID: manifest.sessionID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL(sessionID: manifest.sessionID), options: [.atomic])
    }

    public func loadManifest(sessionID: String) throws -> ImportSessionManifest {
        let data = try Data(contentsOf: manifestURL(sessionID: sessionID))
        return try decoder.decode(ImportSessionManifest.self, from: data)
    }

    public func listManifests() throws -> [ImportSessionManifest] {
        guard fileManager.fileExists(atPath: sessionsDirectory.path) else { return [] }
        let directories = try fileManager.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil)
        let manifests = directories.compactMap { directory -> ImportSessionManifest? in
            let manifestURL = directory.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL) else { return nil }
            return try? decoder.decode(ImportSessionManifest.self, from: data)
        }
        return manifests.sorted { $0.createdAt > $1.createdAt }
    }
}
