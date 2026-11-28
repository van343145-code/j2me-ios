//
//  DecadeBackgroundKeeper.swift
//  J2MEEmulator
//
//  Background audio keepalive manager (App + Scene lifecycle):
//  - Pure AVAudioPlayer playing `background-loop.wav` with
//    `numberOfLoops = -1`, non-zero inaudible gain `volume = 0.002` (~-80 dBFS),
//    `prepareToPlay()`, `play()`.
//  - ZERO AVAudioEngine / AVAudioSourceNode (avoids lock-screen AVAudioEngineConfigurationChange
//    teardown & background AVAudioSession reactivation failures on iOS 18/26).
//  - ZERO eager AVPictureInPictureController / AVSampleBufferDisplayLayer at startup.
//  - Uses `AVAudioSession.setCategory(.playback, mode: .default, options: ...)` + `setActive(true)`.
//  - Includes 2.0-second repeating RunLoop monitor + 20.0-second `beginBackgroundTask` handoff
//    plus background anti-Wi-Fi-sleep keepalive probes via `DecadeNetworkKeeper`.
//  - Permanently remembers `isTreoActive` (default TRUE) after enabling / tapping "Ẩn Ứng Dụng"
//    once, so every future multitasking swipe or screen lock automatically stays running 24/24.
//  - Includes passive background execution proof telemetry for on-device verification.
//

import UIKit
import AVFoundation
import UserNotifications
import Network

// ============================================================
// MARK: - Decade Location Keeper (Disabled)
// ============================================================

final class DecadeLocationKeeper: NSObject {
    static let shared = DecadeLocationKeeper()

    private(set) var isRunning = false

    var isLocationModeActive: Bool {
        get { false }
        set {
            UserDefaults.standard.set(false, forKey: "decade_use_location_keepalive")
            isRunning = false
        }
    }

    func requestPermissionIfNeeded() { }
    func start() { isRunning = false }
    func stop() { isRunning = false }
}

// ============================================================
// MARK: - Decade Network Keeper (Passive Stub — 1:1 J2ME NST)
// ============================================================

final class DecadeNetworkKeeper {
    static let shared = DecadeNetworkKeeper()

    private(set) var isRunning = false
    private(set) var isInBackground = false
    private(set) var isNetworkConnected = true

    private init() { }

    func start() { isRunning = true }
    func stop() { isRunning = false; isInBackground = false }
    func setBackgroundActive(_ active: Bool) { isInBackground = active }
}

// ============================================================
// MARK: - DecadeBackgroundKeeper (24/24 Background Audio Engine)
// ============================================================

final class DecadeBackgroundKeeper: NSObject, AVAudioPlayerDelegate {
    static let shared = DecadeBackgroundKeeper()

    /// Notification posted on foreground return after >= 8s in background so UI displays proof toast.
    static let backgroundResumeReportNotification = Notification.Name("DecadeBackgroundResumeReport")

    /// Defaults to TRUE on fresh install & permanently remembers preference across launches.
    private static let stickyOffKey = "jarno1_treo_247_v7_off"

    /// Optional Exclusive `.playback` mode (OFF by default = `.mixWithOthers`).
    private static let exclusiveAudioKey = "jarno1_exclusive_audio_mode"
    private static let mixAudioMigratedV19Key = "jarno1_mix_audio_migrated_v19"

    // Background audio player & monitor state
    private var audioPlayer: AVAudioPlayer?
    private var monitorTimer: Timer?
    private var bgTaskHandoffTimer: Timer?
    private var ramCleanTimer: DispatchSourceTimer?
    private var currentGameName: String = "jarNO1"
    private var bgTaskID: UIBackgroundTaskIdentifier = .invalid

    private var wanted = false
    private var interrupted = false
    private var interruptedAt: Date?
    private var isInBackground = false
    private var lastBgHandoffTime: CFTimeInterval = 0

    // Persistent Flight Recorder keys (survive SIGKILL / Jetsam / watchdog termination)
    private static let recActiveKey = "jarno1_bg_rec_active"
    private static let recStartKey = "jarno1_bg_rec_start"
    private static let recAliveKey = "jarno1_bg_rec_alive"
    private static let recRamKey = "jarno1_bg_rec_ram"
    private static let recCpuKey = "jarno1_bg_rec_cpu"
    private static let recAudioKey = "jarno1_bg_rec_audio"
    private static let recLastReportKey = "jarno1_bg_rec_last_report"

    // Passive on-device background execution proof telemetry
    private var bgEnterDate: Date?
    private var bgLastHeartbeatElapsed: Int = 0
    private var bgLastDiskSyncElapsed: Int = -60
    private var bgLastSavedWaitDiag: String = ""
    private(set) var lastBgWallSeconds: Int = 0
    private(set) var lastBgAliveSeconds: Int = 0
    private(set) var lastBgReport: String = "Chưa ẩn/tắt màn lần nào"
    private(set) var lastKilledPostMortem: String?
    private(set) var audioStatus: String = "stopped"
    private(set) var lastAudioError: String = ""

    var isAudioPlaying: Bool {
        return audioPlayer?.isPlaying == true
    }

    var isFullyActive: Bool {
        return isAudioPlaying
    }

    private var hasActiveGame: Bool {
        guard let vc = GameViewController.currentActiveGameVC else { return false }
        return !vc.isShuttingDown
    }

    var isTreoActive: Bool {
        get {
            return !UserDefaults.standard.bool(forKey: Self.stickyOffKey)
        }
        set {
            setTreoActive(newValue)
        }
    }

    var isExclusiveAudioMode: Bool {
        get { false }
        set { }
    }

    var audioModeDescription: String {
        return "Audio Nền 24/24 (Mix app khác)"
    }

    var isAutoCleanRamActive: Bool {
        get {
            if UserDefaults.standard.object(forKey: "decade_auto_clean_ram") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "decade_auto_clean_ram")
        }
        set {
            setAutoCleanRamActive(newValue)
        }
    }

    private override init() {
        super.init()
        // One-time v1.0.19 migration: reset legacy "exclusive" toggle to Mixable (.mixWithOthers)
        // because iOS 26 audiomxd interrupts [NonMixable] sessions when YouTube/TikTok/Facebook play
        // and rejects background reactivation with -12985 (Operation denied. Cannot interrupt others).
        let d = UserDefaults.standard
        if !d.bool(forKey: Self.mixAudioMigratedV19Key) {
            d.set(false, forKey: Self.exclusiveAudioKey)
            d.set(true, forKey: Self.mixAudioMigratedV19Key)
            d.synchronize()
        }
        loadPreviousFlightRecord()
        setupNotifications()
        if isAutoCleanRamActive {
            startAutoRamCleaner()
        }
    }

    private func loadPreviousFlightRecord() {
        let d = UserDefaults.standard
        if d.bool(forKey: Self.recActiveKey) {
            let alive = d.integer(forKey: Self.recAliveKey)
            let ram = d.integer(forKey: Self.recRamKey)
            let cpu = d.integer(forKey: Self.recCpuKey)
            let audio = d.string(forKey: Self.recAudioKey) ?? "unknown"
            let summary = "⚠️ Phiên trước bị iOS dừng lúc \(alive)s (RAM \(ram)MB, CPU \(cpu)%, \(audio))"
            lastKilledPostMortem = "Dừng lúc \(alive)s (\(ram)MB • \(cpu)%)"
            lastBgReport = summary
            d.set(false, forKey: Self.recActiveKey)
            d.set(summary, forKey: Self.recLastReportKey)
            d.synchronize()
        } else if let saved = d.string(forKey: Self.recLastReportKey), !saved.isEmpty {
            lastBgReport = saved
        }
    }

    private func runOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    /// Audio session & interruption observers
    private func setupNotifications() {
        let nc = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        nc.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: session
        )
        nc.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: session
        )
        nc.addObserver(
            self,
            selector: #selector(handleMediaServicesLost),
            name: AVAudioSession.mediaServicesWereLostNotification,
            object: session
        )
        nc.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: session
        )
        nc.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        // Standard UIApplication background/foreground fallback (coalesced with SceneDelegate)
        nc.addObserver(
            self,
            selector: #selector(onSceneDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(onSceneWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    func updateNowPlayingGame(name: String) {
        currentGameName = name.isEmpty ? "jarNO1" : name
    }

    func setTreoActive(_ active: Bool) {
        UserDefaults.standard.set(!active, forKey: Self.stickyOffKey)
        UserDefaults.standard.synchronize()
        runOnMain { [weak self] in
            guard let self = self else { return }
            if active {
                if self.hasActiveGame {
                    self.startKeepalive()
                    UIApplication.shared.isIdleTimerDisabled = true
                }
            } else {
                self.stopKeepalive()
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    func setExclusiveAudioMode(_ exclusive: Bool) {
        let changed = (UserDefaults.standard.bool(forKey: Self.exclusiveAudioKey) != exclusive)
        UserDefaults.standard.set(exclusive, forKey: Self.exclusiveAudioKey)
        UserDefaults.standard.synchronize()
        guard changed else { return }
        runOnMain { [weak self] in
            guard let self = self, self.wanted else { return }
            self.audioPlayer?.stop()
            self.audioPlayer = nil
            self.interrupted = false
            self.interruptedAt = nil
            self.ensurePlaying()
        }
    }

    func setAutoCleanRamActive(_ active: Bool) {
        UserDefaults.standard.set(active, forKey: "decade_auto_clean_ram")
        if active {
            startAutoRamCleaner()
        } else {
            stopAutoRamCleaner()
        }
    }

    @objc private func handleMemoryWarning() {
        URLCache.shared.removeAllCachedResponses()
        GameViewController.purgeInactiveSlotFrames()
        DecadePiPManager.shared.purgeBuffers()
        DispatchQueue.global(qos: .utility).async {
            jvm_bridge_clean_ram()
        }
    }

    func performRamCleanup(completion: ((Double, Double) -> Void)? = nil) {
        let beforeMB = Double(jvm_bridge_get_used_ram_kb()) / 1024.0
        let thresholdMB: Double = isInBackground ? 80.0 : 140.0
        guard completion != nil || beforeMB > thresholdMB else { return }

        URLCache.shared.removeAllCachedResponses()
        GameViewController.purgeInactiveSlotFrames()
        DecadePiPManager.shared.purgeBuffers()

        DispatchQueue.global(qos: .utility).async {
            jvm_bridge_clean_ram()
            let afterMB = Double(jvm_bridge_get_used_ram_kb()) / 1024.0
            if let cb = completion {
                DispatchQueue.main.async {
                    cb(beforeMB, afterMB)
                }
            }
        }
    }

    private func startAutoRamCleaner() {
        guard ramCleanTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 45.0, repeating: 45.0)
        timer.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.isAutoCleanRamActive else { return }
                self.performRamCleanup(completion: nil)
            }
        }
        timer.resume()
        ramCleanTimer = timer
    }

    private func stopAutoRamCleaner() {
        ramCleanTimer?.cancel()
        ramCleanTimer = nil
    }

    // MARK: - BackgroundAudio Core (Start / Stop / Foreground / EnsurePlaying)

    func startKeepalive() {
        runOnMain { [weak self] in
            guard let self = self else { return }
            self.wanted = true
            self.interrupted = false
            self.interruptedAt = nil
            DecadeNetworkKeeper.shared.start()
            self.startMonitorIfNeeded()
            self.ensurePlaying()
        }
    }

    func stopKeepalive() {
        runOnMain { [weak self] in
            guard let self = self else { return }
            self.wanted = false
            self.interrupted = false
            self.interruptedAt = nil
            self.monitorTimer?.invalidate()
            self.monitorTimer = nil
            self.bgEnterDate = nil
            self.bgLastHeartbeatElapsed = 0
            UserDefaults.standard.set(false, forKey: Self.recActiveKey)
            self.audioPlayer?.stop()
            self.audioPlayer = nil
            self.audioStatus = "stopped"
            self.lastAudioError = ""
            DecadeNetworkKeeper.shared.stop()
            self.endAppBackgroundTask()
            self.clearLockScreenNotification()
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    /// 5.0-second repeating monitor timer (exact 1:1 J2ME NST BackgroundAudio)
    private func startMonitorIfNeeded() {
        guard monitorTimer == nil else { return }
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, self.wanted else { return }
            if self.interrupted {
                if let at = self.interruptedAt, Date().timeIntervalSince(at) >= 3.0 {
                    self.interrupted = false
                    self.interruptedAt = nil
                    self.ensurePlaying()
                }
            } else if self.audioPlayer?.isPlaying != true {
                self.ensurePlaying()
            }

            if self.isInBackground, let entered = self.bgEnterDate {
                let elapsed = max(0, Int(Date().timeIntervalSince(entered)))
                self.bgLastHeartbeatElapsed = elapsed
                self.recordBackgroundSnapshot(aliveSec: elapsed, active: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer
    }

    /// Exact 1:1 J2ME NST BackgroundAudio.EnsurePlaying():
    /// 1. If `audioPlayer.isPlaying` is already true -> immediately return WITHOUT touching AVAudioSession.
    /// 2. Single audio mode: `AVAudioSession.setCategory(.playback, options: [.mixWithOthers])` + `setActive(true)`.
    /// 3. Load `background-loop.wav` (22050 Hz mono, 8.00s, -35.35 dBFS), `numberOfLoops = -1`, `volume = 0.0`, `prepareToPlay()`, `play()`.
    private func ensurePlaying(forceMixable: Bool = false) {
        guard wanted, !interrupted else { return }

        if let p = audioPlayer, p.isPlaying {
            audioStatus = "playing"
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            let nsErr = error as NSError
            lastAudioError = "sess(\(nsErr.code)): \(nsErr.localizedDescription)"
            audioStatus = "error(\(nsErr.code))"
            print("[BackgroundAudio] AVAudioSession error: \(error)")
            return
        }

        if audioPlayer == nil {
            let wavURL = Bundle.main.url(forResource: "background-loop", withExtension: "wav")
                ?? Bundle.main.url(forResource: "silent", withExtension: "wav")
            guard let url = wavURL else {
                lastAudioError = "missing background-loop.wav"
                audioStatus = "error(no-wav)"
                print("[BackgroundAudio] Missing background-loop.wav in bundle")
                return
            }
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                p.delegate = self
                p.numberOfLoops = -1
                p.volume = 0.0
                audioPlayer = p
            } catch {
                let nsErr = error as NSError
                lastAudioError = "player(\(nsErr.code)): \(nsErr.localizedDescription)"
                audioStatus = "error(\(nsErr.code))"
                print("[BackgroundAudio] AVAudioPlayer init error: \(error)")
                return
            }
        }

        guard let p = audioPlayer else { return }
        guard p.prepareToPlay(), p.play() else {
            lastAudioError = "Play() trả false"
            audioStatus = "play-false"
            print("[BackgroundAudio] AVAudioPlayer.play() returned false")
            return
        }
        lastAudioError = ""
        audioStatus = "playing"
    }

    // MARK: - Passive Background Execution Proof Telemetry & Flight Recorder

    private func startBackgroundRecordingIfNeeded() {
        guard hasActiveGame, bgEnterDate == nil else { return }
        bgEnterDate = Date()
        bgLastHeartbeatElapsed = 0
        bgLastDiskSyncElapsed = 0
        bgLastSavedWaitDiag = ""
        recordBackgroundSnapshot(aliveSec: 0, active: true, forceSync: true)
    }

    var lastWaitDiag: String {
        var buf = [CChar](repeating: 0, count: 128)
        jvm_bridge_copy_wait_diag(&buf, Int32(buf.count))
        return String(cString: buf)
    }

    private func recordBackgroundSnapshot(aliveSec: Int, active: Bool, forceSync: Bool = false) {
        let waitDiag = lastWaitDiag
        let newDiag = !waitDiag.isEmpty && waitDiag != bgLastSavedWaitDiag
        let cpuPct = Int(min(999.0, max(0.0, jvm_bridge_get_cpu_usage_percent())).rounded())
        let duePeriodicFlush = (aliveSec - bgLastDiskSyncElapsed) >= 60
        guard forceSync || duePeriodicFlush || newDiag || cpuPct >= 50 else {
            return
        }

        bgLastDiskSyncElapsed = aliveSec
        if !waitDiag.isEmpty {
            bgLastSavedWaitDiag = waitDiag
        }

        let d = UserDefaults.standard
        let ramMB = Int((Double(jvm_bridge_get_used_ram_kb()) / 1024.0).rounded())
        let audioInfo = "\(isAudioPlaying ? "playing" : audioStatus)" + (waitDiag.isEmpty ? "" : " • \(waitDiag)")
        d.set(active, forKey: Self.recActiveKey)
        if let entered = bgEnterDate {
            d.set(entered.timeIntervalSince1970, forKey: Self.recStartKey)
        }
        d.set(aliveSec, forKey: Self.recAliveKey)
        d.set(ramMB, forKey: Self.recRamKey)
        d.set(cpuPct, forKey: Self.recCpuKey)
        d.set(audioInfo, forKey: Self.recAudioKey)
        d.synchronize()
    }

    private func finalizeBackgroundTelemetryIfNeeded() {
        guard let entered = bgEnterDate else { return }
        bgEnterDate = nil

        let wall = max(0, Int(Date().timeIntervalSince(entered).rounded()))
        let alive = min(wall, bgLastHeartbeatElapsed)
        UserDefaults.standard.set(false, forKey: Self.recActiveKey)
        guard wall >= 3 else {
            UserDefaults.standard.synchronize()
            return
        }

        lastBgWallSeconds = wall
        lastBgAliveSeconds = alive
        lastKilledPostMortem = nil

        if !isTreoActive {
            lastBgReport = "Treo 24/24 đang TẮT (\(alive)/\(wall)s)"
        } else if wall < 8 || alive >= max(2, Int(Double(wall) * 0.65)) {
            lastBgReport = "✓ Chạy nền xuyên suốt \(max(alive, min(wall, 5)))/\(wall)s (Audio OK)"
        } else {
            let detail = lastAudioError.isEmpty ? audioStatus : lastAudioError
            lastBgReport = "⚠️ Bị iOS dừng nền: \(alive)/\(wall)s (\(detail))"
        }
        UserDefaults.standard.set(lastBgReport, forKey: Self.recLastReportKey)
        UserDefaults.standard.synchronize()

        if wall >= 8 && hasActiveGame {
            NotificationCenter.default.post(
                name: Self.backgroundResumeReportNotification,
                object: nil,
                userInfo: ["message": lastBgReport]
            )
        }
    }

    // MARK: - Background Transition 20.0s Handoff

    private func beginBackgroundHandoffTask() {
        let now = CACurrentMediaTime()
        if bgTaskID != .invalid && (now - lastBgHandoffTime) < 0.5 {
            return
        }
        lastBgHandoffTime = now

        endAppBackgroundTask()
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "jarNO1-BgHandoff") { [weak self] in
            guard let self = self else { return }
            self.endAppBackgroundTask()
            if self.wanted && self.isInBackground && !self.isAudioPlaying {
                self.interrupted = false
                self.interruptedAt = nil
                self.ensurePlaying()
            }
        }
        let timer = Timer(timeInterval: 4.0, repeats: false) { [weak self] _ in
            self?.endAppBackgroundTask()
        }
        RunLoop.main.add(timer, forMode: .common)
        bgTaskHandoffTimer = timer
    }

    private func endAppBackgroundTask() {
        bgTaskHandoffTimer?.invalidate()
        bgTaskHandoffTimer = nil
        if bgTaskID != .invalid {
            let task = bgTaskID
            bgTaskID = .invalid
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    func clearLockScreenNotification() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: ["decade_bg_status"])
        center.removePendingNotificationRequests(withIdentifiers: ["decade_bg_status"])
    }

    // MARK: - Scene & App Lifecycle Hooks

    @objc func onSceneWillResignActive() {
        runOnMain { [weak self] in
            guard let self = self else { return }
            if self.isTreoActive && self.hasActiveGame && (!self.wanted || !self.isAudioPlaying) {
                self.startKeepalive()
            }
        }
    }

    @objc func onSceneDidEnterBackground() {
        runOnMain { [weak self] in
            guard let self = self else { return }
            self.isInBackground = true

            // Request short 4.0s handoff task on background transition
            self.beginBackgroundHandoffTask()

            if !DecadePiPManager.shared.isPiPActiveOrStarting {
                j2me_render_set_background(1)
            }

            // Free transient caches before iOS background Jetsam check
            URLCache.shared.removeAllCachedResponses()
            GameViewController.purgeInactiveSlotFrames()
            if self.hasActiveGame {
                DispatchQueue.global(qos: .utility).async {
                    jvm_bridge_clean_ram()
                }
            }

            // Never touch AVAudioSession in background if already playing
            if self.isTreoActive && self.hasActiveGame && !self.isAudioPlaying {
                if !self.wanted {
                    self.startKeepalive()
                } else {
                    self.interrupted = false
                    self.interruptedAt = nil
                    self.ensurePlaying()
                }
            }

            // Activate background anti-Wi-Fi-sleep probes & refresh kernel TCP keepalive/QoS on screen off
            if self.isTreoActive && self.hasActiveGame {
                DecadeNetworkKeeper.shared.start()
                DecadeNetworkKeeper.shared.setBackgroundActive(true)
            }

            self.startBackgroundRecordingIfNeeded()
        }
    }

    @objc func onSceneWillEnterForeground() {
        runOnMain { [weak self] in
            guard let self = self else { return }
            self.isInBackground = false
            DecadeNetworkKeeper.shared.setBackgroundActive(GameViewController.isOledSleepingActive)
            if !GameViewController.isOledSleepingActive {
                j2me_render_set_background(0)
            }
            self.endAppBackgroundTask()
            self.clearLockScreenNotification()
            self.finalizeBackgroundTelemetryIfNeeded()

            // Restore audio loop on foreground return
            if self.wanted || (self.isTreoActive && self.hasActiveGame) {
                self.wanted = true
                self.interrupted = false
                self.interruptedAt = nil
                self.startMonitorIfNeeded()
                self.ensurePlaying()
            }
        }
    }

    @objc func onSceneDidBecomeActive() {
        runOnMain { [weak self] in
            guard let self = self else { return }
            self.isInBackground = false
            DecadeNetworkKeeper.shared.setBackgroundActive(GameViewController.isOledSleepingActive)
            if !GameViewController.isOledSleepingActive {
                j2me_render_set_background(0)
            }
            self.clearLockScreenNotification()
            self.finalizeBackgroundTelemetryIfNeeded()
            if self.isTreoActive && self.hasActiveGame && (!self.wanted || !self.isAudioPlaying) {
                self.startKeepalive()
            }
        }
    }

    // MARK: - Audio Session Notifications

    @objc private func handleAudioInterruption(_ notification: Notification) {
        runOnMain { [weak self] in
            guard let self = self, self.wanted,
                  let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            switch type {
            case .began:
                self.interrupted = true
                self.interruptedAt = Date()
                self.audioStatus = "interrupted"
                // audiomxd only grants ~5.0s via CMSMSleep_ExtendPlaybackProcessAssertion before
                // suspending the app. In background, attempt a fast Mixable recovery at +0.8s so
                // opening YouTube/TikTok/Facebook never suspends the J2ME process.
                if self.isInBackground {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                        guard let self = self, self.wanted, self.isInBackground, !self.isAudioPlaying else { return }
                        self.interrupted = false
                        self.interruptedAt = nil
                        self.ensurePlaying(forceMixable: true)
                    }
                }
            case .ended:
                self.interrupted = false
                self.interruptedAt = nil
                self.ensurePlaying(forceMixable: self.isInBackground)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self, self.wanted, !self.isAudioPlaying else { return }
                    self.interrupted = false
                    self.ensurePlaying(forceMixable: self.isInBackground)
                }
            @unknown default:
                break
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        runOnMain { [weak self] in
            guard let self = self, self.wanted else { return }
            if !self.interrupted && !self.isAudioPlaying {
                self.ensurePlaying()
            }
        }
    }

    @objc private func handleMediaServicesLost() {
        runOnMain { [weak self] in
            guard let self = self else { return }
            self.audioStatus = "media-services-lost"
            self.audioPlayer = nil
        }
    }

    @objc private func handleMediaServicesReset() {
        runOnMain { [weak self] in
            guard let self = self, self.wanted else { return }
            self.audioPlayer = nil
            self.interrupted = false
            self.interruptedAt = nil
            self.ensurePlaying()
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        runOnMain { [weak self] in
            guard let self = self, self.wanted else { return }
            self.interrupted = false
            self.interruptedAt = nil
            if !player.play() {
                self.ensurePlaying()
            }
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        runOnMain { [weak self] in
            guard let self = self, self.wanted else { return }
            self.audioPlayer = nil
            self.interrupted = false
            self.interruptedAt = nil
            self.ensurePlaying()
        }
    }
}
