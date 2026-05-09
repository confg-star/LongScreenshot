import Foundation
import CoreGraphics
import UIKit

public struct LocalImageStitchResult: Equatable, Sendable {
    public let jpegData: Data
    public let overlaps: [Int]

    public init(jpegData: Data, overlaps: [Int]) {
        self.jpegData = jpegData
        self.overlaps = overlaps
    }
}

public enum LocalImageStitchingError: Error, LocalizedError, Equatable, Sendable {
    case emptyImages
    case notEnoughImages
    case unreadableImage
    case differentWidths
    case insufficientNewContent
    case renderingFailed

    public var errorDescription: String? {
        switch self {
        case .emptyImages:
            return "没有可拼接的图片。"
        case .notEnoughImages:
            return "请至少选择 2 张有重叠区域的截图。"
        case .unreadableImage:
            return "无法读取图片数据。"
        case .differentWidths:
            return "图片宽度不一致，无法拼接。"
        case .insufficientNewContent:
            return "后续截图没有检测到新增内容，请重新选择有重叠且继续向下滚动后的截图。"
        case .renderingFailed:
            return "图片渲染失败。"
        }
    }
}

public struct LocalImageStitcher: Sendable {
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
        guard imageData.count >= 2 else {
            throw LocalImageStitchingError.notEnoughImages
        }

        let images = try imageData.map { data -> RGBAImage in
            guard let image = UIImage(data: data) else {
                throw LocalImageStitchingError.unreadableImage
            }
            return try RGBAImage(image: image)
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
            if isVisuallyDuplicate(previous, current) {
                throw LocalImageStitchingError.insufficientNewContent
            }

            let overlap = detectOverlap(
                previous: previous,
                current: current,
                minOverlap: minOverlap,
                maxOverlap: maxOverlap
            )
            overlaps.append(overlap)

            let startRow = min(overlap, current.height)
            let newRows = current.height - startRow
            guard newRows >= minimumNewContentRows(for: current.height, minOverlap: minOverlap) else {
                throw LocalImageStitchingError.insufficientNewContent
            }

            let startByte = startRow * current.bytesPerRow
            stitchedBytes.append(contentsOf: current.bytes[startByte...])
            stitchedHeight += current.height - startRow
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
        let maximumAvailableOverlap = min(previous.height, current.height)
        let highestPossibleOverlap = min(maximumAvailableOverlap, maxOverlap ?? maximumAvailableOverlap)
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

    private func isVisuallyDuplicate(_ previous: RGBAImage, _ current: RGBAImage) -> Bool {
        previous.width == current.width && previous.height == current.height && previous.bytes == current.bytes
    }

    private func minimumNewContentRows(for height: Int, minOverlap: Int) -> Int {
        min(height, max(1, minOverlap))
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

    init(image: UIImage) throws {
        guard let cgImage = image.normalizedCGImage else {
            throw LocalImageStitchingError.unreadableImage
        }

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

private extension UIImage {
    var normalizedCGImage: CGImage? {
        guard imageOrientation != .up else {
            return cgImage
        }

        guard let cgImage else {
            return nil
        }

        let size: CGSize
        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            size = CGSize(width: CGFloat(cgImage.height), height: CGFloat(cgImage.width))
        default:
            size = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}
