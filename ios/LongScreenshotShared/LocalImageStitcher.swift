import Foundation
import CoreGraphics
import UIKit

public struct LocalImageStitchResult: Equatable {
    public let jpegData: Data
    public let overlaps: [Int]

    public init(jpegData: Data, overlaps: [Int]) {
        self.jpegData = jpegData
        self.overlaps = overlaps
    }
}

public enum LocalImageStitchingError: Error, LocalizedError, Equatable {
    case emptyImages
    case unreadableImage
    case differentWidths
    case renderingFailed

    public var errorDescription: String? {
        switch self {
        case .emptyImages:
            return "没有可拼接的图片。"
        case .unreadableImage:
            return "无法读取图片数据。"
        case .differentWidths:
            return "图片宽度不一致，无法拼接。"
        case .renderingFailed:
            return "图片渲染失败。"
        }
    }
}

public struct LocalImageStitcher {
    public init() {}

    public func stitchImageData(
        _ imageData: [Data],
        minOverlap: Int = 20,
        maxOverlap: Int? = nil,
        compressionQuality: CGFloat = 0.92
    ) throws -> LocalImageStitchResult {
        guard !imageData.isEmpty else {
            throw LocalImageStitchingError.emptyImages
        }

        let images = try imageData.map { data -> RGBAImage in
            guard let image = UIImage(data: data)?.cgImage else {
                throw LocalImageStitchingError.unreadableImage
            }
            return try RGBAImage(cgImage: image)
        }

        guard let first = images.first else {
            throw LocalImageStitchingError.emptyImages
        }

        guard images.allSatisfy({ $0.width == first.width }) else {
            throw LocalImageStitchingError.differentWidths
        }

        var stitchedBytes = first.bytes
        var stitchedHeight = first.height
        var overlaps: [Int] = []

        for index in images.indices.dropFirst() {
            let previous = images[index - 1]
            let current = images[index]
            let overlap = detectOverlap(
                previous: previous,
                current: current,
                minOverlap: minOverlap,
                maxOverlap: maxOverlap
            )
            overlaps.append(overlap)

            let startRow = min(overlap, current.height)
            if startRow < current.height {
                let startByte = startRow * current.bytesPerRow
                stitchedBytes.append(contentsOf: current.bytes[startByte...])
                stitchedHeight += current.height - startRow
            }
        }

        guard let cgImage = makeCGImage(width: first.width, height: stitchedHeight, bytes: stitchedBytes),
              let jpegData = UIImage(cgImage: cgImage).jpegData(compressionQuality: compressionQuality) else {
            throw LocalImageStitchingError.renderingFailed
        }

        return LocalImageStitchResult(jpegData: jpegData, overlaps: overlaps)
    }

    private func detectOverlap(
        previous: RGBAImage,
        current: RGBAImage,
        minOverlap: Int,
        maxOverlap: Int?
    ) -> Int {
        let highestPossibleOverlap = min(previous.height, current.height, maxOverlap ?? min(previous.height, current.height))
        let lowestPossibleOverlap = min(max(0, minOverlap), highestPossibleOverlap)

        guard highestPossibleOverlap > 0 else {
            return 0
        }

        var bestOverlap = lowestPossibleOverlap
        var bestScore = Double.greatestFiniteMagnitude

        for overlap in lowestPossibleOverlap...highestPossibleOverlap {
            let score = sampledLumaDifference(
                previous: previous,
                current: current,
                overlap: overlap
            )

            if score < bestScore {
                bestScore = score
                bestOverlap = overlap
            }
        }

        return bestOverlap
    }

    private func sampledLumaDifference(previous: RGBAImage, current: RGBAImage, overlap: Int) -> Double {
        guard overlap > 0 else {
            return Double.greatestFiniteMagnitude
        }

        let horizontalStep = max(1, previous.width / 80)
        let verticalSamples = min(overlap, 48)
        let firstPreviousRow = previous.height - overlap
        var totalDifference = 0.0
        var sampleCount = 0

        for sampleIndex in 0..<verticalSamples {
            let row = verticalSamples == 1 ? 0 : sampleIndex * (overlap - 1) / (verticalSamples - 1)
            let previousRowOffset = (firstPreviousRow + row) * previous.bytesPerRow
            let currentRowOffset = row * current.bytesPerRow

            for column in stride(from: 0, to: previous.width, by: horizontalStep) {
                let previousOffset = previousRowOffset + column * 4
                let currentOffset = currentRowOffset + column * 4

                totalDifference += abs(luma(at: previousOffset, in: previous.bytes) - luma(at: currentOffset, in: current.bytes))
                sampleCount += 1
            }
        }

        return sampleCount == 0 ? Double.greatestFiniteMagnitude : totalDifference / Double(sampleCount)
    }

    private func luma(at offset: Int, in bytes: [UInt8]) -> Double {
        let red = Double(bytes[offset])
        let green = Double(bytes[offset + 1])
        let blue = Double(bytes[offset + 2])
        return 0.299 * red + 0.587 * green + 0.114 * blue
    }

    private func makeCGImage(width: Int, height: Int, bytes: [UInt8]) -> CGImage? {
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

private struct RGBAImage {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let bytes: [UInt8]

    init(cgImage: CGImage) throws {
        self.width = cgImage.width
        self.height = cgImage.height
        self.bytesPerRow = cgImage.width * 4

        var buffer = [UInt8](repeating: 0, count: cgImage.height * cgImage.width * 4)
        try buffer.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: cgImage.width,
                    height: cgImage.height,
                    bitsPerComponent: 8,
                    bytesPerRow: cgImage.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                throw LocalImageStitchingError.unreadableImage
            }

            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        }
        self.bytes = buffer
    }
}
