import CoreImage
import CoreMedia
import ScreenCaptureKit

/// Frames from one display, for live translation: at most `framesPerSecond` a second, and only
/// the newest one is kept, since a pass over a frame takes longer than a frame interval.
/// ScreenCaptureKit's own change reports aren't used; they flag the compositor's work, which
/// includes Slater's overlay, so `FrameDiff` compares the captured pixels instead.
final class ScreenStream: NSObject, SCStreamOutput, @unchecked Sendable {
    struct Frame: Sendable {
        let image: CGImage
        /// Pixels per point.
        let scale: CGFloat
    }

    let frames: AsyncStream<Frame>
    private let continuation: AsyncStream<Frame>.Continuation
    private let stream: SCStream
    private let context = CIContext()
    private let queue = DispatchQueue(label: "app.slater.live-frames")

    /// Slater's own windows (the overlay) are excluded so they aren't read back.
    init(display: SCDisplay, excluding applications: [SCRunningApplication], framesPerSecond: Int) throws {
        let filter = SCContentFilter(display: display, excludingApplications: applications, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.queueDepth = 3
        (frames, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        super.init()
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
    }

    func start() async throws {
        try await stream.startCapture()
    }

    func stop() async {
        try? await stream.stopCapture()
        continuation.finish()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let status = (info[.status] as? Int).flatMap(SCFrameStatus.init(rawValue:)), status == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer)
        guard let image = context.createCGImage(CIImage(cvPixelBuffer: pixelBuffer), from: CGRect(x: 0, y: 0, width: width, height: height)) else { return }

        let scale = (info[.scaleFactor] as? CGFloat) ?? 2
        continuation.yield(Frame(image: image, scale: scale))
    }
}
