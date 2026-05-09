import XCTest
import UIKit
@testable import LongScreenshotShared

final class LocalImageStitcherTests: XCTestCase {
    func testStitchesTwoImagesByDetectedOverlap() throws {
        let first = try makeImageData(rows: [red, green, blue, yellow], width: 3)
        let second = try makeImageData(rows: [blue, yellow, cyan, magenta], width: 3)

        let result = try LocalImageStitcher().stitchImageData(
            [first, second],
            minOverlap: 1,
            maxOverlap: 3,
            compressionQuality: 1.0
        )

        XCTAssertEqual(result.overlaps, [2])
        let outputImage = try XCTUnwrap(UIImage(data: result.jpegData)?.cgImage)
        XCTAssertEqual(outputImage.width, 3)
        XCTAssertEqual(outputImage.height, 6)
    }

    func testUsesMinimumOverlapWhenRegionsAreUniform() throws {
        let first = try makeImageData(rows: Array(repeating: white, count: 200), width: 4)
        let second = try makeImageData(rows: Array(repeating: white, count: 199) + [cyan], width: 4)

        let result = try LocalImageStitcher().stitchImageData(
            [first, second],
            minOverlap: 20,
            compressionQuality: 1.0
        )

        XCTAssertEqual(result.overlaps, [20])
        let outputImage = try XCTUnwrap(UIImage(data: result.jpegData)?.cgImage)
        XCTAssertEqual(outputImage.height, 380)
    }

    func testNormalizesImageOrientationBeforeStitching() throws {
        let first = try makeOrientedImageData(rows: [red, green, blue], width: 2, orientation: .right)
        let second = try makeImageData(rows: [blue, yellow], width: 3)

        let result = try LocalImageStitcher().stitchImageData(
            [first, second],
            minOverlap: 1,
            maxOverlap: 1,
            compressionQuality: 1.0
        )

        let outputImage = try XCTUnwrap(UIImage(data: result.jpegData)?.cgImage)
        XCTAssertEqual(outputImage.width, 3)
        XCTAssertEqual(outputImage.height, 3)
    }

    func testRejectsSingleImageInput() throws {
        let image = try makeImageData(rows: [red, green, blue], width: 3)

        XCTAssertThrowsError(try LocalImageStitcher().stitchImageData([image], minOverlap: 1)) { error in
            XCTAssertEqual(error as? LocalImageStitchingError, .notEnoughImages)
        }
    }

    func testRejectsAdditionalImageWithoutNewContent() throws {
        let image = try makeImageData(rows: [red, green, blue, yellow], width: 3)

        XCTAssertThrowsError(try LocalImageStitcher().stitchImageData([image, image], minOverlap: 1)) { error in
            XCTAssertEqual(error as? LocalImageStitchingError, .insufficientNewContent)
        }
    }

    func testRejectsLowVariationDuplicateImageWithoutNewContent() throws {
        let image = try makeImageData(rows: Array(repeating: white, count: 80), width: 4)

        XCTAssertThrowsError(try LocalImageStitcher().stitchImageData([image, image], minOverlap: 20)) { error in
            XCTAssertEqual(error as? LocalImageStitchingError, .insufficientNewContent)
        }
    }

    func testRejectsNearDuplicateImageWithoutMeaningfulNewContent() throws {
        let first = try makeImageData(rows: [red, green, blue, yellow], width: 3)
        let second = try makeImageData(rows: [red, green, blue, cyan], width: 3)

        XCTAssertThrowsError(try LocalImageStitcher().stitchImageData([first, second], minOverlap: 1)) { error in
            XCTAssertEqual(error as? LocalImageStitchingError, .insufficientNewContent)
        }
    }

    func testRejectsNearDuplicateImageWithOnlyHeaderChange() throws {
        let first = try makeImageData(rows: [red, green, blue, yellow], width: 3)
        let second = try makeImageData(rows: [cyan, green, blue, yellow], width: 3)

        XCTAssertThrowsError(try LocalImageStitcher().stitchImageData([first, second], minOverlap: 1)) { error in
            XCTAssertEqual(error as? LocalImageStitchingError, .insufficientNewContent)
        }
    }

    func testAllowsLargeOverlapWhenThereIsEnoughNewContent() throws {
        let first = try makeImageData(rows: [red, green, blue, yellow], width: 3)
        let second = try makeImageData(rows: [green, blue, yellow, cyan, magenta], width: 3)

        let result = try LocalImageStitcher().stitchImageData([first, second], minOverlap: 1, compressionQuality: 1.0)

        XCTAssertEqual(result.overlaps, [3])
        let outputImage = try XCTUnwrap(UIImage(data: result.jpegData)?.cgImage)
        XCTAssertEqual(outputImage.height, 6)
    }

    func testStitchesThreeSequentialImagesWithoutSwallowingLastImage() throws {
        let rows = uniqueRows(count: 14)
        let first = try makeImageData(rows: Array(rows[0..<6]), width: 4)
        let second = try makeImageData(rows: Array(rows[4..<10]), width: 4)
        let third = try makeImageData(rows: Array(rows[8..<14]), width: 4)

        let result = try LocalImageStitcher().stitchImageData(
            [first, second, third],
            minOverlap: 1,
            compressionQuality: 1.0
        )

        XCTAssertEqual(result.overlaps, [2, 2])
        let outputImage = try XCTUnwrap(UIImage(data: result.jpegData)?.cgImage)
        XCTAssertEqual(outputImage.height, 14)
    }

    func testStitchesFourSequentialImagesWithRepeatedSimpleRows() throws {
        let rows = uniqueRows(count: 8)
        let first = try makeImageData(rows: [white, white, rows[0], rows[1], rows[2], rows[3]], width: 4)
        let second = try makeImageData(rows: [rows[2], rows[3], white, white, rows[4], rows[5]], width: 4)
        let third = try makeImageData(rows: [rows[4], rows[5], white, white, rows[6], rows[7]], width: 4)
        let fourth = try makeImageData(rows: [rows[6], rows[7], white, white, cyan, magenta], width: 4)

        let result = try LocalImageStitcher().stitchImageData(
            [first, second, third, fourth],
            minOverlap: 1,
            compressionQuality: 1.0
        )

        XCTAssertEqual(result.overlaps, [2, 2, 2])
        let outputImage = try XCTUnwrap(UIImage(data: result.jpegData)?.cgImage)
        XCTAssertEqual(outputImage.height, 18)
    }

    func testRejectsEmptyInput() {
        XCTAssertThrowsError(try LocalImageStitcher().stitchImageData([])) { error in
            XCTAssertEqual(error as? LocalImageStitchingError, .emptyImages)
        }
    }

    func testRejectsInvalidImageData() {
        let invalidImageData = Data([0x00, 0x01, 0x02])

        XCTAssertThrowsError(try LocalImageStitcher().stitchImageData([invalidImageData, invalidImageData])) { error in
            XCTAssertEqual(error as? LocalImageStitchingError, .unreadableImage)
        }
    }

    func testRejectsDifferentWidths() throws {
        let first = try makeImageData(rows: [red, green], width: 3)
        let second = try makeImageData(rows: [red, green], width: 4)

        XCTAssertThrowsError(try LocalImageStitcher().stitchImageData([first, second], minOverlap: 1)) { error in
            XCTAssertEqual(error as? LocalImageStitchingError, .differentWidths)
        }
    }

    func testResizesDifferentWidthsToFirstImageWidthWhenAllowed() throws {
        let first = try makeImageData(rows: [red, green, blue], width: 3)
        let second = try makeImageData(rows: [blue, yellow], width: 4)

        let result = try LocalImageStitcher().stitchImageData(
            [first, second],
            minOverlap: 1,
            resizeMismatchedWidthsToFirst: true,
            compressionQuality: 1.0
        )

        XCTAssertEqual(result.overlaps, [1])
        let outputImage = try XCTUnwrap(UIImage(data: result.jpegData)?.cgImage)
        XCTAssertEqual(outputImage.width, 3)
        XCTAssertEqual(outputImage.height, 4)
    }
}

private struct TestRGB {
    let r: UInt8
    let g: UInt8
    let b: UInt8
}

private let red = TestRGB(r: 255, g: 0, b: 0)
private let green = TestRGB(r: 0, g: 255, b: 0)
private let blue = TestRGB(r: 0, g: 0, b: 255)
private let yellow = TestRGB(r: 255, g: 255, b: 0)
private let cyan = TestRGB(r: 0, g: 255, b: 255)
private let magenta = TestRGB(r: 255, g: 0, b: 255)
private let white = TestRGB(r: 255, g: 255, b: 255)

private func uniqueRows(count: Int) -> [TestRGB] {
    (0..<count).map { index in
        TestRGB(
            r: UInt8((index * 53 + 31) % 256),
            g: UInt8((index * 97 + 17) % 256),
            b: UInt8((index * 193 + 71) % 256)
        )
    }
}

private func makeImageData(rows: [TestRGB], width: Int) throws -> Data {
    let image = try makeCGImage(rows: rows, width: width)
    return try XCTUnwrap(UIImage(cgImage: image).pngData())
}

private func makeOrientedImageData(rows: [TestRGB], width: Int, orientation: UIImage.Orientation) throws -> Data {
    let image = try makeCGImage(rows: rows, width: width)
    return try XCTUnwrap(UIImage(cgImage: image, scale: 1, orientation: orientation).jpegData(compressionQuality: 1.0))
}

private func makeCGImage(rows: [TestRGB], width: Int) throws -> CGImage {
    var bytes: [UInt8] = []
    for row in rows {
        for _ in 0..<width {
            bytes.append(row.r)
            bytes.append(row.g)
            bytes.append(row.b)
            bytes.append(255)
        }
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let provider = CGDataProvider(data: Data(bytes) as CFData)
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    return try XCTUnwrap(CGImage(
        width: width,
        height: rows.count,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo,
        provider: try XCTUnwrap(provider),
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ))
}
