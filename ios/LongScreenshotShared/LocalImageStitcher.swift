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
        resizeMismatchedWidthsToFirst: Bool = false,
        compressionQuality: CGFloat = 0.92
    ) throws -> LocalImageStitchResult {
        guard !imageData.isEmpty else {
            throw LocalImageStitchingError.emptyImages
        }
        guard imageData.count >= 2 else {
            throw LocalImageStitchingError.notEnoughImages
        }

        var images = try imageData.map { data -> RGBAImage in
            guard let image = UIImage(data: data) else {
                throw LocalImageStitchingError.unreadableImage
            }
            return try RGBAImage(image: image)
        }

        guard let first = images.first else {
            throw LocalImageStitchingError.emptyImages
        }

        if !images.allSatisfy({ $0.width == first.width }) {
            guard resizeMismatchedWidthsToFirst else {
                throw LocalImageStitchingError.differentWidths
            }
            images = try images.map { try $0.resized(toWidth: first.width) }
        }

        guard let normalizedFirst = images.first else {
            throw LocalImageStitchingError.emptyImages
        }

        var stitchedBytes = normalizedFirst.bytes
        var stitchedHeight = normalizedFirst.height
        var overlaps: [Int] = []

        for index in images.indices.dropFirst() {
            let previous = images[index - 1]
            let current = images[index]
            if hasInsufficientPositionChange(previous, current, minOverlap: minOverlap) {
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

        guard let cgImage = makeCGImage(width: normalizedFirst.width, height: stitchedHeight, bytes: stitchedBytes),
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
        let minimumNewRows = minimumNewContentRows(for: current.height, minOverlap: minOverlap)
        let maximumOverlapWithNewContent = max(0, current.height - minimumNewRows)
        let highestPossibleOverlap = min(
            maximumAvailableOverlap,
            maxOverlap ?? maximumAvailableOverlap,
            maximumOverlapWithNewContent
        )
        let lowestPossibleOverlap = min(max(0, minOverlap), highestPossibleOverlap)

        guard highestPossibleOverlap > 0 else {
            return 0
        }

        var bestOverlap = lowestPossibleOverlap
        var bestScore = Double.greatestFiniteMagnitude
        let scoreTolerance = 0.75

        for overlap in lowestPossibleOverlap...highestPossibleOverlap {
            let score = sampledColorDifference(
                previous: previous,
                current: current,
                overlap: overlap
            )

            if score + scoreTolerance < bestScore {
                bestScore = score
                bestOverlap = overlap
            }
        }

        return bestOverlap
    }

    private func hasInsufficientPositionChange(_ previous: RGBAImage, _ current: RGBAImage, minOverlap: Int) -> Bool {
        guard previous.width == current.width, previous.height == current.height else {
            return false
        }
        if previous.bytes == current.bytes {
            return true
        }
        guard !hasLowVerticalVariation(previous), !hasLowVerticalVariation(current) else {
            return false
        }

        let minimumChangedRows = minimumNewContentRows(for: current.height, minOverlap: minOverlap)
        var changedRows = 0

        for row in 0..<current.height {
            if sampledRowColorDifference(previous: previous, previousRow: row, current: current, currentRow: row) > 2.0 {
                changedRows += 1
                if changedRows > minimumChangedRows {
                    return false
                }
            }
        }

        return true
    }

    private func hasLowVerticalVariation(_ image: RGBAImage) -> Bool {
        guard image.height > 1 else {
            return true
        }

        let maximumChangedAdjacentRows = max(1, image.height / 20)
        var changedAdjacentRows = 0

        for row in 1..<image.height {
            if sampledRowColorDifference(previous: image, previousRow: row - 1, current: image, currentRow: row) > 2.0 {
                changedAdjacentRows += 1
                if changedAdjacentRows > maximumChangedAdjacentRows {
                    return false
                }
            }
        }

        return true
    }

    private func minimumNewContentRows(for height: Int, minOverlap: Int) -> Int {
        let minimumRows = max(1, minOverlap)
        guard height > 8 else {
            return min(height, minimumRows)
        }
        return min(height, max(minimumRows, Int((Double(height) * 0.12).rounded(.up))))
    }

    private func sampledColorDifference(previous: RGBAImage, current: RGBAImage, overlap: Int) -> Double {
        guard overlap > 0 else {
            return Double.greatestFiniteMagnitude
        }

        let verticalSamples = min(overlap, 48)
        let firstPreviousRow = previous.height - overlap
        var totalDifference = 0.0
        var sampleCount = 0

        for sampleIndex in 0..<verticalSamples {
            let row = verticalSamples == 1 ? 0 : sampleIndex * (overlap - 1) / (verticalSamples - 1)
            totalDifference += sampledRowColorDifference(
                previous: previous,
                previousRow: firstPreviousRow + row,
                current: current,
                currentRow: row
            )
            sampleCount += 1
        }

        return sampleCount == 0 ? Double.greatestFiniteMagnitude : totalDifference / Double(sampleCount)
    }

    private func sampledRowColorDifference(
        previous: RGBAImage,
        previousRow: Int,
        current: RGBAImage,
        currentRow: Int
    ) -> Double {
        let horizontalStep = max(1, previous.width / 80)
        let previousRowOffset = previousRow * previous.bytesPerRow
        let currentRowOffset = currentRow * current.bytesPerRow
        var totalDifference = 0.0
        var sampleCount = 0

        for column in stride(from: 0, to: previous.width, by: horizontalStep) {
            let previousOffset = previousRowOffset + column * 4
            let currentOffset = currentRowOffset + column * 4
            totalDifference += colorDifference(previousOffset: previousOffset, currentOffset: currentOffset, previous: previous, current: current)
            sampleCount += 1
        }

        return sampleCount == 0 ? Double.greatestFiniteMagnitude : totalDifference / Double(sampleCount)
    }

    private func colorDifference(previousOffset: Int, currentOffset: Int, previous: RGBAImage, current: RGBAImage) -> Double {
        let redDifference = abs(Int(previous.bytes[previousOffset]) - Int(current.bytes[currentOffset]))
        let greenDifference = abs(Int(previous.bytes[previousOffset + 1]) - Int(current.bytes[currentOffset + 1]))
        let blueDifference = abs(Int(previous.bytes[previousOffset + 2]) - Int(current.bytes[currentOffset + 2]))
        return Double(redDifference + greenDifference + blueDifference) / 3.0
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

    func resized(toWidth targetWidth: Int) throws -> RGBAImage {
        guard targetWidth > 0 else {
            throw LocalImageStitchingError.renderingFailed
        }
        guard width != targetWidth else {
            return self
        }
        guard let cgImage = makeCGImage() else {
            throw LocalImageStitchingError.renderingFailed
        }

        let targetHeight = max(1, Int((Double(height) * Double(targetWidth) / Double(width)).rounded()))
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        let resizedImage = UIGraphicsImageRenderer(
            size: CGSize(width: CGFloat(targetWidth), height: CGFloat(targetHeight)),
            format: format
        ).image { _ in
            UIImage(cgImage: cgImage).draw(in: CGRect(x: 0, y: 0, width: CGFloat(targetWidth), height: CGFloat(targetHeight)))
        }
        return try RGBAImage(image: resizedImage)
    }

    private func makeCGImage() -> CGImage? {
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
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
