//
//  DecadeBackgroundKeeper.swift
//  J2MEEmulator
//
//  Hardened 24/24 Background Execution Engine (Ported from J2ME NST 1.0.0 + iOS 18/26 fixes):
//  - `isTreoActive` defaults to TRUE (inverted key `jarno1_sticky_off`, exact match to NST `sticky_off`).
//    Once enabled (or after tapping "Ẩn Ứng Dụng" once), it is permanently remembered in UserDefaults
//    so every future swipe to multitasking OR screen lock automatically keeps running 24/24 non-stop.
//  - Uses `AVAudioSession` `.playback` + `mode: .default` + `.mixWithOthers` with subsonic 16Hz
//    non-zero PCM `silent.wav` (-60 dBFS) at `volume = 0.01` (combined -100 dBFS: 100% inaudible to
//    human ears while guaranteeing non-zero gain + non-zero PCM so iOS 18/26 mediaserverd NEVER
//    treats the player as muted/0-volume on screen lock!).
//  - Self-healing interruption & route-change recovery: never permanently locks out if iOS fails to
//    deliver an `.ended` interruption notification after screen lock / notification / video apps.
//  - Observes SceneDelegate, UIApplication background/foreground notifications, AND screen-lock
//    `protectedDataWillBecomeUnavailableNotification`, with a clean 5-second `beginBackgroundTask`
//    handoff bridge on every background/lock transition.
//  - Zero CLLocationManager, zero 15s HTTP polling, zero private BKSProcessAssertion.
//

import UIKit
import AVFAudio
import UserNotifications

// ============================================================
// MARK: - Decade Location Keeper (Disabled — Cool Core from J2ME NST)
// ============================================================

final class DecadeLocationKeeper: NSObject {
    static let shared = DecadeLocationKeeper()

    private(set) var isRunning = false

    /// Disabled by default (J2ME NST uses pure AVAudioPlayer, zero CoreLocation battery drain).
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
// MARK: - Decade Network Keeper (Zero-Radio-Drain Passive Stub)
// ============================================================

final class DecadeNetworkKeeper {
    static let shared = DecadeNetworkKeeper()

    private(set) var isRunning = false
    private(set) var isNetworkConnected = true

    private init() { }

    /// Game TCP sockets maintain native kernel SO_KEEPALIVE + TCP_NODELAY in decade_proxy_tunnel.c.
    /// Avoid periodic HTTP HEAD requests that keep cellular/Wi-Fi radios hot.
    func start() { isRunning = true }
    func stop() { isRunning = false }
}

// ============================================================
// MARK: - DecadeBackgroundKeeper (Hardened NST 24/24 Core)
// ============================================================

final class DecadeBackgroundKeeper: NSObject, AVAudioPlayerDelegate {
    static let shared = DecadeBackgroundKeeper()

    /// Inverted key matching J2ME NST `App.Sticky` (`!NSUserDefaults.bool(forKey: "sticky_off")`).
    /// Defaults to TRUE on fresh install and permanently remembers user preference.
    private static let stickyOffKey = "jarno1_sticky_off"

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

    private(set) var audioStatus: String = "stopped"

    var isAudioPlaying: Bool {
        return audioPlayer?.isPlaying == true
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
        setupNotifications()
        if isAutoCleanRamActive {
            startAutoRamCleaner()
        }
    }

    private func runOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    private func setupNotifications() {
        let nc = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        // Audio session observers (NST BackgroundAudio.Observe + self-healing recovery)
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

        // Direct UIApplication + Lock-Screen observers (safely coalesced with SceneDelegate)
        nc.addObserver(
            self,
            selector: #selector(onSceneWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(onSceneDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(onProtectedDataWillBecomeUnavailable),
            name: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(onSceneWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(onSceneDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
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

    func setAutoCleanRamActive(_ active: Bool) {
        UserDefaults.standard.set(active, forKey: "decade_auto_clean_ram")
        if active {
            startAutoRamCleaner()
        } else {
            stopAutoRamCleaner()
        }
    }

    @objc private func handleMemoryWarning() {
        performRamCleanup(completion: nil)
    }

    func performRamCleanup(completion: ((Double, Double) -> Void)? = nil) {
        let beforeMB = Double(jvm_bridge_get_used_ram_kb()) / 1024.0
        let thresholdMB: Double = isInBackground ? 220.0 : 180.0
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
        timer.schedule(deadline: .now() + 120.0, repeating: 120.0)
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

    // MARK: - Silent Subsonic 16Hz WAV Fallback Generator (Zero audible noise, non-zero PCM)

    private func makeSubsonicKeepaliveWavData() -> Data {
        let sampleRate: Int = 22050
        let durationSeconds: Int = 8
        let numSamples = sampleRate * durationSeconds
        let dataSize = numSamples * 2
        var data = Data(capacity: 44 + dataSize)

        func appendUInt32LE(_ v: UInt32) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendUInt16LE(_ v: UInt16) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        // RIFF/WAVE header (mono, 16-bit PCM, 22050 Hz)
        data.append(contentsOf: "RIFF".utf8)
        appendUInt32LE(UInt32(36 + dataSize))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        appendUInt32LE(16)
        appendUInt16LE(1) // PCM
        appendUInt16LE(1) // mono
        appendUInt32LE(UInt32(sampleRate))
        appendUInt32LE(UInt32(sampleRate * 2))
        appendUInt16LE(2)
        appendUInt16LE(16)
        data.append(contentsOf: "data".utf8)
        appendUInt32LE(UInt32(dataSize))

        // 16 Hz subsonic sine wave, peak amplitude 40 (~ -58 dBFS); at volume 0.01 => ~ -98 dBFS (100% silent)
        let freq = 16.0
        let amp = 40.0
        for i in 0..<numSamples {
            let phase = 2.0 * Double.pi * freq * Double(i) / Double(sampleRate)
            var sample = Int16((sin(phase) * amp).rounded()).littleEndian
            withUnsafeBytes(of: &sample) { data.append(contentsOf: $0) }
        }
        return data
    }

    // MARK: - Hardened BackgroundAudio Core (1:1 NST + iOS 18/26 Lock-Screen Hardening)

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
            self.audioPlayer?.stop()
            self.audioPlayer = nil
            self.audioStatus = "stopped"
            DecadeNetworkKeeper.shared.stop()
            self.endAppBackgroundTask()
            self.clearLockScreenNotification()
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    private func startMonitorIfNeeded() {
        guard monitorTimer == nil else { return }
        // 3.0s monitor interval recovers quickly from any lock-screen or route interruption
        // before iOS's background audio suspension grace window expires.
        let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self, self.wanted else { return }
            if self.interrupted {
                // Self-heal if iOS swallowed `.ended` (common on lock screen / notifications / video apps)
                if let at = self.interruptedAt, Date().timeIntervalSince(at) >= 3.0 {
                    self.interrupted = false
                    self.interruptedAt = nil
                    self.ensurePlaying()
                }
                return
            }
            if self.audioPlayer?.isPlaying != true {
                self.ensurePlaying()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer
    }

    /// Ensures the silent background audio keep-alive player is running:
    /// 1. If `audioPlayer` is already playing -> immediately return WITHOUT touching AVAudioSession!
    /// 2. Configure `.playback` + `.default` + `.mixWithOthers` and activate session.
    /// 3. Play subsonic 16Hz `silent.wav` (non-zero PCM, -60 dBFS) at non-zero `volume = 0.01`
    ///    (combined -100 dBFS: 100% physically inaudible, never detected as volume==0 muted by iOS 18/26).
    private func ensurePlaying() {
        guard wanted, !interrupted else { return }

        if let p = audioPlayer, p.isPlaying {
            audioStatus = "playing"
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            audioStatus = "session-err: \(error.localizedDescription)"
            print("[BackgroundAudio] AVAudioSession error: \(error)")
            return
        }

        if audioPlayer == nil {
            var created: AVAudioPlayer? = nil
            var targetVolume: Float = 0.01

            // Prefer subsonic 16Hz silent.wav (-60 dBFS) at volume 0.01 (-100 dBFS total, non-zero gain + non-zero PCM)
            if let silentURL = Bundle.main.url(forResource: "silent", withExtension: "wav") {
                created = try? AVAudioPlayer(contentsOf: silentURL)
                targetVolume = 0.01
            }
            // Fallback 1: in-memory subsonic 16Hz PCM WAV
            if created == nil {
                created = try? AVAudioPlayer(data: makeSubsonicKeepaliveWavData())
                targetVolume = 0.01
            }
            // Fallback 2: NST background-loop.wav at ultra-low non-zero gain (-92 dBFS total)
            if created == nil, let loopURL = Bundle.main.url(forResource: "background-loop", withExtension: "wav") {
                created = try? AVAudioPlayer(contentsOf: loopURL)
                targetVolume = 0.0005
            }

            guard let p = created else {
                audioStatus = "missing-wav"
                print("[BackgroundAudio] Failed to create AVAudioPlayer")
                return
            }
            p.delegate = self
            p.numberOfLoops = -1
            p.volume = targetVolume
            audioPlayer = p
        }

        guard let p = audioPlayer else { return }
        if p.volume <= 0.0 {
            p.volume = 0.01
        }
        guard p.prepareToPlay(), p.play() else {
            audioStatus = "play-false"
            print("[BackgroundAudio] AVAudioPlayer.play() returned false")
            return
        }
        audioStatus = "playing"
    }

    /// Acquire a short 5.0-second background task bridging background/lock-screen handoff
    /// and end it cleanly BEFORE iOS's 30s expiration watchdog so mediaserverd audio keeps the app alive 24/24.
    private func beginBackgroundHandoffTask() {
        let now = CACurrentMediaTime()
        // Coalesce back-to-back SceneDelegate + UIApplication + ProtectedData notifications within 0.5s
        if bgTaskID != .invalid && (now - lastBgHandoffTime) < 0.5 {
            return
        }
        lastBgHandoffTime = now

        endAppBackgroundTask()
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "jarNO1-Handoff") { [weak self] in
            self?.endAppBackgroundTask()
        }
        let timer = Timer(timeInterval: 5.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.wanted && !self.isAudioPlaying {
                self.interrupted = false
                self.interruptedAt = nil
                self.ensurePlaying()
            }
            self.endAppBackgroundTask()
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

    // MARK: - Scene, App & Screen-Lock Lifecycle Hooks

    @objc func onSceneWillResignActive() {
        runOnMain { [weak self] in
            guard let self = self else { return }
            // Still foreground-eligible here: prime audio BEFORE iOS completes backgrounding or screen lock!
            if self.isTreoActive && self.hasActiveGame {
                if !self.wanted || !self.isAudioPlaying {
                    self.startKeepalive()
                }
            }
        }
    }

    @objc private func onProtectedDataWillBecomeUnavailable() {
        // Fires specifically when the user presses the Power/Lock button or auto-lock triggers.
        onSceneDidEnterBackground()
    }

    @objc func onSceneDidEnterBackground() {
        runOnMain { [weak self] in
            guard let self = self else { return }
            self.isInBackground = true

            // Short 5s handoff task on EVERY background / lock-screen transition (never skipped on re-lock)
            self.beginBackgroundHandoffTask()

            if !DecadePiPManager.shared.isPiPActiveOrStarting {
                j2me_render_set_background(1)
            }

            if self.isTreoActive && self.hasActiveGame {
                // Keep audio alive WITHOUT calling setCategory/setActive again if already playing!
                if !self.wanted {
                    self.startKeepalive()
                } else if !self.isAudioPlaying {
                    self.interrupted = false
                    self.interruptedAt = nil
                    self.ensurePlaying()
                }
            }
        }
    }

    @objc func onSceneWillEnterForeground() {
        runOnMain { [weak self] in
            guard let self = self else { return }
            self.isInBackground = false
            if !GameViewController.isOledSleepingActive {
                j2me_render_set_background(0)
            }
            self.endAppBackgroundTask()
            self.clearLockScreenNotification()
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
            if !GameViewController.isOledSleepingActive {
                j2me_render_set_background(0)
            }
            self.clearLockScreenNotification()
            if self.isTreoActive && self.hasActiveGame {
                if !self.wanted {
                    self.startKeepalive()
                } else if !self.isAudioPlaying {
                    self.interrupted = false
                    self.interruptedAt = nil
                    self.ensurePlaying()
                }
            }
        }
    }

    // MARK: - Audio Session Notifications (Self-Healing Recovery)

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
            case .ended:
                self.interrupted = false
                self.interruptedAt = nil
                self.ensurePlaying()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    guard let self = self, self.wanted, !self.isAudioPlaying else { return }
                    self.ensurePlaying()
                }
            @unknown default:
                break
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        runOnMain { [weak self] in
            guard let self = self, self.wanted else { return }
            if self.interrupted, let at = self.interruptedAt, Date().timeIntervalSince(at) >= 2.0 {
                self.interrupted = false
                self.interruptedAt = nil
            }
            if !self.interrupted && !self.isAudioPlaying {
                self.ensurePlaying()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    guard let self = self, self.wanted, !self.interrupted, !self.isAudioPlaying else { return }
                    self.ensurePlaying()
                }
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
