//
//  DecadeBackgroundKeeper.swift
//  J2MEEmulator
//
//  Hardened Dual-Layer 24/24 Background Execution Engine (v1.0.7):
//  - `isTreoActive` defaults to TRUE (migrated key `jarno1_treo_247_v7_off`) so users
//    upgrading from earlier builds never stay stuck with an accidental toggle-off state.
//    Once enabled (or after tapping "Ẩn Ứng Dụng" once), it is permanently remembered in
//    UserDefaults so every future multitasking swipe OR screen lock runs 24/24 non-stop.
//  - Dual-Layer Hardware Audio Keep-Alive:
//      1. Primary: `AVAudioEngine` + `AVAudioSourceNode` driving a live CoreAudio `AURemoteIO`
//         hardware render callback outputting a continuous 16 Hz subsonic sine wave at
//         -50.5 dBFS (amplitude 0.003, outputVolume = 1.0): 100% physically inaudible on
//         iPhone speakers & headphones while staying >45 dB above 16-bit digital zero so
//         iOS 18/26 `mediaserverd` NEVER flags the session as silent!
//      2. Secondary: `AVAudioPlayer` looping `silent.wav` (16 Hz subsonic -57 dBFS) at
//         `volume = 1.0` (fallback in-memory 16 Hz WAV, fallback `background-loop.wav` like NST).
//  - Uses exact 2-arg `AVAudioSession.setCategory(.playback, options:)` + 1-arg `setActive(true)`
//    matching J2ME NST (`[.mixWithOthers]` by default, plus optional 1-tap Exclusive `.playback`
//    mode in Treo 24/7 & Game Settings).
//  - Built-in On-Device Background Proof Telemetry: counts actual 1-second background CPU ticks
//    vs wall-clock elapsed time across every lock/multitasking session and reports exact status.
//  - Zero CLLocationManager, zero 15s HTTP polling, zero private BKSProcessAssertion.
//

import UIKit
import AVFoundation
import AudioToolbox
import UserNotifications

/// Non-isolated CoreAudio render-block factory so `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
/// NEVER attaches a `@MainActor` executor assertion to the real-time AURemoteIO audio thread.
nonisolated private func createSubsonicAudioSourceNode(format: AVAudioFormat, sampleRate: Double) -> AVAudioSourceNode {
    // Continuous 16 Hz subsonic sine wave at amplitude 0.003 (-50.5 dBFS):
    // - 100% physically inaudible (below 20 Hz human threshold & ~120 Hz iPhone speaker cutoff)
    // - ~98 LSB in 16-bit PCM: never quantized to 0, keeps AURemoteIO hardware IO alive 24/24
    var phase: Double = 0.0
    let phaseStep = 2.0 * Double.pi * 16.0 / sampleRate
    let amplitude: Float = 0.003
    let twoPi = 2.0 * Double.pi

    return AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for frame in 0..<Int(frameCount) {
            let sample = Float(sin(phase)) * amplitude
            phase += phaseStep
            if phase >= twoPi {
                phase -= twoPi
            }
            for buf in abl {
                if let ptr = buf.mData?.assumingMemoryBound(to: Float.self) {
                    ptr[frame] = sample
                }
            }
        }
        return noErr
    }
}

// ============================================================
// MARK: - Decade Location Keeper (Disabled — Cool Core from J2ME NST)
// ============================================================

final class DecadeLocationKeeper: NSObject {
    static let shared = DecadeLocationKeeper()

    private(set) var isRunning = false

    /// Disabled by default (J2ME NST uses pure audio keep-alive, zero CoreLocation battery drain).
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
// MARK: - DecadeBackgroundKeeper (Dual-Layer AURemoteIO + NST 24/24 Core)
// ============================================================

final class DecadeBackgroundKeeper: NSObject, AVAudioPlayerDelegate {
    static let shared = DecadeBackgroundKeeper()

    /// Notification posted on foreground return after >= 8s in background so UI can display proof toast.
    static let backgroundResumeReportNotification = Notification.Name("DecadeBackgroundResumeReport")

    /// Migrated v7 sticky-off key (inverted: false => ON by default).
    /// Clean migration guarantees users who accidentally toggled off the ambiguous v1.0.6 button
    /// automatically start v1.0.7 with 24/24 background execution enabled.
    private static let stickyOffKey = "jarno1_treo_247_v7_off"

    /// Optional Exclusive `.playback` mode (OFF by default = `.mixWithOthers` matching J2ME NST).
    private static let exclusiveAudioKey = "jarno1_exclusive_audio_mode"

    // Audio Layer 1: Hardware AURemoteIO via AVAudioEngine + AVAudioSourceNode
    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?

    // Audio Layer 2: NST-compatible AVAudioPlayer loop redundancy
    private var audioPlayer: AVAudioPlayer?

    // Timers & Background Handoff
    private var monitorTimer: DispatchSourceTimer?
    private var bgTaskHandoffTimer: Timer?
    private var bgTickTimer: DispatchSourceTimer?
    private var ramCleanTimer: DispatchSourceTimer?
    private var currentGameName: String = "jarNO1"
    private var bgTaskID: UIBackgroundTaskIdentifier = .invalid

    // Runtime state
    private var wanted = false
    private var interrupted = false
    private var interruptedAt: Date?
    private var isInBackground = false
    private var lastBgHandoffTime: CFTimeInterval = 0

    // On-device Background Proof Telemetry
    private var bgEnterDate: Date?
    private var bgAliveTicks: Int = 0
    private(set) var lastBgWallSeconds: Int = 0
    private(set) var lastBgAliveSeconds: Int = 0
    private(set) var lastBgReport: String = "Chưa ẩn/tắt màn lần nào"
    private(set) var audioStatus: String = "stopped"
    private(set) var lastAudioError: String = ""

    var isEngineRunning: Bool {
        return audioEngine?.isRunning == true
    }

    var isPlayerPlaying: Bool {
        return audioPlayer?.isPlaying == true
    }

    var isAudioPlaying: Bool {
        return isEngineRunning || isPlayerPlaying
    }

    var isFullyActive: Bool {
        return isEngineRunning && isPlayerPlaying
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

    /// FALSE (default) = `.mixWithOthers` (matches J2ME NST; lets TikTok/YouTube play simultaneously).
    /// TRUE = Exclusive `.playback` without `.mixWithOthers` (strongest lock-screen priority on iOS 26).
    var isExclusiveAudioMode: Bool {
        get {
            return UserDefaults.standard.bool(forKey: Self.exclusiveAudioKey)
        }
        set {
            setExclusiveAudioMode(newValue)
        }
    }

    var audioModeDescription: String {
        return isExclusiveAudioMode
            ? "Độc quyền (Khóa cứng 24/24)"
            : "Mix app khác (Chuẩn NST)"
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

        // Audio session & engine observers
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
            selector: #selector(handleEngineConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: nil
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

    func setExclusiveAudioMode(_ exclusive: Bool) {
        let changed = (UserDefaults.standard.bool(forKey: Self.exclusiveAudioKey) != exclusive)
        UserDefaults.standard.set(exclusive, forKey: Self.exclusiveAudioKey)
        UserDefaults.standard.synchronize()
        guard changed else { return }
        runOnMain { [weak self] in
            guard let self = self, self.wanted else { return }
            self.teardownAudioLayers()
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

    // MARK: - Subsonic 16 Hz WAV Fallback Generator (-50 dBFS, 100% inaudible, non-zero PCM)

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

        // 16 Hz subsonic sine wave, peak amplitude 96 (~ -50.6 dBFS) played at volume 1.0
        let freq = 16.0
        let amp = 96.0
        for i in 0..<numSamples {
            let phase = 2.0 * Double.pi * freq * Double(i) / Double(sampleRate)
            var sample = Int16((sin(phase) * amp).rounded()).littleEndian
            withUnsafeBytes(of: &sample) { data.append(contentsOf: $0) }
        }
        return data
    }

    // MARK: - Dual-Layer Audio Keep-Alive Core (AVAudioEngine AURemoteIO + AVAudioPlayer)

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
            self.monitorTimer?.cancel()
            self.monitorTimer = nil
            self.stopBackgroundTickTimer()
            self.bgEnterDate = nil
            self.teardownAudioLayers()
            self.audioStatus = "stopped"
            self.lastAudioError = ""
            DecadeNetworkKeeper.shared.stop()
            self.endAppBackgroundTask()
            self.clearLockScreenNotification()
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    private func teardownAudioLayers() {
        if let engine = audioEngine {
            engine.stop()
            engine.reset()
        }
        audioEngine = nil
        sourceNode = nil

        audioPlayer?.stop()
        audioPlayer = nil
    }

    private func startMonitorIfNeeded() {
        guard monitorTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 3.0, repeating: 3.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.wanted else { return }
            if self.interrupted {
                // Self-heal if iOS swallows `.ended` after lock screen / notification / video apps
                if let at = self.interruptedAt, Date().timeIntervalSince(at) >= 2.5 {
                    self.interrupted = false
                    self.interruptedAt = nil
                    self.ensurePlaying()
                }
                return
            }
            if !self.isFullyActive {
                self.ensurePlaying()
            }
        }
        timer.resume()
        monitorTimer = timer
    }

    private func startAudioEngineIfNeeded() -> Bool {
        if let engine = audioEngine, engine.isRunning {
            return true
        }

        if let existing = audioEngine {
            do {
                existing.prepare()
                try existing.start()
                if existing.isRunning {
                    return true
                }
            } catch {
                lastAudioError = "eng-restart: \((error as NSError).code)"
                existing.stop()
                existing.reset()
                audioEngine = nil
                sourceNode = nil
            }
        }

        let engine = AVAudioEngine()
        let hwRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate: Double = (hwRate >= 8000.0 && hwRate <= 192000.0) ? hwRate : 44100.0

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            lastAudioError = "eng-fmt"
            return false
        }

        let srcNode = createSubsonicAudioSourceNode(format: format, sampleRate: sampleRate)

        engine.attach(srcNode)
        engine.connect(srcNode, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1.0
        engine.prepare()

        do {
            try engine.start()
            self.audioEngine = engine
            self.sourceNode = srcNode
            return engine.isRunning
        } catch {
            let nsErr = error as NSError
            lastAudioError = "eng(\(nsErr.code)): \(nsErr.localizedDescription)"
            print("[BackgroundAudio] AVAudioEngine start failed: \(error)")
            engine.stop()
            return false
        }
    }

    private func startAudioPlayerIfNeeded() -> Bool {
        if let p = audioPlayer, p.isPlaying {
            return true
        }

        if audioPlayer == nil {
            var created: AVAudioPlayer? = nil
            var targetVolume: Float = 1.0

            // Prefer subsonic 16 Hz silent.wav (-57.2 dBFS) at FULL volume = 1.0:
            // stays 100% inaudible while keeping non-zero gain + non-zero PCM!
            if let silentURL = Bundle.main.url(forResource: "silent", withExtension: "wav") {
                created = try? AVAudioPlayer(contentsOf: silentURL)
                targetVolume = 1.0
            }
            // Fallback 1: in-memory 16 Hz -50.6 dBFS PCM WAV at volume = 1.0
            if created == nil {
                created = try? AVAudioPlayer(data: makeSubsonicKeepaliveWavData())
                targetVolume = 1.0
            }
            // Fallback 2: NST background-loop.wav at volume = 0.0 (exact NST fallback)
            if created == nil, let loopURL = Bundle.main.url(forResource: "background-loop", withExtension: "wav") {
                created = try? AVAudioPlayer(contentsOf: loopURL)
                targetVolume = 0.0
            }

            guard let p = created else {
                lastAudioError = "player-missing-wav"
                print("[BackgroundAudio] Failed to create AVAudioPlayer")
                return false
            }
            p.delegate = self
            p.numberOfLoops = -1
            p.volume = targetVolume
            audioPlayer = p
        }

        guard let p = audioPlayer else { return false }
        guard p.prepareToPlay(), p.play() else {
            lastAudioError = "player-play-false"
            print("[BackgroundAudio] AVAudioPlayer.play() returned false")
            return false
        }
        return true
    }

    /// Ensures BOTH hardware AURemoteIO (`AVAudioEngine`) and `AVAudioPlayer` loop are active:
    /// 1. If both are already running -> immediately return WITHOUT touching AVAudioSession!
    /// 2. Configure 2-arg `setCategory(.playback, options:)` + 1-arg `setActive(true)` matching NST.
    /// 3. Start `AVAudioEngine` (16 Hz -50.5 dBFS) and `AVAudioPlayer` (`silent.wav` vol=1.0).
    private func ensurePlaying() {
        guard wanted, !interrupted else { return }

        if isFullyActive {
            audioStatus = "Engine+Player OK"
            return
        }

        let session = AVAudioSession.sharedInstance()
        let options: AVAudioSession.CategoryOptions = isExclusiveAudioMode ? [] : [.mixWithOthers]
        do {
            try session.setCategory(.playback, options: options)
            try session.setActive(true)
        } catch {
            let nsErr = error as NSError
            lastAudioError = "sess(\(nsErr.code)): \(nsErr.localizedDescription)"
            audioStatus = "Lỗi AudioSession (\(nsErr.code))"
            print("[BackgroundAudio] AVAudioSession error: \(error)")
            return
        }

        let engOK = startAudioEngineIfNeeded()
        let plyOK = startAudioPlayerIfNeeded()

        if engOK && plyOK {
            audioStatus = "Engine+Player OK"
            lastAudioError = ""
        } else if engOK {
            audioStatus = "Engine OK (Player off)"
        } else if plyOK {
            audioStatus = "Player OK (Engine off)"
        } else {
            audioStatus = lastAudioError.isEmpty ? "Audio fail" : lastAudioError
        }
    }

    // MARK: - Background Execution Proof Telemetry (1-second real execution counter)

    private func startBackgroundTickTimerIfNeeded() {
        if bgEnterDate == nil {
            bgEnterDate = Date()
            bgAliveTicks = 0
        }
        guard bgTickTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isInBackground else { return }
            self.bgAliveTicks += 1
        }
        timer.resume()
        bgTickTimer = timer
    }

    private func stopBackgroundTickTimer() {
        bgTickTimer?.cancel()
        bgTickTimer = nil
    }

    private func finalizeBackgroundTelemetryIfNeeded() {
        stopBackgroundTickTimer()
        guard let entered = bgEnterDate else { return }
        bgEnterDate = nil

        let wall = max(0, Int(Date().timeIntervalSince(entered).rounded()))
        let alive = min(wall, bgAliveTicks)
        guard wall >= 3 else { return }

        lastBgWallSeconds = wall
        lastBgAliveSeconds = alive

        if !isTreoActive {
            lastBgReport = "Treo 24/24 đang TẮT (\(alive)/\(wall)s)"
        } else if alive >= max(2, Int(Double(wall) * 0.70)) {
            lastBgReport = "✓ Chạy nền xuyên suốt \(alive)/\(wall)s (\(audioStatus))"
        } else {
            let detail = lastAudioError.isEmpty ? audioStatus : lastAudioError
            lastBgReport = "⚠️ Bị iOS dừng nền: \(alive)/\(wall)s (\(detail))"
        }

        if wall >= 8 && hasActiveGame {
            NotificationCenter.default.post(
                name: Self.backgroundResumeReportNotification,
                object: nil,
                userInfo: ["message": lastBgReport]
            )
        }
    }

    // MARK: - Background Handoff Task

    /// Acquire a short 5.0-second background task bridging background/lock-screen handoff
    /// and end it cleanly BEFORE iOS's 30s expiration watchdog so mediaserverd audio keeps the app alive 24/24.
    private func beginBackgroundHandoffTask() {
        let now = CACurrentMediaTime()
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
            if self.wanted && !self.isFullyActive {
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
            // Still foreground-eligible here: prime BOTH audio layers BEFORE iOS completes backgrounding/lock!
            if self.isTreoActive && self.hasActiveGame {
                if !self.wanted || !self.isFullyActive {
                    self.startKeepalive()
                }
            }
        }
    }

    @objc private func onProtectedDataWillBecomeUnavailable() {
        // Fires specifically when the user presses Power/Lock or auto-lock engages.
        onSceneDidEnterBackground()
    }

    @objc func onSceneDidEnterBackground() {
        runOnMain { [weak self] in
            guard let self = self else { return }
            self.isInBackground = true
            self.startBackgroundTickTimerIfNeeded()

            // Short 5s handoff task on EVERY background / lock-screen transition
            self.beginBackgroundHandoffTask()

            if !DecadePiPManager.shared.isPiPActiveOrStarting {
                j2me_render_set_background(1)
            }

            if self.isTreoActive && self.hasActiveGame {
                if !self.wanted {
                    self.startKeepalive()
                } else if !self.isFullyActive {
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
            self.finalizeBackgroundTelemetryIfNeeded()
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
            self.finalizeBackgroundTelemetryIfNeeded()
            if self.isTreoActive && self.hasActiveGame {
                if !self.wanted {
                    self.startKeepalive()
                } else if !self.isFullyActive {
                    self.interrupted = false
                    self.interruptedAt = nil
                    self.ensurePlaying()
                }
            }
        }
    }

    // MARK: - Audio Session & Engine Notifications (Self-Healing Recovery)

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
                    guard let self = self, self.wanted, !self.isFullyActive else { return }
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
            if !self.interrupted && !self.isFullyActive {
                self.ensurePlaying()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    guard let self = self, self.wanted, !self.interrupted, !self.isFullyActive else { return }
                    self.ensurePlaying()
                }
            }
        }
    }

    @objc private func handleEngineConfigurationChange() {
        runOnMain { [weak self] in
            guard let self = self, self.wanted, !self.interrupted else { return }
            if let engine = self.audioEngine {
                engine.stop()
                engine.reset()
            }
            self.audioEngine = nil
            self.sourceNode = nil
            self.ensurePlaying()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self = self, self.wanted, !self.interrupted, !self.isFullyActive else { return }
                self.ensurePlaying()
            }
        }
    }

    @objc private func handleMediaServicesLost() {
        runOnMain { [weak self] in
            guard let self = self else { return }
            self.audioStatus = "media-services-lost"
            self.teardownAudioLayers()
        }
    }

    @objc private func handleMediaServicesReset() {
        runOnMain { [weak self] in
            guard let self = self, self.wanted else { return }
            self.teardownAudioLayers()
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
