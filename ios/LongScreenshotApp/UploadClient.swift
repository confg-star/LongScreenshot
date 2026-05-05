import Foundation
import LongScreenshotShared

struct UploadClient {
    let stitchURL: URL
    let session: URLSession

    init(stitchURL: URL, session: URLSession = .shared) {
        self.stitchURL = stitchURL
        self.session = session
    }

    func upload(manifest: ImportSessionManifest, store: SandboxSessionStore) async throws -> Data {
        var request = URLRequest(url: stitchURL)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        for image in manifest.images.sorted(by: { $0.order < $1.order }) {
            let imageData = try Data(contentsOf: store.imageURL(sessionID: manifest.sessionID, fileName: image.fileName))
            body.appendMultipartFile(fieldName: "frames", fileName: image.fileName, mimeType: "image/jpeg", data: imageData, boundary: boundary)
        }
        body.appendString("--\(boundary)--\r\n")

        let (data, response) = try await session.upload(for: request, from: body)
        guard let httpResponse = response as? HTTPURLResponse else { throw UploadError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            throw UploadError.serverStatus(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    enum UploadError: LocalizedError {
        case invalidResponse
        case serverStatus(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The stitching server returned a non-HTTP response."
            case .serverStatus(let status, let body):
                return "The stitching server returned HTTP \(status): \(body)"
            }
        }
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendMultipartFile(fieldName: String, fileName: String, mimeType: String, data: Data, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(data)
        appendString("\r\n")
    }
}
