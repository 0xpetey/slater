import CoreImage
import CoreMedia
import ScreenCaptureKit

/// Frames from one display, or one window, for live translation: at most `framesPerSecond` a
/// second, and only the newest one is kept, since a pass over a frame takes longer than a frame
/// interval. ScreenCaptureKit's own change reports aren't used; they flag the compositor's work,
/// which includes Slater's overlay, so `FrameDiff` compares the captured pixels instead.
final class ScreenStream: NSObject, SCStreamOutput, @unchecked Sendable {
    struct Frame: Sendable {
        let image: CGImage
        /// Pixels per point.
        let scale: CGFloat
    }

    let frames: AsyncStream<Frame>
    private let continuation: AsyncStream<Frame>.Continuation
    private let stream: SCStream
    private let configuration: SCStreamConfiguration
    private let context = CIContext()
    private let queue = DispatchQueue(label: "app.slater.live-frames")

    /// Slater's own windows (the overlay) are excluded so they aren't read back.
    convenience init(display: SCDisplay, excluding applications: [SCRunningApplication], framesPerSecond: Int) throws {
        try self.init(
            filter: SCContentFilter(display: display, excludingApplications: applications, exceptingWindows: []),
            framesPerSecond: framesPerSecond
        )
    }

    /// The window's own pixels, whatever is over it on screen, so the overlay needs no excluding.
    convenience init(window: SCWindow, framesPerSecond: Int) throws {
        try self.init(filter: SCContentFilter(desktopIndependentWindow: window), framesPerSecond: framesPerSecond)
    }

    private init(filter: SCContentFilter, framesPerSecond: Int) throws {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.queueDepth = 3
        // A window's frame is its bounds, with nothing around it, and keeps its scale: a window
        // that outgrows the frame is cropped, never shrunk, until `resize` catches up.
        configuration.ignoreShadowsSingleWindow = true
        configuration.scalesToFit = false
        self.configuration = configuration
        (frames, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        super.init()
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
    }

    func start() async throws {
        try await stream.startCapture()
    }

    /// Fits the frames to a window's new size.
    func resize(toPoints size: CGSize, scale: CGFloat) async {
        configuration.width = Int(size.width * scale)
        configuration.height = Int(size.height * scale)
        try? await stream.updateConfiguration(configuration)
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
