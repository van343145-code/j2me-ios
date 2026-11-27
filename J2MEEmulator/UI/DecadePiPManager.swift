//
//  DecadePiPManager.swift
//  J2MEEmulator
//
//  LAZY & EPHEMERAL Picture-in-Picture (PiP) manager using AVSampleBufferDisplayLayer.
//  Provides ONLY the live resizable floating small game window outside the app
//  on the Home Screen and over other apps (drag anywhere + pinch to resize freely).
//  Bubble mode has been completely removed.
//
//  CRITICAL FOR 24/24 LOCK-SCREEN BACKGROUND EXECUTION (matching J2ME NST):
//  - NEVER instantiates AVSampleBufferDisplayLayer or AVPictureInPictureController
//    at launch or in viewDidLoad()!
//  - Creates them strictly on demand when the user taps "Cửa Sổ Nhỏ Ngoài Màn Hình",
//    and completely tears them down when PiP stops/fails so iOS video/PiP media session
//    management NEVER interferes with pure audio-only background execution on screen lock!
//

import UIKit
import AVKit
import AVFoundation
import CoreMedia
import VideoToolbox

final class DecadePiPManager: NSObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    static let shared = DecadePiPManager()

    private var pipController: AVPictureInPictureController?
    private var displayLayer: AVSampleBufferDisplayLayer?
    private weak var sourceView: UIView?

    private var pixelBufferPool: CVPixelBufferPool?
    private var lastPoolSize: CGSize = .zero
    private var lastFrameTime: CFTimeInterval = 0
    private var hasEnqueuedInitialFrame = false
    private(set) var isPiPStarting = false

    var isPiPActive: Bool {
        return pipController?.isPictureInPictureActive ?? false
    }

    var isPiPActiveOrStarting: Bool {
        return isPiPActive || isPiPStarting
    }

    var onPiPStateChanged: ((Bool) -> Void)?
    var onPiPFailed: ((Error) -> Void)?

    var gameName: String = "jarNO1"
    var gameIcon: UIImage?
    var currentTab: Int = 1

    func setGameInfo(name: String, icon: UIImage?, tabNumber: Int) {
        self.gameName = name
        self.gameIcon = icon
        self.currentTab = tabNumber
    }

    override init() {
        super.init()
    }

    /// Registers the host view WITHOUT creating AVSampleBufferDisplayLayer or AVPictureInPictureController.
    /// Keeps the process 100% pure audio-only (matching J2ME NST) until the user explicitly opens PiP.
    func setup(sourceView: UIView) {
        self.sourceView = sourceView
    }

    private func setupAudioSession() {
        // Ensure DecadeBackgroundKeeper's live .playback + .mixWithOthers session is active
        if DecadeBackgroundKeeper.shared.isAudioPlaying {
            return
        }
        DecadeBackgroundKeeper.shared.startKeepalive()
    }

    private func ensurePipelineCreated() -> AVPictureInPictureController? {
        if let existing = pipController, displayLayer != nil {
            if let host = sourceView {
                displayLayer?.frame = host.bounds
                if displayLayer?.superlayer == nil {
                    host.layer.addSublayer(displayLayer!)
                }
            }
            return existing
        }

        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let host = sourceView else {
            return nil
        }

        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resizeAspect
        layer.isOpaque = true
        layer.frame = host.bounds
        host.layer.addSublayer(layer)
        self.displayLayer = layer

        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: layer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        // Keep inline auto-PiP off so normal NST invisible hide ("Ẩn ứng dụng") & screen lock stay silent.
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        controller.requiresLinearPlayback = true
        if controller.responds(to: Selector(("setControlsStyle:"))) {
            controller.setValue(1, forKey: "controlsStyle")
        }
        self.pipController = controller
        print("[PiP] Lazily created AVPictureInPictureController on demand")
        return controller
    }

    /// Completely tears down AVPictureInPictureController & AVSampleBufferDisplayLayer when PiP closes,
    /// leaving zero active video/Pegasus sessions to interfere with screen-lock audio keep-alive.
    func teardownPipeline() {
        let work = {
            self.isPiPStarting = false
            self.pipController?.delegate = nil
            self.pipController = nil
            self.displayLayer?.flushAndRemoveImage()
            self.displayLayer?.removeFromSuperlayer()
            self.displayLayer = nil
            self.pixelBufferPool = nil
            self.lastPoolSize = .zero
            self.hasEnqueuedInitialFrame = false
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func updateLayout() {
        guard let sourceView = sourceView, let layer = displayLayer else { return }
        layer.frame = sourceView.bounds
    }

    /// Starts the outside-app resizable PiP small window, lazily creating & priming AVSampleBufferDisplayLayer
    /// so iOS immediately receives a live video frame before transitioning into PiP.
    func startPiP(initialFrame: CGImage? = nil) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            let err = NSError(domain: "DecadePiP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Thiết bị không hỗ trợ Hình trong hình (PiP)"])
            onPiPFailed?(err)
            return
        }
        guard let controller = ensurePipelineCreated() else {
            let err = NSError(domain: "DecadePiP", code: -2, userInfo: [NSLocalizedDescriptionKey: "PiP chưa sẵn sàng"])
            onPiPFailed?(err)
            return
        }
        if controller.isPictureInPictureActive {
            onPiPStateChanged?(true)
            return
        }

        setupAudioSession()
        isPiPStarting = true
        j2me_render_set_background(0)

        // Prime displayLayer synchronously with a valid sample buffer before calling startPictureInPicture()
        if let frame = initialFrame {
            enqueueFrameSynchronously(frame)
        } else if let fallback = makeBlackFallbackImage() {
            enqueueFrameSynchronously(fallback)
        }
        controller.invalidatePlaybackState()

        // Allow one CoreAnimation commit tick so AVSampleBufferDisplayLayer registers the primed frame
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self = self, let ctrl = self.pipController, self.isPiPStarting else { return }
            if !ctrl.isPictureInPictureActive {
                ctrl.startPictureInPicture()
            }
        }
    }

    func stopPiP() {
        isPiPStarting = false
        if let controller = pipController, controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            teardownPipeline()
        }
    }

    func togglePiP(initialFrame: CGImage? = nil) {
        if isPiPActive {
            stopPiP()
        } else {
            startPiP(initialFrame: initialFrame)
        }
    }

    // MARK: - Frame Enqueueing

    private func enqueueFrameSynchronously(_ cgImage: CGImage) {
        guard let sampleBuffer = createSampleBuffer(from: cgImage) else { return }
        let work = {
            guard let layer = self.displayLayer else { return }
            if layer.status == .failed {
                layer.flush()
            }
            if layer.isReadyForMoreMediaData {
                layer.enqueue(sampleBuffer)
                self.hasEnqueuedInitialFrame = true
                self.lastFrameTime = CACurrentMediaTime()
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    func updateFrame(_ cgImage: CGImage) {
        // Never allocate CVPixelBuffer/IOSurface when PiP is completely off
        guard isPiPActiveOrStarting, displayLayer != nil else { return }

        let now = CACurrentMediaTime()
        if hasEnqueuedInitialFrame {
            guard (now - lastFrameTime) >= 0.066 else { return } // ~15 FPS smooth & cool for PiP
        }
        lastFrameTime = now
        hasEnqueuedInitialFrame = true

        guard let sampleBuffer = createSampleBuffer(from: cgImage) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isPiPActiveOrStarting, let layer = self.displayLayer else { return }
            if layer.status == .failed {
                layer.flush()
            }
            if layer.isReadyForMoreMediaData {
                layer.enqueue(sampleBuffer)
            }
        }
    }

    func purgeBuffers() {
        guard !isPiPActiveOrStarting else { return }
        guard displayLayer != nil || pixelBufferPool != nil else { return }
        teardownPipeline()
    }

    private func makeBlackFallbackImage() -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: 320,
            height: 240,
            bitsPerComponent: 8,
            bytesPerRow: 320 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
        return ctx.makeImage()
    }

    private func getPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let currentSize = CGSize(width: width, height: height)
        if pixelBufferPool == nil || lastPoolSize != currentSize {
            pixelBufferPool = nil
            lastPoolSize = currentSize

            let poolAttrs: [CFString: Any] = [
                kCVPixelBufferPoolMinimumBufferCountKey: 3
            ]
            let bufferAttrs: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ]
            CVPixelBufferPoolCreate(
                kCFAllocatorDefault,
                poolAttrs as CFDictionary,
                bufferAttrs as CFDictionary,
                &pixelBufferPool
            )
        }

        guard let pool = pixelBufferPool else { return nil }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        guard status == kCVReturnSuccess else { return nil }
        return pixelBuffer
    }

    private func createSampleBuffer(from cgImage: CGImage) -> CMSampleBuffer? {
        let origW = cgImage.width
        let origH = cgImage.height

        // Portrait 3:4 video (e.g. 240x320) is tightly capped by iOS PiP size limits.
        // Expanding the container to 4:3 landscape unlocks FULL free pinch-to-resize
        // from tiny corner window up to full iPhone screen width outside on the Home Screen!
        let targetW: Int
        let targetH: Int
        let drawX: Int
        let drawY: Int

        if origW < origH {
            targetH = origH
            targetW = max(origW, (origH * 4) / 3)
            drawX = (targetW - origW) / 2
            drawY = 0
        } else {
            targetW = origW
            targetH = origH
            drawX = 0
            drawY = 0
        }

        guard let buffer = getPixelBuffer(width: targetW, height: targetH) else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: baseAddress,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: targetW, height: targetH))

        context.interpolationQuality = .none
        context.draw(cgImage, in: CGRect(x: drawX, y: drawY, width: origW, height: origH))

        var formatDesc: CMVideoFormatDescription?
        let vStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescriptionOut: &formatDesc
        )
        guard vStatus == noErr, let format = formatDesc else { return nil }

        let now = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 15),
            presentationTimeStamp: now,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let sStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard sStatus == noErr, let sb = sampleBuffer else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true) {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        return sb
    }

    // MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        pictureInPictureController.invalidatePlaybackState()
    }

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        return CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        return false
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    // MARK: - AVPictureInPictureControllerDelegate

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPStarting = true
        j2me_render_set_background(0)
        j2me_input_post_repaint()
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPStarting = false
        j2me_render_set_background(0)
        j2me_input_post_repaint()
        onPiPStateChanged?(true)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        teardownPipeline()
        onPiPStateChanged?(false)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("[PiP] Failed: \(error.localizedDescription)")
        teardownPipeline()
        onPiPFailed?(error)
        onPiPStateChanged?(false)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}
