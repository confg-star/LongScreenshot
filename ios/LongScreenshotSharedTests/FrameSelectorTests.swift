import XCTest
@testable import LongScreenshotShared

final class FrameSelectorTests: XCTestCase {
    func testKeepsFirstUsableFrame() {
        var selector = FrameSelector(minimumSecondsBetweenFrames: 0.75, minimumMotionScore: 0.12, maximumBlurScore: 0.85)

        let decision = selector.evaluate(FrameSample(timestamp: 1.0, motionScore: 0.0, blurScore: 0.2))

        XCTAssertTrue(decision.keep)
        XCTAssertEqual(decision.reason, "first-frame")
    }

    func testRejectsBlurryFrame() {
        var selector = FrameSelector(minimumSecondsBetweenFrames: 0.75, minimumMotionScore: 0.12, maximumBlurScore: 0.85)
        _ = selector.evaluate(FrameSample(timestamp: 1.0, motionScore: 0.0, blurScore: 0.2))

        let decision = selector.evaluate(FrameSample(timestamp: 2.0, motionScore: 0.4, blurScore: 0.95))

        XCTAssertFalse(decision.keep)
        XCTAssertEqual(decision.reason, "too-blurry")
    }

    func testRejectsFrameTooSoonAfterLastKeptFrame() {
        var selector = FrameSelector(minimumSecondsBetweenFrames: 0.75, minimumMotionScore: 0.12, maximumBlurScore: 0.85)
        _ = selector.evaluate(FrameSample(timestamp: 1.0, motionScore: 0.0, blurScore: 0.2))

        let decision = selector.evaluate(FrameSample(timestamp: 1.2, motionScore: 0.4, blurScore: 0.2))

        XCTAssertFalse(decision.keep)
        XCTAssertEqual(decision.reason, "too-soon")
    }

    func testRejectsLowMotionFrameAfterFirstFrame() {
        var selector = FrameSelector(minimumSecondsBetweenFrames: 0.75, minimumMotionScore: 0.12, maximumBlurScore: 0.85)
        _ = selector.evaluate(FrameSample(timestamp: 1.0, motionScore: 0.0, blurScore: 0.2))

        let decision = selector.evaluate(FrameSample(timestamp: 2.0, motionScore: 0.03, blurScore: 0.2))

        XCTAssertFalse(decision.keep)
        XCTAssertEqual(decision.reason, "low-motion")
    }

    func testKeepsFrameWithEnoughTimeAndMotion() {
        var selector = FrameSelector(minimumSecondsBetweenFrames: 0.75, minimumMotionScore: 0.12, maximumBlurScore: 0.85)
        _ = selector.evaluate(FrameSample(timestamp: 1.0, motionScore: 0.0, blurScore: 0.2))

        let decision = selector.evaluate(FrameSample(timestamp: 2.0, motionScore: 0.24, blurScore: 0.2))

        XCTAssertTrue(decision.keep)
        XCTAssertEqual(decision.reason, "selected")
    }
}
