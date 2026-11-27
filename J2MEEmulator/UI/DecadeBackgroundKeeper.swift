//
//  DecadeBackgroundKeeper.swift
//  J2MEEmulator
//
//  Ported 1:1 from J2ME NST 1.0.0 (`J2me.iOS.Platform.BackgroundAudio`):
//  - Uses a single lightweight `AVAudioPlayer` looping `background-loop.wav` (fallback `silent.wav`)
//    at volume 0.01 with `.playback` + `.mixWithOthers` ONLY when "Treo tắt màn" is enabled.
//  - Eliminates hot-CPU/radio culprits from legacy Decade:
//    * NO CLLocationManager / continuous GPS/BTS background updates
//    * NO AVAudioEngine / AVAudioSourceNode real-time DSP thread
//    * NO 15-second HTTP HEAD network polling wakeups (TCP sockets use native SO_KEEPALIVE)
//    * NO private BKSProcessAssertion XPC churn or NowPlaying lockscreen spam
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

    /// Game TCP sockets already maintain native kernel SO_KEEPALIVE in decade_proxy_tunnel.c.
    /// Avoid periodic HTTP HEAD requests that keep cellular/Wi-Fi radios hot.
    func start() { isRunning = true }
    func stop() { isRunning = false }
}

// ============================================================
// MARK: - DecadeBackgroundKeeper (1:1 Port of J2ME NST BackgroundAudio)
// ============================================================

final class DecadeBackgroundKeeper: NSObject, AVAudioPlayerDelegate {
    static let shared = DecadeBackgroundKeeper()

    private var audioPlayer: AVAudioPlayer?
    private var monitorTimer: Timer?
    private var ramCleanTimer: DispatchSourceTimer?
    private var currentGameName: String = "jarNO1"
    private var bgTaskID: UIBackgroundTaskIdentifier = .invalid
    private var wanted = false
    private var interrupted = false

    var isTreoActive: Bool {
        get {
            // Default OFF (matches J2ME NST): only keep audio/idle-timer awake when user turns on Treo.
            return UserDefaults.standard.bool(forKey: "decade_treo_tat_man_v2")
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

    private func setupNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
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
        UserDefaults.standard.set(active, forKey: "decade_treo_tat_man_v2")
        if active {
            startKeepalive()
            UIApplication.shared.isIdleTimerDisabled = true
        } else {
            stopKeepalive()
            UIApplication.shared.isIdleTimerDisabled = false
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

    // MARK: - J2ME NST BackgroundAudio Core

    func startKeepalive() {
        wanted = true
        interrupted = false
        ensurePlaying()
        startMonitor()
    }

    func stopKeepalive() {
        wanted = false
        interrupted = false
        monitorTimer?.invalidate()
        monitorTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        endAppBackgroundTask()
        clearLockScreenNotification()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func startMonitor() {
        monitorTimer?.invalidate()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.wanted, !self.interrupted else { return }
                if self.audioPlayer?.isPlaying != true {
                    self.ensurePlaying()
                }
            }
        }
    }

    private func ensurePlaying() {
        guard wanted else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            return
        }

        if audioPlayer == nil {
            let bundleURL = Bundle.main.url(forResource: "background-loop", withExtension: "wav")
                ?? Bundle.main.url(forResource: "silent", withExtension: "wav")
            if let url = bundleURL, let p = try? AVAudioPlayer(contentsOf: url) {
                p.delegate = self
                p.numberOfLoops = -1
                p.volume = 0.01
                p.prepareToPlay()
                audioPlayer = p
            }
        }

        if let p = audioPlayer, !p.isPlaying {
            _ = p.play()
        }
    }

    private func beginAppBackgroundTask() {
        if bgTaskID != .invalid {
            if UIApplication.shared.backgroundTimeRemaining > 25.0 {
                return
            }
            let expired = bgTaskID
            bgTaskID = .invalid
            UIApplication.shared.endBackgroundTask(expired)
        }
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "jarNO1-AFK") { [weak self] in
            self?.endAppBackgroundTask()
        }
    }

    private func endAppBackgroundTask() {
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

    // MARK: - Scene / App Lifecycle Hooks

    @objc func onSceneWillResignActive() {
        if isTreoActive && GameViewController.currentActiveGameVC != nil {
            startKeepalive()
        }
    }

    @objc func onSceneDidEnterBackground() {
        if !DecadePiPManager.shared.isPiPActive {
            j2me_render_set_background(1)
        }
        if isTreoActive && GameViewController.currentActiveGameVC != nil {
            startKeepalive()
            beginAppBackgroundTask()
        }
    }

    @objc func onSceneWillEnterForeground() {
        j2me_render_set_background(0)
        endAppBackgroundTask()
        clearLockScreenNotification()
        if wanted {
            interrupted = false
            ensurePlaying()
        }
    }

    @objc private func handleAppDidEnterBackground() {
        onSceneDidEnterBackground()
    }

    @objc private func handleAppWillEnterForeground() {
        onSceneWillEnterForeground()
    }

    @objc private func handleAppDidBecomeActive() {
        j2me_render_set_background(0)
        clearLockScreenNotification()
        if wanted {
            interrupted = false
            ensurePlaying()
        }
    }

    // MARK: - Audio Session Notifications (exact match to J2ME NST BackgroundAudio)

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard wanted,
              let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            interrupted = true
        case .ended:
            interrupted = false
            ensurePlaying()
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard wanted, !interrupted else { return }
        ensurePlaying()
    }

    @objc private func handleMediaServicesReset() {
        guard wanted else { return }
        audioPlayer = nil
        interrupted = false
        ensurePlaying()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if wanted && !interrupted {
            player.play()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if wanted {
            audioPlayer = nil
            ensurePlaying()
        }
    }
}
