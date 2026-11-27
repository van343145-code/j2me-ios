//
//  DecadePiPManager.swift
//  J2MEEmulator
//
//  Picture-in-Picture (PiP) manager using AVSampleBufferDisplayLayer.
//  Provides ONLY the live resizable floating small game window outside the app
//  on the Home Screen and over other apps (drag anywhere + pinch to resize freely).
//  Bubble mode has been completely removed.
//

import UIKit
import AVKit
import AVFoundation
import CoreMedia
import VideoToolbox

final class DecadePiPManager: NSObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    static let shared = DecadePiPManager()

    private var pipController: AVPictureInPictureController?
    let displayLayer = AVSampleBufferDisplayLayer()
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

    func setupAudioSession() {
        // Ensure DecadeBackgroundKeeper's live .playback + .mixWithOthers session is active
        if DecadeBackgroundKeeper.shared.isAudioPlaying {
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[PiP] AudioSession error: \(error)")
        }
    }

    func setup(sourceView: UIView) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("[PiP] Picture in Picture is not supported on this device")
            return
        }

        self.sourceView = sourceView

        // Setup display layer
        displayLayer.videoGravity = .resizeAspect
        displayLayer.isOpaque = true
        displayLayer.frame = sourceView.bounds

        if displayLayer.superlayer == nil {
            sourceView.layer.addSublayer(displayLayer)
        }

        // Setup PiP Controller with ContentSource(sampleBufferDisplayLayer:playbackDelegate:)
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )

        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        // Keep inline auto-PiP off so normal NST invisible hide ("Ẩn ứng dụng") stays silent;
        // PiP opens cleanly on demand via "Cửa Sổ Nhỏ Ngoài Màn Hình".
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        controller.requiresLinearPlayback = true
        if controller.responds(to: Selector(("setControlsStyle:"))) {
            controller.setValue(1, forKey: "controlsStyle")
        }
        self.pipController = controller
        print("[PiP] Setup completed with AVSampleBufferDisplayLayer")
    }

    func updateLayout() {
        guard let sourceView = sourceView else { return }
        displayLayer.frame = sourceView.bounds
    }

    /// Starts the outside-app resizable PiP small window, priming AVSampleBufferDisplayLayer first
    /// so iOS immediately receives a live video frame before transitioning into PiP.
    func startPiP(initialFrame: CGImage? = nil) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            let err = NSError(domain: "DecadePiP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Thiết bị không hỗ trợ Hình trong hình (PiP)"])
            onPiPFailed?(err)
            return
        }
        guard let controller = pipController else {
            let err = NSError(domain: "DecadePiP", code: -2, userInfo: [NSLocalizedDescriptionKey: "PiP chưa được khởi tạo"])
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
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
            if self.displayLayer.status == .failed {
                self.displayLayer.flush()
            }
            if self.displayLayer.isReadyForMoreMediaData {
                self.displayLayer.enqueue(sampleBuffer)
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
        guard isPiPActiveOrStarting else { return }

        let now = CACurrentMediaTime()
        if hasEnqueuedInitialFrame {
            guard (now - lastFrameTime) >= 0.066 else { return } // ~15 FPS smooth & cool for PiP
        }
        lastFrameTime = now
        hasEnqueuedInitialFrame = true

        guard let sampleBuffer = createSampleBuffer(from: cgImage) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isPiPActiveOrStarting else { return }
            if self.displayLayer.status == .failed {
                self.displayLayer.flush()
            }
            if self.displayLayer.isReadyForMoreMediaData {
                self.displayLayer.enqueue(sampleBuffer)
            }
        }
    }

    func purgeBuffers() {
        guard !isPiPActiveOrStarting else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isPiPActiveOrStarting else { return }
            self.displayLayer.flush()
            self.pixelBufferPool = nil
            self.lastPoolSize = .zero
            self.hasEnqueuedInitialFrame = false
        }
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

        // Clear container background with clean black
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: targetW, height: targetH))

        // Draw crisp pixel-perfect live game frame
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

        // Display immediately so AVSampleBufferDisplayLayer never stalls waiting on controlTimebase
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
        // Always stay live small game window — bubble mode removed
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
        // User pinched/resized PiP window freely on Home Screen
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
        isPiPStarting = false
        purgeBuffers()
        onPiPStateChanged?(false)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        isPiPStarting = false
        print("[PiP] Failed: \(error.localizedDescription)")
        purgeBuffers()
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
