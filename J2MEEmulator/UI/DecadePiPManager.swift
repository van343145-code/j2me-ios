//
//  DecadePiPManager.swift
//  J2MEEmulator
//
//  Created for Vạn Trần idol J2me NSV IOS
//  Picture-in-Picture (PiP) manager with AVSampleBufferDisplayLayer.
//  Enables live game video floating outside the app over Home Screen and other apps.
//  Supports dragging anywhere and pinch-to-resize freely ("kéo to nhỏ tuỳ ý ngoài màn hình").
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

    var isPiPActive: Bool {
        return pipController?.isPictureInPictureActive ?? false
    }

    var onPiPStateChanged: ((Bool) -> Void)?

    var gameName: String = "J2ME Game"
    var gameIcon: UIImage?
    var currentTab: Int = 1

    func setGameInfo(name: String, icon: UIImage?, tabNumber: Int) {
        self.gameName = name
        self.gameIcon = icon
        self.currentTab = tabNumber
    }

    private func getLogoCGImage(fallback: CGImage) -> CGImage {
        return gameIcon?.cgImage ?? fallback
    }

    override init() {
        super.init()
    }

    func setupAudioSession() {
        // Never disrupt DecadeBackgroundKeeper's live .playback + .mixWithOthers session!
        if DecadeBackgroundKeeper.shared.isAudioPlaying {
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
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
        // CRITICAL: Keep inline auto-PiP OFF so backgrounding / HideApp ("suspend")
        // never triggers empty-layer media arbitration that interrupts BackgroundAudio!
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

    func startPiP() {
        setupAudioSession()
        guard let controller = pipController else {
            print("[PiP] Controller is nil")
            return
        }
        if !controller.isPictureInPictureActive {
            controller.startPictureInPicture()
        }
    }

    func stopPiP() {
        if let controller = pipController, controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        }
    }

    func togglePiP() {
        if isPiPActive {
            stopPiP()
        } else {
            startPiP()
        }
    }

    // MARK: - Frame Enqueueing
    func updateFrame(_ cgImage: CGImage) {
        // CRITICAL: Never allocate CVPixelBuffer/IOSurface/CMSampleBuffer when PiP is NOT active!
        // Previously running 30fps while PiP was off leaked ~65 MB/s of IOSurface memory.
        guard isPiPActive else { return }

        let now = CACurrentMediaTime()
        if hasEnqueuedInitialFrame {
            guard (now - lastFrameTime) >= 0.05 else { return } // 20 FPS max for PiP
        }
        lastFrameTime = now
        hasEnqueuedInitialFrame = true

        guard let sampleBuffer = createSampleBuffer(from: cgImage) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isPiPActive else { return }
            if self.displayLayer.status == .failed {
                self.displayLayer.flush()
            }
            if self.displayLayer.isReadyForMoreMediaData {
                self.displayLayer.enqueue(sampleBuffer)
            }
        }
    }

    func purgeBuffers() {
        guard !isPiPActive else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isPiPActive else { return }
            self.displayLayer.flush()
            self.pixelBufferPool = nil
            self.lastPoolSize = .zero
            self.hasEnqueuedInitialFrame = false
        }
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

        // Portrait 3:4 video (240x320) is severely restricted by iOS PiP size limits.
        // Expanding the container to 4:3 landscape ratio allows iOS PiP to expand
        // to the FULL WIDTH of the iPhone screen, unlocking free multi-size resizing!
        let targetW: Int
        let targetH: Int
        let drawX: Int
        let drawY: Int

        if isBubbleMode {
            // 1:1 Compact Bubble Aspect Ratio: shrinks the entire PiP window into a tight bubble!
            targetW = 160
            targetH = 160
            drawX = 0
            drawY = 0
        } else {
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

        if isBubbleMode {
            // Fill background with clean black
            context.setFillColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 160))

            let centerX: CGFloat = 80.0
            let centerY: CGFloat = 80.0
            let bubbleRadius: CGFloat = 72.0

            // Glowing cyan outer ring
            context.setStrokeColor(red: 0.13, green: 0.59, blue: 0.95, alpha: 0.45)
            context.setLineWidth(8.0)
            context.strokeEllipse(in: CGRect(x: centerX - bubbleRadius, y: centerY - bubbleRadius, width: bubbleRadius * 2, height: bubbleRadius * 2))

            // Main cyan ring
            context.setStrokeColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 1.0)
            context.setLineWidth(4.0)
            context.strokeEllipse(in: CGRect(x: centerX - bubbleRadius, y: centerY - bubbleRadius, width: bubbleRadius * 2, height: bubbleRadius * 2))

            // Dark inner circle base
            context.setFillColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1.0)
            context.fillEllipse(in: CGRect(x: centerX - bubbleRadius + 2.0, y: centerY - bubbleRadius + 2.0, width: (bubbleRadius - 2.0) * 2, height: (bubbleRadius - 2.0) * 2))

            // Draw game logo in the center of the bubble!
            let logoImage = getLogoCGImage(fallback: cgImage)
            let logoRadius: CGFloat = 52.0
            context.saveGState()
            context.addEllipse(in: CGRect(x: centerX - logoRadius, y: centerY - logoRadius, width: logoRadius * 2, height: logoRadius * 2))
            context.clip()

            context.interpolationQuality = .high
            context.draw(logoImage, in: CGRect(x: centerX - logoRadius, y: centerY - logoRadius, width: logoRadius * 2, height: logoRadius * 2))
            context.restoreGState()

            // Red badge with tab indicator in the corner
            let badgeX: CGFloat = 114.0
            let badgeY: CGFloat = 114.0
            let badgeRadius: CGFloat = 16.0
            context.setFillColor(red: 0.90, green: 0.22, blue: 0.21, alpha: 1.0)
            context.fillEllipse(in: CGRect(x: badgeX - badgeRadius, y: badgeY - badgeRadius, width: badgeRadius * 2, height: badgeRadius * 2))
            context.setStrokeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            context.setLineWidth(2.0)
            context.strokeEllipse(in: CGRect(x: badgeX - badgeRadius, y: badgeY - badgeRadius, width: badgeRadius * 2, height: badgeRadius * 2))
        } else {
            // Clear container background with clean black
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: targetW, height: targetH))

            // Draw game frame centered and pixel-perfect
            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: drawX, y: drawY, width: origW, height: origH))
        }

        var formatDesc: CMVideoFormatDescription?
        let vStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescriptionOut: &formatDesc
        )
        guard vStatus == noErr, let format = formatDesc else { return nil }

        let now = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
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
        guard sStatus == noErr else { return nil }
        return sampleBuffer
    }

    // MARK: - AVPictureInPictureSampleBufferPlaybackDelegate
    var isBubbleMode: Bool = false {
        didSet {
            displayLayer.flush()
        }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        isBubbleMode.toggle()
        print("[PiP] Toggled bubble mode via center button: \(isBubbleMode)")
    }

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        // Infinite duration prevents loading indicator on game stream
        return CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        return isBubbleMode
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
        // Called when user pinches/resizes PiP window on home screen
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        isBubbleMode.toggle()
        completionHandler()
    }

    // MARK: - AVPictureInPictureControllerDelegate
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        onPiPStateChanged?(true)
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        onPiPStateChanged?(true)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        purgeBuffers()
        onPiPStateChanged?(false)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("[PiP] Failed: \(error.localizedDescription)")
        onPiPStateChanged?(false)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}
