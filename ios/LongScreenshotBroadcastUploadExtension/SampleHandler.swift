import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
    private var videoFrameCount = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        videoFrameCount = 0
    }

    override func broadcastPaused() {}

    override func broadcastResumed() {}

    override func broadcastFinished() {
        videoFrameCount = 0
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            videoFrameCount += 1
        case .audioApp, .audioMic:
            break
        @unknown default:
            break
        }
    }
}
