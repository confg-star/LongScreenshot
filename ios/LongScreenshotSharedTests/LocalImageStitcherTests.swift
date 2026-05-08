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
        let second = try makeImageData(rows: Array(repeating: white, count: 200), width: 4)

        let result = try LocalImageStitcher().stitchImageData(
            [first, second],
            minOverlap: 20,
            compressionQuality: 1.0
        )

        XCTAssertEqual(result.overlaps, [20])
        let outputImage = try XCTUnwrap(UIImage(data: result.jpegData)?.cgImage)
        XCTAssertEqual(outputImage.height, 380)
    }

    func testRejectsEmptyInput() {
        XCTAssertThrowsError(try LocalImageStitcher().stitchImageData([])) { error in
            XCTAssertEqual(error as? LocalImageStitchingError, .emptyImages)
        }
    }

    func testRejectsInvalidImageData() {
        XCTAssertThrowsError(try LocalImageStitcher().stitchImageData([Data([0x00, 0x01, 0x02])])) { error in
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

private func makeImageData(rows: [TestRGB], width: Int) throws -> Data {
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
    let image = try XCTUnwrap(CGImage(
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
    return try XCTUnwrap(UIImage(cgImage: image).pngData())
}
