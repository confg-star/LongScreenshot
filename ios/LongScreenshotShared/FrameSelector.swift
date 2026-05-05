import Foundation

public struct FrameSample: Equatable {
    public let timestamp: TimeInterval
    public let motionScore: Double
    public let blurScore: Double

    public init(timestamp: TimeInterval, motionScore: Double, blurScore: Double) {
        self.timestamp = timestamp
        self.motionScore = motionScore
        self.blurScore = blurScore
    }
}

public struct FrameDecision: Equatable {
    public let keep: Bool
    public let reason: String

    public init(keep: Bool, reason: String) {
        self.keep = keep
        self.reason = reason
    }
}

public struct FrameSelector {
    private let minimumSecondsBetweenFrames: TimeInterval
    private let minimumMotionScore: Double
    private let maximumBlurScore: Double
    private var lastKeptTimestamp: TimeInterval?

    public init(
        minimumSecondsBetweenFrames: TimeInterval = 0.75,
        minimumMotionScore: Double = 0.12,
        maximumBlurScore: Double = 0.85
    ) {
        self.minimumSecondsBetweenFrames = minimumSecondsBetweenFrames
        self.minimumMotionScore = minimumMotionScore
        self.maximumBlurScore = maximumBlurScore
        self.lastKeptTimestamp = nil
    }

    public mutating func evaluate(_ sample: FrameSample) -> FrameDecision {
        if sample.blurScore > maximumBlurScore {
            return FrameDecision(keep: false, reason: "too-blurry")
        }

        guard let lastKeptTimestamp else {
            self.lastKeptTimestamp = sample.timestamp
            return FrameDecision(keep: true, reason: "first-frame")
        }

        if sample.timestamp - lastKeptTimestamp < minimumSecondsBetweenFrames {
            return FrameDecision(keep: false, reason: "too-soon")
        }

        if sample.motionScore < minimumMotionScore {
            return FrameDecision(keep: false, reason: "low-motion")
        }

        self.lastKeptTimestamp = sample.timestamp
        return FrameDecision(keep: true, reason: "selected")
    }
}
