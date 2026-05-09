import XCTest
import UIKit
@testable import LongScreenshotShared

final class LocalImageStitcherTests: XCTestCase {
    func testStitchesTwoImagesByDetectedOverlap() throws {
        let firstRows: [TestRGB] = [red, green, blue, yellow]
        let secondRows: [TestRGB] = [blue, yellow, cyan, magenta]
        let first: Data = try makeImageData(rows: firstRows, width: 3)
        let second: Data = try makeImageData(rows: secondRows, width: 3)
        let images: [Data] = [first, second]

        let result: LocalImageStitchResult = try stitchImages(images, minOverlap: 1, maxOverlap: 3)

        assertOverlaps(result.overlaps, [2])
        let outputImage: CGImage = try outputCGImage(from: result)
        XCTAssertEqual(outputImage.width, 3)
        XCTAssertEqual(outputImage.height, 6)
    }

    func testUsesMinimumOverlapWhenRegionsAreUniform() throws {
        let firstRows: [TestRGB] = Array(repeating: white, count: 200)
        var secondRows: [TestRGB] = Array(repeating: white, count: 199)
        secondRows.append(cyan)
        let first: Data = try makeImageData(rows: firstRows, width: 4)
        let second: Data = try makeImageData(rows: secondRows, width: 4)
        let images: [Data] = [first, second]

        let result: LocalImageStitchResult = try stitchImages(images, minOverlap: 20)

        assertOverlaps(result.overlaps, [20])
        let outputImage: CGImage = try outputCGImage(from: result)
        XCTAssertEqual(outputImage.height, 380)
    }

    func testNormalizesImageOrientationBeforeStitching() throws {
        let firstRows: [TestRGB] = [red, green, blue]
        let secondRows: [TestRGB] = [blue, yellow]
        let first: Data = try makeOrientedImageData(rows: firstRows, width: 2, orientation: .right)
        let second: Data = try makeImageData(rows: secondRows, width: 3)
        let images: [Data] = [first, second]

        let result: LocalImageStitchResult = try stitchImages(images, minOverlap: 1, maxOverlap: 1)

        let outputImage: CGImage = try outputCGImage(from: result)
        XCTAssertEqual(outputImage.width, 3)
        XCTAssertEqual(outputImage.height, 3)
    }

    func testRejectsSingleImageInput() throws {
        let rows: [TestRGB] = [red, green, blue]
        let image: Data = try makeImageData(rows: rows, width: 3)
        let images: [Data] = [image]

        assertStitchingThrows(images, minOverlap: 1, expectedError: .notEnoughImages)
    }

    func testRejectsAdditionalImageWithoutNewContent() throws {
        let rows: [TestRGB] = [red, green, blue, yellow]
        let image: Data = try makeImageData(rows: rows, width: 3)
        let images: [Data] = [image, image]

        assertStitchingThrows(images, minOverlap: 1, expectedError: .insufficientNewContent)
    }

    func testRejectsLowVariationDuplicateImageWithoutNewContent() throws {
        let rows: [TestRGB] = Array(repeating: white, count: 80)
        let image: Data = try makeImageData(rows: rows, width: 4)
        let images: [Data] = [image, image]

        assertStitchingThrows(images, minOverlap: 20, expectedError: .insufficientNewContent)
    }

    func testRejectsNearDuplicateImageWithoutMeaningfulNewContent() throws {
        let firstRows: [TestRGB] = [red, green, blue, yellow]
        let secondRows: [TestRGB] = [red, green, blue, cyan]
        let first: Data = try makeImageData(rows: firstRows, width: 3)
        let second: Data = try makeImageData(rows: secondRows, width: 3)
        let images: [Data] = [first, second]

        assertStitchingThrows(images, minOverlap: 1, expectedError: .insufficientNewContent)
    }

    func testRejectsNearDuplicateImageWithOnlyHeaderChange() throws {
        let firstRows: [TestRGB] = [red, green, blue, yellow]
        let secondRows: [TestRGB] = [cyan, green, blue, yellow]
        let first: Data = try makeImageData(rows: firstRows, width: 3)
        let second: Data = try makeImageData(rows: secondRows, width: 3)
        let images: [Data] = [first, second]

        assertStitchingThrows(images, minOverlap: 1, expectedError: .insufficientNewContent)
    }

    func testAllowsLargeOverlapWhenThereIsEnoughNewContent() throws {
        let firstRows: [TestRGB] = [red, green, blue, yellow]
        let secondRows: [TestRGB] = [green, blue, yellow, cyan, magenta]
        let first: Data = try makeImageData(rows: firstRows, width: 3)
        let second: Data = try makeImageData(rows: secondRows, width: 3)
        let images: [Data] = [first, second]

        let result: LocalImageStitchResult = try stitchImages(images, minOverlap: 1)

        assertOverlaps(result.overlaps, [3])
        let outputImage: CGImage = try outputCGImage(from: result)
        XCTAssertEqual(outputImage.height, 6)
    }

    func testStitchesThreeSequentialImagesWithoutSwallowingLastImage() throws {
        let rows: [TestRGB] = uniqueRows(count: 14)
        let firstRows: [TestRGB] = Array(rows[0..<6])
        let secondRows: [TestRGB] = Array(rows[4..<10])
        let thirdRows: [TestRGB] = Array(rows[8..<14])
        let first: Data = try makeImageData(rows: firstRows, width: 4)
        let second: Data = try makeImageData(rows: secondRows, width: 4)
        let third: Data = try makeImageData(rows: thirdRows, width: 4)
        let images: [Data] = [first, second, third]

        let result: LocalImageStitchResult = try stitchImages(images, minOverlap: 1)

        assertOverlaps(result.overlaps, [2, 2])
        let outputImage: CGImage = try outputCGImage(from: result)
        XCTAssertEqual(outputImage.height, 14)
    }

    func testStitchesFourSequentialImagesWithRepeatedSimpleRows() throws {
        let rows: [TestRGB] = uniqueRows(count: 8)
        let firstRows: [TestRGB] = [white, white, rows[0], rows[1], rows[2], rows[3]]
        let secondRows: [TestRGB] = [rows[2], rows[3], white, white, rows[4], rows[5]]
        let thirdRows: [TestRGB] = [rows[4], rows[5], white, white, rows[6], rows[7]]
        let fourthRows: [TestRGB] = [rows[6], rows[7], white, white, cyan, magenta]
        let first: Data = try makeImageData(rows: firstRows, width: 4)
        let second: Data = try makeImageData(rows: secondRows, width: 4)
        let third: Data = try makeImageData(rows: thirdRows, width: 4)
        let fourth: Data = try makeImageData(rows: fourthRows, width: 4)
        let images: [Data] = [first, second, third, fourth]

        let result: LocalImageStitchResult = try stitchImages(images, minOverlap: 1)

        assertOverlaps(result.overlaps, [2, 2, 2])
        let outputImage: CGImage = try outputCGImage(from: result)
        XCTAssertEqual(outputImage.height, 18)
    }

    func testRejectsEmptyInput() {
        let images: [Data] = []

        assertStitchingThrows(images, expectedError: .emptyImages)
    }

    func testRejectsInvalidImageData() {
        let invalidBytes: [UInt8] = [0x00, 0x01, 0x02]
        let invalidImageData: Data = Data(invalidBytes)
        let images: [Data] = [invalidImageData, invalidImageData]

        assertStitchingThrows(images, expectedError: .unreadableImage)
    }

    func testRejectsDifferentWidths() throws {
        let firstRows: [TestRGB] = [red, green]
        let secondRows: [TestRGB] = [red, green]
        let first: Data = try makeImageData(rows: firstRows, width: 3)
        let second: Data = try makeImageData(rows: secondRows, width: 4)
        let images: [Data] = [first, second]

        assertStitchingThrows(images, minOverlap: 1, expectedError: .differentWidths)
    }

    func testResizesDifferentWidthsToFirstImageWidthWhenAllowed() throws {
        let firstRows: [TestRGB] = [red, green, blue]
        let secondRows: [TestRGB] = [blue, yellow]
        let first: Data = try makeImageData(rows: firstRows, width: 3)
        let second: Data = try makeImageData(rows: secondRows, width: 4)
        let images: [Data] = [first, second]

        let result: LocalImageStitchResult = try stitchImages(
            images,
            minOverlap: 1,
            resizeMismatchedWidthsToFirst: true
        )

        assertOverlaps(result.overlaps, [1])
        let outputImage: CGImage = try outputCGImage(from: result)
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

private func stitchImages(
    _ imageData: [Data],
    minOverlap: Int = 20,
    maxOverlap: Int? = nil,
    resizeMismatchedWidthsToFirst: Bool = false,
    compressionQuality: CGFloat = 1.0
) throws -> LocalImageStitchResult {
    let stitcher = LocalImageStitcher()
    let result: LocalImageStitchResult = try stitcher.stitchImageData(
        imageData,
        minOverlap: minOverlap,
        maxOverlap: maxOverlap,
        resizeMismatchedWidthsToFirst: resizeMismatchedWidthsToFirst,
        compressionQuality: compressionQuality
    )
    return result
}

private func assertStitchingThrows(
    _ imageData: [Data],
    minOverlap: Int = 20,
    expectedError: LocalImageStitchingError,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        _ = try stitchImages(imageData, minOverlap: minOverlap)
        XCTFail("Expected stitching to throw \(expectedError)", file: file, line: line)
    } catch let error as LocalImageStitchingError {
        XCTAssertEqual(error, expectedError, file: file, line: line)
    } catch {
        XCTFail("Expected \(expectedError), got \(error)", file: file, line: line)
    }
}

private func assertOverlaps(
    _ actual: [Int],
    _ expected: [Int],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual, expected, file: file, line: line)
}

private func outputCGImage(
    from result: LocalImageStitchResult,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> CGImage {
    let data: Data = result.jpegData
    let uiImage = try XCTUnwrap(UIImage(data: data), file: file, line: line)
    let cgImage = try XCTUnwrap(uiImage.cgImage, file: file, line: line)
    return cgImage
}

private func uniqueRows(count: Int) -> [TestRGB] {
    var result: [TestRGB] = []
    result.reserveCapacity(count)

    for index in 0..<count {
        let redValue = (index * 53 + 31) % 256
        let greenValue = (index * 97 + 17) % 256
        let blueValue = (index * 193 + 71) % 256
        let row = TestRGB(
            r: UInt8(redValue),
            g: UInt8(greenValue),
            b: UInt8(blueValue)
        )
        result.append(row)
    }

    return result
}

private func makeImageData(rows: [TestRGB], width: Int) throws -> Data {
    let image: CGImage = try makeCGImage(rows: rows, width: width)
    let uiImage: UIImage = UIImage(cgImage: image)
    let data: Data? = uiImage.pngData()
    return try XCTUnwrap(data)
}

private func makeOrientedImageData(rows: [TestRGB], width: Int, orientation: UIImage.Orientation) throws -> Data {
    let image: CGImage = try makeCGImage(rows: rows, width: width)
    let uiImage: UIImage = UIImage(cgImage: image, scale: 1, orientation: orientation)
    let data: Data? = uiImage.jpegData(compressionQuality: 1.0)
    return try XCTUnwrap(data)
}

private func makeCGImage(rows: [TestRGB], width: Int) throws -> CGImage {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(rows.count * width * 4)

    for row in rows {
        for _ in 0..<width {
            bytes.append(row.r)
            bytes.append(row.g)
            bytes.append(row.b)
            bytes.append(255)
        }
    }

    let colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
    let data: Data = Data(bytes)
    let provider: CGDataProvider = try XCTUnwrap(CGDataProvider(data: data as CFData))
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    let image: CGImage? = CGImage(
        width: width,
        height: rows.count,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
    return try XCTUnwrap(image)
}
