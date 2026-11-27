//
//  DecadeBackgroundKeeper.swift
//  J2MEEmulator
//
//  Ported 1:1 from J2ME NST 1.0.0 (`J2me.iOS.Platform.BackgroundAudio`,
//  `App.Sticky`, and `AppDelegate.DidEnterBackground` / `WillEnterForeground`):
//  - `isTreoActive` defaults to TRUE (inverted key `jarno1_sticky_off`, exact match to NST `sticky_off`)
//    so background audio is ALWAYS primed in foreground when a game starts — BEFORE the user
//    taps "Ẩn Ứng Dụng", swipes Home, switches apps, or locks the screen.
//  - `ensurePlaying()` returns immediately when `audioPlayer?.isPlaying == true` so it NEVER
//    re-calls `AVAudioSession.setCategory` / `setActive(true)` while transitioning into background.
//  - Uses `AVAudioSession` `.playback` + `.mixWithOthers` with `background-loop.wav` (non-zero PCM,
//    `numberOfLoops = -1`, `volume = 0.0`, exact match to NST `BackgroundAudio.EnsurePlaying`).
//  - Starts a 4.0-second `beginBackgroundTask` handoff timer in `onSceneDidEnterBackground`
//    and ends it cleanly after 4s (exact match to NST `AppDelegate.DidEnterBackground`).
//  - Zero CLLocationManager, zero 15s HTTP HEAD polling, zero private BKSProcessAssertion.
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

    /// Game TCP sockets already maintain native kernel SO_KEEPALIVE + SO_TC_VO in decade_proxy_tunnel.c.
    /// Avoid periodic HTTP HEAD requests that keep cellular/Wi-Fi radios hot.
    func start() { isRunning = true }
    func stop() { isRunning = false }
}

// ============================================================
// MARK: - DecadeBackgroundKeeper (1:1 Port of J2ME NST BackgroundAudio)
// ============================================================

final class DecadeBackgroundKeeper: NSObject, AVAudioPlayerDelegate {
    static let shared = DecadeBackgroundKeeper()

    /// Inverted key matching J2ME NST `App.Sticky` (`!NSUserDefaults.bool(forKey: "sticky_off")`).
    /// Defaults to TRUE on fresh install and upgrade over v1.0.3.
    private static let stickyOffKey = "jarno1_sticky_off"

    private var audioPlayer: AVAudioPlayer?
    private var monitorTimer: Timer?
    private var bgTaskHandoffTimer: Timer?
    private var ramCleanTimer: DispatchSourceTimer?
    private var currentGameName: String = "jarNO1"
    private var bgTaskID: UIBackgroundTaskIdentifier = .invalid
    private var wanted = false
    private var interrupted = false
    private var isInBackground = false

    private(set) var audioStatus: String = "stopped"

    var isAudioPlaying: Bool {
        return audioPlayer?.isPlaying == true
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
        // Audio session observers (exact match to J2ME NST BackgroundAudio.Observe).
        // Scene/App background & foreground transitions are routed once via SceneDelegate
        // to avoid duplicate AVAudioSession re-entrancy during background handoff.
        nc.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        nc.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
        nc.addObserver(
            self,
            selector: #selector(handleMediaServicesLost),
            name: AVAudioSession.mediaServicesWereLostNotification,
            object: AVAudioSession.sharedInstance()
        )
        nc.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance()
        )
        nc.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    func updateNowPlayingGame(name: String) {
        currentGameName = name.isEmpty ? "jarNO1" : name
    }

    func setTreoActive(_ active: Bool) {
        UserDefaults.standard.set(!active, forKey: Self.stickyOffKey)
        runOnMain { [weak self] in
            guard let self = self else { return }
            let hasGame = GameViewController.currentActiveGameVC != nil
            if active {
                if hasGame {
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
        guard completion != nil || beforeMB > 180.0 else { return }

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

    // MARK: - J2ME NST BackgroundAudio Core (1:1 Port)

    func startKeepalive() {
        runOnMain { [weak self] in
            guard let self = self else { return }
            self.wanted = true
            self.interrupted = false
            self.startMonitorIfNeeded()
            self.ensurePlaying()
        }
    }

    func stopKeepalive() {
        runOnMain { [weak self] in
            guard let self = self else { return }
            self.wanted = false
            self.interrupted = false
            self.monitorTimer?.invalidate()
            self.monitorTimer = nil
            self.audioPlayer?.stop()
            self.audioPlayer = nil
            self.audioStatus = "stopped"
            self.endAppBackgroundTask()
            self.clearLockScreenNotification()
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    private func startMonitorIfNeeded() {
        guard monitorTimer == nil else { return }
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, self.wanted, !self.interrupted else { return }
            if self.audioPlayer?.isPlaying != true {
                self.ensurePlaying()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer
    }

    /// Exact 1:1 port of J2ME NST `BackgroundAudio.EnsurePlaying()`:
    /// 1. If `audioPlayer` is already playing -> immediately return WITHOUT touching AVAudioSession!
    /// 2. Configure `.playback` + `.mixWithOthers` and activate session.
    /// 3. Load `background-loop.wav` (non-zero PCM, 8s mono 22050Hz), loop infinitely at volume 0.0.
    private func ensurePlaying() {
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
            audioStatus = "session-err: \(error.localizedDescription)"
            print("[BackgroundAudio] AVAudioSession error: \(error)")
            return
        }

        if audioPlayer == nil {
            guard let bundleURL = Bundle.main.url(forResource: "background-loop", withExtension: "wav")
                    ?? Bundle.main.url(forResource: "silent", withExtension: "wav") else {
                audioStatus = "missing-wav"
                print("[BackgroundAudio] Missing background-loop.wav")
                return
            }
            do {
                let p = try AVAudioPlayer(contentsOf: bundleURL)
                p.delegate = self
                p.numberOfLoops = -1
                audioPlayer = p
            } catch {
                audioStatus = "player-err: \(error.localizedDescription)"
                print("[BackgroundAudio] AVAudioPlayer init error: \(error)")
                return
            }
        }

        guard let p = audioPlayer else { return }
        p.volume = 0.0
        guard p.prepareToPlay(), p.play() else {
            audioStatus = "play-false"
            print("[BackgroundAudio] AVAudioPlayer.play() returned false")
            return
        }
        audioStatus = "playing"
    }

    /// Matches J2ME NST `AppDelegate.DidEnterBackground`:
    /// Acquire a short background task during background transition and end it cleanly after 4.0s
    /// so iOS hands off seamlessly to the active `.playback` audio session without hitting the 30s expiration kill.
    private func beginBackgroundHandoffTask() {
        endAppBackgroundTask()
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "jarNO1-Handoff") { [weak self] in
            self?.endAppBackgroundTask()
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

    // MARK: - Scene Lifecycle Hooks (Exact 1:1 with J2ME NST AppDelegate)

    @objc func onSceneWillResignActive() {
        runOnMain { [weak self] in
            guard let self = self else { return }
            if self.isTreoActive && GameViewController.currentActiveGameVC != nil {
                // Only start if not already playing — never disturb live AVAudioSession!
                if !self.wanted || !self.isAudioPlaying {
                    self.startKeepalive()
                }
            }
        }
    }

    @objc func onSceneDidEnterBackground() {
        runOnMain { [weak self] in
            guard let self = self else { return }
            guard !self.isInBackground else { return }
            self.isInBackground = true

            // Short 4s handoff task matching J2ME NST AppDelegate.DidEnterBackground
            self.beginBackgroundHandoffTask()

            if !DecadePiPManager.shared.isPiPActive {
                j2me_render_set_background(1)
            }

            if self.isTreoActive && GameViewController.currentActiveGameVC != nil {
                // Keep audio alive without calling setCategory/setActive again if already playing!
                if !self.wanted {
                    self.startKeepalive()
                } else if !self.isAudioPlaying && !self.interrupted {
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
            if self.wanted || (self.isTreoActive && GameViewController.currentActiveGameVC != nil) {
                self.wanted = true
                self.interrupted = false
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
            if self.wanted && !self.isAudioPlaying {
                self.interrupted = false
                self.ensurePlaying()
            }
        }
    }

    // MARK: - Audio Session Notifications (Exact match to J2ME NST BackgroundAudio)

    @objc private func handleAudioInterruption(_ notification: Notification) {
        runOnMain { [weak self] in
            guard let self = self, self.wanted,
                  let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            switch type {
            case .began:
                self.interrupted = true
                self.audioStatus = "interrupted"
            case .ended:
                self.interrupted = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.ensurePlaying()
                }
            @unknown default:
                break
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        runOnMain { [weak self] in
            guard let self = self, self.wanted, !self.interrupted else { return }
            if !self.isAudioPlaying {
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
            self.ensurePlaying()
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        runOnMain { [weak self] in
            guard let self = self, self.wanted, !self.interrupted else { return }
            if !player.play() {
                self.ensurePlaying()
            }
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        runOnMain { [weak self] in
            guard let self = self, self.wanted else { return }
            self.audioPlayer = nil
            self.ensurePlaying()
        }
    }
}
