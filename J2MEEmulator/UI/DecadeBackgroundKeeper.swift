//
//  DecadeBackgroundKeeper.swift
//  J2MEEmulator
//
//  Engine chạy ngầm 24/7 chuẩn Spotify / Apple Music cho J2ME iOS:
//  - Sử dụng AVAudioSession .playback ĐỘC QUYỀN kết hợp MPNowPlayingInfoCenter &
//    MPRemoteCommandCenter để iOS RunningBoard cấp mức ưu tiên Jetsam cao nhất
//    (MediaPlayback / NowPlaying Priority 120 — tương đương Apple Music & Spotify).
//  - Sử dụng AVAudioEngine + AVAudioSourceNode (CoreAudio AURemoteIO phần cứng)
//    phát liên tục không ngắt quãng sóng hạ âm 18 Hz (-56 dB, hoàn toàn im lặng với
//    tai người & loa điện thoại), kèm AVAudioPlayer dự phòng.
//  - Hiển thị trực tiếp trạng thái "Đang treo: <Tên Game>" trên màn hình khóa để
//    xác nhận iOS đang giữ tiến trình sống liên tục.
//  - Ngắt render CoreGraphics & OpenGL ES và hạ nhịp Display xuống ~8 wakeups/giây
//    khi tắt màn hình để không bao giờ chạm giới hạn EXC_RESOURCE CPU / WAKEUPS.
//

import UIKit
import AVFoundation
import MediaPlayer
import UserNotifications
import CoreLocation
import Network

// ============================================================
// MARK: - Decade Location Keep-Alive (Định Vị BTS 0% Hao Pin GPS)
// ============================================================

final class DecadeLocationKeeper: NSObject, CLLocationManagerDelegate {
    static let shared = DecadeLocationKeeper()

    private var locationManager: CLLocationManager?
    private(set) var isRunning = false

    /// Mặc định kích hoạt chế độ Định Vị BTS tiết kiệm pin (True) theo yêu cầu người dùng
    var isLocationModeActive: Bool {
        get {
            if UserDefaults.standard.object(forKey: "decade_use_location_keepalive") == nil {
                return true // Mặc định bật chế độ Định Vị BTS
            }
            return UserDefaults.standard.bool(forKey: "decade_use_location_keepalive")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "decade_use_location_keepalive")
            if newValue {
                start()
            } else {
                stop()
            }
        }
    }

    private func setupLocationManager() {
        guard locationManager == nil else { return }
        let manager = CLLocationManager()
        manager.delegate = self
        // Độ chính xác 3km: Chỉ dựa vào trạm sóng di động BTS, TẮT HOÀN TOÀN chip GPS vệ tinh (0% hao pin GPS)
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = 100.0
        manager.pausesLocationUpdatesAutomatically = false
        if #available(iOS 9.0, *) {
            manager.allowsBackgroundLocationUpdates = true
        }
        if #available(iOS 11.0, *) {
            manager.showsBackgroundLocationIndicator = false
        }
        self.locationManager = manager
    }

    func requestPermissionIfNeeded() {
        setupLocationManager()
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager?.authorizationStatus ?? .notDetermined
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        if status == .notDetermined {
            locationManager?.requestAlwaysAuthorization()
        }
    }

    func start() {
        setupLocationManager()
        guard let manager = locationManager else { return }
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = manager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        if status == .notDetermined {
            manager.requestAlwaysAuthorization()
        }
        manager.startUpdatingLocation()
        isRunning = true
        print("[DecadeLocationKeeper] Started BTS Location Keepalive (0% GPS power, No Audio)")
    }

    func stop() {
        locationManager?.stopUpdatingLocation()
        isRunning = false
        print("[DecadeLocationKeeper] Stopped BTS Location Keepalive")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Tín hiệu định vị trạm BTS giữ tiến trình sống liên tục
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Bỏ qua lỗi định vị
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if isLocationModeActive {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if isLocationModeActive {
            manager.startUpdatingLocation()
        }
    }
}

// ============================================================
// MARK: - Decade Network Keep-Alive (Giữ Mạng 24/24 - Chống Ngủ Wi-Fi & 4G/5G)
// ============================================================

final class DecadeNetworkKeeper {
    static let shared = DecadeNetworkKeeper()

    private var heartbeatTimer: DispatchSourceTimer?
    private var session: URLSession?
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.decade.network.monitor")
    private(set) var isRunning = false
    private(set) var isNetworkConnected = true
    private var lastProbeSuccessTime: TimeInterval = 0

    // Các máy chủ kiểm tra kết nối toàn cầu phản hồi siêu tốc (HTTP 204 No Content / 0 byte tải về)
    private let keepaliveEndpoints: [String] = [
        "http://connectivitycheck.gstatic.com/generate_204",
        "http://captive.apple.com/hotspot-detect.html",
        "http://cp.cloudflare.com/generate_204"
    ]
    private var endpointIndex = 0

    private init() {
        setupSession()
    }

    private func setupSession() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 12.0
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        if #available(iOS 11.0, *) {
            config.multipathServiceType = .handover
        }
        self.session = URLSession(configuration: config)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startPathMonitor()
        startHeartbeat()
        print("[DecadeNetworkKeeper] ĐÃ BẬT Giữ Mạng 24/24 — Chống ngủ Wi-Fi & Chống đứt 4G/5G CGNAT.")
    }

    func stop() {
        isRunning = false
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        print("[DecadeNetworkKeeper] ĐÃ TẮT Giữ Mạng 24/24.")
    }

    private func startPathMonitor() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let connected = (path.status == .satisfied)
            self.isNetworkConnected = connected
            let isCellular = path.isExpensive || path.usesInterfaceType(.cellular)
            let isWiFi = path.usesInterfaceType(.wifi)
            print("[DecadeNetworkKeeper] Đường truyền mạng: \(connected ? "ONLINE" : "OFFLINE") [WiFi=\(isWiFi), 4G/5G=\(isCellular)]")
            if connected {
                self.sendProbe()
            }
        }
        monitor.start(queue: monitorQueue)
        self.pathMonitor = monitor
    }

    private func startHeartbeat() {
        guard heartbeatTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        // Ping đều đặn mỗi 15 giây:
        // 1. Ngăn iOS tắt / sleep chip Wi-Fi khi tắt màn hình khóa máy (Wi-Fi Power Save off)
        // 2. Ngăn nhà mạng (Viettel, Vina, Mobi) ngắt cổng NAT (CGNAT) khi game đứng yên auto-farm
        // 3. Duy trì luồng IP liên tục 24/24 không bao giờ bị đứt
        timer.schedule(deadline: .now() + 2.0, repeating: 15.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.sendProbe()
        }
        timer.resume()
        self.heartbeatTimer = timer
    }

    private func sendProbe() {
        let endpoint = keepaliveEndpoints[endpointIndex % keepaliveEndpoints.count]
        endpointIndex += 1

        guard let url = URL(string: endpoint) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        session?.dataTask(with: request) { [weak self] _, response, _ in
            guard let self = self else { return }
            if let http = response as? HTTPURLResponse, (200...204).contains(http.statusCode) {
                self.lastProbeSuccessTime = Date().timeIntervalSince1970
            }
        }.resume()
    }
}

final class DecadeBackgroundKeeper: NSObject, AVAudioPlayerDelegate {
    static let shared = DecadeBackgroundKeeper()

    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var audioPlayer: AVAudioPlayer?
    private var watchdogTimer: DispatchSourceTimer?
    private var ramCleanTimer: DispatchSourceTimer?
    private var remoteCommandsConfigured = false
    private var currentGameName: String = "J2ME Game"
    private var bgTaskID: UIBackgroundTaskIdentifier = .invalid
    private let audioQueue = DispatchQueue(label: "com.decade.keepalive.audio", qos: .userInteractive)

    private func beginAppBackgroundTask() {
        guard bgTaskID == .invalid else { return }
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "DecadeKeepAliveTransition") { [weak self] in
            guard let self = self else { return }
            print("[DecadeBackgroundKeeper] Background task expiring, ending cleanly...")
            self.endAppBackgroundTask()
        }
    }

    private func endAppBackgroundTask() {
        if bgTaskID != .invalid {
            let task = bgTaskID
            bgTaskID = .invalid
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    var isTreoActive: Bool {
        get {
            if UserDefaults.standard.object(forKey: "decade_treo_tat_man") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "decade_treo_tat_man")
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
        if isTreoActive {
            startKeepalive()
        }
        if isAutoCleanRamActive {
            startAutoRamCleaner()
        }
    }

    private func setupNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
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
    }

    func updateNowPlayingGame(name: String) {
        currentGameName = name.isEmpty ? "J2ME Game" : name
        if isTreoActive {
            updateNowPlayingInfo()
        }
    }

    func setTreoActive(_ active: Bool) {
        UserDefaults.standard.set(active, forKey: "decade_treo_tat_man")

        if active {
            startKeepalive()
            UIApplication.shared.isIdleTimerDisabled = true
            print("[DecadeBackgroundKeeper] Treo tắt màn & Chạy nền 24/7: ĐÃ BẬT")
        } else {
            stopWatchdog()
            stopKeepalive()
            UIApplication.shared.isIdleTimerDisabled = false
            print("[DecadeBackgroundKeeper] Treo tắt màn: ĐÃ TẮT")
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

    /// Thực thi dọn dẹp RAM thực sự: ép MiniJVM GC, dọn bộ đệm ảnh CoreGraphics,
    /// xoá URLCache và trả trang nhớ malloc về kernel iOS (chống Jetsam kill khi treo lâu).
    func performRamCleanup(completion: ((Double, Double) -> Void)? = nil) {
        let beforeMB = Double(jvm_bridge_get_used_ram_kb()) / 1024.0
        // Chỉ chạy dọn dẹp sâu nếu bấm thủ công hoặc RAM thực sự cao (>150MB) để tránh đơ/khựng khung hình khi treo game
        guard completion != nil || beforeMB > 150.0 else { return }

        URLCache.shared.removeAllCachedResponses()
        GameViewController.purgeInactiveSlotFrames()
        DecadePiPManager.shared.purgeBuffers()

        DispatchQueue.global(qos: .utility).async {
            jvm_bridge_clean_ram()
            Thread.sleep(forTimeInterval: 0.4)
            jvm_bridge_clean_ram()
            let afterMB = Double(jvm_bridge_get_used_ram_kb()) / 1024.0
            print(String(format: "[RAM Cleaner] %.1f MB -> %.1f MB", beforeMB, afterMB))
            DispatchQueue.main.async {
                self.updateNowPlayingInfo()
                if let cb = completion {
                    cb(beforeMB, afterMB)
                }
            }
        }
    }

    private func startAutoRamCleaner() {
        guard ramCleanTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 60.0, repeating: 60.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isAutoCleanRamActive else { return }
            self.performRamCleanup(completion: nil)
        }
        timer.resume()
        ramCleanTimer = timer
    }

    private func stopAutoRamCleaner() {
        ramCleanTimer?.cancel()
        ramCleanTimer = nil
    }

    func startKeepalive() {
        setupRemoteCommandsIfNeeded()

        // 0. Cấp quyền chạy nền vô thời hạn trên iOS (BKSProcessAssertion / TrollStore / Enterprise)
        decade_acquire_unlimited_background_assertion()

        // 1. Luôn kích hoạt Audio Pipeline bất tử (AVAudioPlayer loop) trên hàng đợi nền
        // để mediaserverd cấp assertion chạy nền 24/24 không bao giờ bị iOS đóng băng (freeze)
        audioQueue.async { [weak self] in
            self?.startAudioPipeline(forceRecreate: false)
        }

        // 2. Kích hoạt song song Định vị BTS nếu bật
        if DecadeLocationKeeper.shared.isLocationModeActive {
            DecadeLocationKeeper.shared.start()
        } else {
            DecadeLocationKeeper.shared.stop()
        }

        // 3. Kích hoạt Giữ Mạng 24/24 (Anti-WiFi Sleep & Anti-CGNAT Drop)
        DecadeNetworkKeeper.shared.start()

        // 4. Kích hoạt Background Task duy trì chuyển cảnh
        beginAppBackgroundTask()

        DispatchQueue.main.async { [weak self] in
            self?.updateNowPlayingInfo()
        }
        startWatchdog()
    }

    func stopKeepalive() {
        decade_release_unlimited_background_assertion()
        DecadeLocationKeeper.shared.stop()
        DecadeNetworkKeeper.shared.stop()
        endAppBackgroundTask()
        stopWatchdog()
        audioQueue.sync { [weak self] in
            self?.stopAudioPipeline()
        }
        DispatchQueue.main.async {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            if #available(iOS 13.0, *) {
                MPNowPlayingInfoCenter.default().playbackState = .stopped
            }
            self.clearLockScreenNotification()
        }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("[DecadeBackgroundKeeper] Deactivate audio error: \(error)")
        }
    }

    private func stopAudioPipeline() {
        audioEngine?.stop()
        audioEngine = nil
        sourceNode = nil
        audioPlayer?.stop()
        audioPlayer = nil
    }

    /// Xóa sạch mọi thông báo chạy ngầm khi vào Foreground hoặc tắt/thoát app
    func clearLockScreenNotification() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: ["decade_bg_status"])
        center.removePendingNotificationRequests(withIdentifiers: ["decade_bg_status"])
    }

    @objc func onSceneWillResignActive() {
        if isTreoActive {
            decade_acquire_unlimited_background_assertion()
            audioQueue.async { [weak self] in
                self?.startAudioPipeline(forceRecreate: false)
            }
            if DecadeLocationKeeper.shared.isLocationModeActive {
                DecadeLocationKeeper.shared.start()
            }
            DecadeNetworkKeeper.shared.start()
            beginAppBackgroundTask()
            DispatchQueue.main.async { [weak self] in
                self?.updateNowPlayingInfo()
            }
        }
    }

    @objc func onSceneDidEnterBackground() {
        if !DecadePiPManager.shared.isPiPActive {
            // Bật chế độ ngắt render đồ hoạ CoreGraphics/GL
            j2me_render_set_background(1)
        }
        if isTreoActive {
            startKeepalive()
            postLockScreenNotification(force: true)
        }
        if isAutoCleanRamActive {
            performRamCleanup(completion: nil)
        }
    }

    @objc func onSceneWillEnterForeground() {
        j2me_render_set_background(0)
        endAppBackgroundTask()
        clearLockScreenNotification()
        if isTreoActive {
            startKeepalive()
        }
    }

    @objc private func handleAppWillResignActive() {
        onSceneWillResignActive()
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
        if isTreoActive {
            startKeepalive()
        }
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard isTreoActive,
              let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .began {
            beginAppBackgroundTask()
        } else if type == .ended {
            audioQueue.async { [weak self] in
                guard let self = self, self.isTreoActive else { return }
                self.startAudioPipeline(forceRecreate: true)
                self.endAppBackgroundTask()
                DispatchQueue.main.async {
                    self.updateNowPlayingInfo()
                }
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard isTreoActive else { return }
        audioQueue.async { [weak self] in
            guard let self = self, self.isTreoActive else { return }
            if self.audioPlayer?.isPlaying != true {
                self.startFallbackAudioPlayer()
            }
            DispatchQueue.main.async {
                self.updateNowPlayingInfo()
            }
        }
    }

    @objc private func handleMediaServicesReset() {
        guard isTreoActive else { return }
        audioQueue.async { [weak self] in
            guard let self = self, self.isTreoActive else { return }
            self.startAudioPipeline(forceRecreate: true)
            DispatchQueue.main.async {
                self.updateNowPlayingInfo()
            }
        }
    }

    @objc private func handleEngineConfigurationChange() {
        guard isTreoActive else { return }
        audioQueue.async { [weak self] in
            guard let self = self, self.isTreoActive else { return }
            if self.audioPlayer?.isPlaying != true {
                self.startFallbackAudioPlayer()
            }
            DispatchQueue.main.async {
                self.updateNowPlayingInfo()
            }
        }
    }

    private var isAudioRunning: Bool {
        if let eng = audioEngine, eng.isRunning { return true }
        if let pl = audioPlayer, pl.isPlaying { return true }
        return false
    }

    private func setupRemoteCommandsIfNeeded() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true
        UIApplication.shared.beginReceivingRemoteControlEvents()

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.startAudioPipeline(forceRecreate: false)
            self.updateNowPlayingInfo()
            return .success
        }
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            // Giữ kết nối luôn sống ngay cả khi bấm nhầm nút trên màn hình khóa
            guard let self = self else { return .commandFailed }
            if self.isTreoActive {
                self.startAudioPipeline(forceRecreate: false)
                self.updateNowPlayingInfo()
            }
            return .success
        }
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    /// Tạo ảnh thẻ thông tin trạng thái treo nền (RAM, CPU, Tab, Đang chạy nền) chuẩn như GaEmulator
    func generateNotificationCardImage(ramMB: Double, cpuPercent: Double, tabCount: Int, timeString: String) -> UIImage {
        let size = CGSize(width: 480, height: 210)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext

            // 1. Nền thẻ bo góc đen xám hiện đại (#12161E)
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 24)
            UIColor(red: 0.07, green: 0.09, blue: 0.12, alpha: 1.0).setFill()
            path.fill()

            // Viền mỏng tinh tế (#21262D)
            UIColor(red: 0.20, green: 0.24, blue: 0.30, alpha: 1.0).setStroke()
            path.lineWidth = 1.5
            path.stroke()

            // 2. Header: 🎮 Tên Game (Trái) & "Đang chạy nền" (Xanh lá - Phải)
            let headerFont = UIFont.systemFont(ofSize: 19, weight: .bold)
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: UIColor.white
            ]
            let headerText = "🎮 \(currentGameName)"
            (headerText as NSString).draw(at: CGPoint(x: 24, y: 18), withAttributes: headerAttrs)

            let statusFont = UIFont.systemFont(ofSize: 15, weight: .semibold)
            let statusAttrs: [NSAttributedString.Key: Any] = [
                .font: statusFont,
                .foregroundColor: UIColor(red: 0.18, green: 0.80, blue: 0.44, alpha: 1.0)
            ]
            let statusText = "Đang chạy nền"
            let statusSize = (statusText as NSString).size(withAttributes: statusAttrs)
            (statusText as NSString).draw(at: CGPoint(x: size.width - statusSize.width - 24, y: 20), withAttributes: statusAttrs)

            // Đường kẻ ngang phân cách mỏng
            cg.setStrokeColor(UIColor(red: 0.16, green: 0.20, blue: 0.26, alpha: 0.8).cgColor)
            cg.setLineWidth(1.0)
            cg.move(to: CGPoint(x: 24, y: 56))
            cg.addLine(to: CGPoint(x: size.width - 24, y: 56))
            cg.strokePath()

            // 3. 3 Cột chỉ số: RAM, CPU, Tab
            let colWidth = (size.width - 48) / 3.0
            let labelFont = UIFont.systemFont(ofSize: 13, weight: .medium)
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: labelFont,
                .foregroundColor: UIColor(red: 0.55, green: 0.60, blue: 0.68, alpha: 1.0)
            ]
            let valueFont = UIFont.monospacedDigitSystemFont(ofSize: 26, weight: .bold)
            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: valueFont,
                .foregroundColor: UIColor.white
            ]

            // Cột 1: RAM
            ("RAM" as NSString).draw(at: CGPoint(x: 24, y: 68), withAttributes: labelAttrs)
            let ramStr = "\(Int(ramMB)) MB"
            (ramStr as NSString).draw(at: CGPoint(x: 24, y: 92), withAttributes: valueAttrs)

            // Cột 2: CPU
            let col2X = 24 + colWidth
            ("CPU" as NSString).draw(at: CGPoint(x: col2X, y: 68), withAttributes: labelAttrs)
            let cpuStr = "\(Int(cpuPercent))%"
            (cpuStr as NSString).draw(at: CGPoint(x: col2X, y: 92), withAttributes: valueAttrs)

            // Cột 3: Tab
            let col3X = 24 + colWidth * 2
            ("Tab" as NSString).draw(at: CGPoint(x: col3X, y: 68), withAttributes: labelAttrs)
            let tabStr = "\(tabCount)"
            (tabStr as NSString).draw(at: CGPoint(x: col3X, y: 92), withAttributes: valueAttrs)

            // 4. Footer: Cập nhật giờ phút giây
            let footerFont = UIFont.systemFont(ofSize: 12, weight: .regular)
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: footerFont,
                .foregroundColor: UIColor(red: 0.45, green: 0.50, blue: 0.58, alpha: 1.0)
            ]
            let footerText = "Cập nhật \(timeString)"
            (footerText as NSString).draw(at: CGPoint(x: 24, y: 172), withAttributes: footerAttrs)
        }
    }

    private var lastNotificationPostTime: TimeInterval = 0

    /// Đẩy thông báo thẻ trạng thái RAM/CPU/Tab trực tiếp lên thanh thông báo / màn hình khóa khi treo nền
    func postLockScreenNotification(force: Bool = false) {
        guard isTreoActive else { return }

        let now = Date().timeIntervalSince1970
        // Throttle updates: Không bao giờ spam thông báo liên tục!
        // Chỉ post khi mới vào nền (force = true) hoặc ít nhất 5 phút/lần
        if !force && (now - lastNotificationPostTime) < 300.0 {
            return
        }
        lastNotificationPostTime = now

        let ramMB = Double(jvm_bridge_get_used_ram_kb()) / 1024.0
        let cpu = jvm_bridge_get_cpu_usage_percent()
        let tabs = GameViewController.activeTabCount

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm:ss"
        let timeString = formatter.string(from: Date())

        let cardImage = generateNotificationCardImage(ramMB: ramMB, cpuPercent: cpu, tabCount: tabs, timeString: timeString)

        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "🎮 \(currentGameName)"
        content.subtitle = "Đang chạy nền"
        content.body = "RAM: \(Int(ramMB)) MB   •   CPU: \(Int(cpu))%   •   Tab: \(tabs)\nCập nhật \(timeString)"
        content.sound = nil // Hoàn toàn êm ái, không rung, không phát tiếng làm phiền

        // QUAN TRỌNG: Thiết lập passive để thông báo ghim cố định âm thầm trên màn hình khóa/trung tâm thông báo,
        // TUYỆT ĐỐI KHÔNG rơi banner popup từ trên xuống ("khong thong bao xuog lien tuục")
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .passive
            content.relevanceScore = 0.0
        }

        let tempDir = FileManager.default.temporaryDirectory
        let imgURL = tempDir.appendingPathComponent("decade_status_card.png")
        if let pngData = cardImage.pngData() {
            try? pngData.write(to: imgURL)
            if let attachment = try? UNNotificationAttachment(identifier: "status_card", url: imgURL, options: nil) {
                content.attachments = [attachment]
            }
        }

        let req = UNNotificationRequest(identifier: "decade_bg_status", content: content, trigger: nil)
        center.add(req, withCompletionHandler: nil)
    }

    private var cachedCardImage: UIImage?
    private var lastCardImageRenderTime: TimeInterval = 0

    func updateNowPlayingInfo() {
        let ramMB = Double(jvm_bridge_get_used_ram_kb()) / 1024.0
        let cpu = jvm_bridge_get_cpu_usage_percent()
        let tabs = GameViewController.activeTabCount

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm:ss"
        let timeString = formatter.string(from: Date())

        let now = Date().timeIntervalSince1970
        let cardImage: UIImage
        if let cached = cachedCardImage, (now - lastCardImageRenderTime) < 60.0 {
            cardImage = cached
        } else {
            cardImage = generateNotificationCardImage(ramMB: ramMB, cpuPercent: cpu, tabCount: tabs, timeString: timeString)
            cachedCardImage = cardImage
            lastCardImageRenderTime = now
        }

        let netStatus = DecadeNetworkKeeper.shared.isNetworkConnected ? "Mạng 24/24: OK" : "Mất mạng"
        let albumTitle = "Treo 24/24 Bất Tử • \(netStatus) • \(timeString)"

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: "🎮 \(currentGameName)",
            MPMediaItemPropertyArtist: "RAM: \(Int(ramMB)) MB   •   CPU: \(Int(cpu))%   •   Tab: \(tabs)",
            MPMediaItemPropertyAlbumTitle: albumTitle,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        let artwork = MPMediaItemArtwork(boundsSize: cardImage.size) { _ in cardImage }
        info[MPMediaItemPropertyArtwork] = artwork

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        if #available(iOS 13.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = .playing
        }
        // Thẻ trạng thái RAM/CPU/Tab được ghim cố định qua MPNowPlayingInfoCenter trên màn hình khóa.
        // Tuyệt đối không dùng UNUserNotificationCenter ở đây để không làm nhảy banner thông báo liên tục!
    }

    /// Khởi động pipeline âm thanh kép giữ tiến trình sống 24/7 xuyên suốt không ngắt nghỉ:
    /// 1. AVAudioPlayer chạy vòng lặp vô tận silent.wav do mediaserverd quản lý độc quyền.
    /// 2. AVAudioEngine + AVAudioSourceNode hạ âm 18 Hz (-56 dB) phần cứng CoreAudio.
    /// Kết hợp đồng thời đảm bảo iOS RunningBoard không bao giờ kill tiến trình hay ngắt kết nối socket!
    private func startAudioPipeline(forceRecreate: Bool) {
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback kết hợp .mixWithOthers + Bluetooth + AirPlay để vừa giữ keepalive 24/7,
            // vừa không bị gián đoạn khi người dùng nghe Spotify/YouTube hay đổi tai nghe AirPods
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP, .allowAirPlay])
            try session.setActive(true, options: [])

            if forceRecreate {
                audioEngine?.stop()
                audioEngine = nil
                sourceNode = nil
                audioPlayer?.stop()
                audioPlayer = nil
            }

            // 1. Luôn kích hoạt AVAudioPlayer chạy nền liên tục (vòng lặp vô tận -1)
            startFallbackAudioPlayer()

            // 2. Kích hoạt song song AVAudioEngine hạ âm chỉ khi AVAudioPlayer chưa chạy được
            if audioPlayer?.isPlaying != true {
                if audioEngine == nil {
                    _ = startRealtimeAudioEngine()
                } else if let eng = audioEngine, !eng.isRunning {
                    try? eng.start()
                }
            }
        } catch {
            print("[DecadeBackgroundKeeper] Audio pipeline error: \(error) — ensuring fallback player runs")
            startFallbackAudioPlayer()
        }
    }

    private func startRealtimeAudioEngine() -> Bool {
        let engine = AVAudioEngine()
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return false
        }

        // Continuous 18 Hz sub-audible sine wave at amplitude 0.0015 (-56 dB):
        // Completely inaudible to human ears & iPhone speakers, yet continuous non-zero PCM
        // so mediaserverd AURemoteIO hardware pipeline NEVER drops our background assertion!
        var phase: Double = 0.0
        let phaseIncrement = 2.0 * Double.pi * 18.0 / sampleRate
        let amplitude: Float = 0.0015

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let sample = Float(sin(phase)) * amplitude
                phase += phaseIncrement
                if phase >= 2.0 * Double.pi {
                    phase -= 2.0 * Double.pi
                }
                for buffer in ablPointer {
                    if let mData = buffer.mData {
                        let ptr = mData.assumingMemoryBound(to: Float.self)
                        ptr[frame] = sample
                    }
                }
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1.0
        engine.prepare()

        do {
            try engine.start()
            self.audioEngine = engine
            self.sourceNode = node
            print("[DecadeBackgroundKeeper] AVAudioEngine AURemoteIO 18Hz keepalive RUNNING (\(sampleRate) Hz).")
            return true
        } catch {
            print("[DecadeBackgroundKeeper] AVAudioEngine start failed: \(error)")
            engine.stop()
            return false
        }
    }

    private func startFallbackAudioPlayer() {
        do {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP, .allowAirPlay])
            try? session.setActive(true, options: [])

            if audioPlayer == nil {
                // Ưu tiên nạp file silent.wav trong App Bundle
                var player: AVAudioPlayer? = nil
                if let bundleURL = Bundle.main.url(forResource: "silent", withExtension: "wav") {
                    player = try? AVAudioPlayer(contentsOf: bundleURL)
                }
                if player == nil {
                    player = try? AVAudioPlayer(data: createSubaudible16HzWavData())
                }
                audioPlayer = player
                audioPlayer?.delegate = self
                audioPlayer?.numberOfLoops = -1
                audioPlayer?.volume = 0.05
                audioPlayer?.prepareToPlay()
            }
            if audioPlayer?.isPlaying == false {
                let ok = audioPlayer?.play() ?? false
                print("[DecadeBackgroundKeeper] Continuous AVAudioPlayer play=\(ok)")
            }
        }
    }

    // AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if isTreoActive {
            audioQueue.async { [weak self] in
                self?.audioPlayer?.play()
            }
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if isTreoActive {
            audioQueue.async { [weak self] in
                self?.startAudioPipeline(forceRecreate: true)
            }
        }
    }

    /// Watchdog tần số thấp (10 giây/lần = 0.1 wakeup/giây) đảm bảo keepalive luôn chạy xuyên suốt.
    private func startWatchdog() {
        guard watchdogTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 10.0, repeating: 10.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isTreoActive else { return }

            // 0. Duy trì quyền chạy nền vô thời hạn trên iOS
            decade_acquire_unlimited_background_assertion()

            // 1. Luôn bảo đảm Audio Pipeline (AVAudioPlayer loop) đang phát
            self.audioQueue.async { [weak self] in
                guard let self = self, self.isTreoActive else { return }
                if self.audioPlayer?.isPlaying != true {
                    print("[DecadeBackgroundKeeper] Watchdog: AudioPlayer not playing, resuming...")
                    self.startFallbackAudioPlayer()
                }
            }

            // 2. Bảo đảm Location Keeper đang chạy nếu được kích hoạt
            if DecadeLocationKeeper.shared.isLocationModeActive {
                if !DecadeLocationKeeper.shared.isRunning {
                    DecadeLocationKeeper.shared.start()
                }
            }

            // 3. Bảo đảm Network Keeper đang giữ mạng 24/24
            if !DecadeNetworkKeeper.shared.isRunning {
                DecadeNetworkKeeper.shared.start()
            }

            // 4. Bảo đảm Background Task Transition luôn có hiệu lực
            if self.bgTaskID == .invalid {
                self.beginAppBackgroundTask()
            }

            DispatchQueue.main.async {
                self.updateNowPlayingInfo()
            }
        }
        timer.resume()
        watchdogTimer = timer
    }

    private func stopWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }

    private func createSubaudible16HzWavData() -> Data {
        let sampleRate: Int32 = 44100
        let channels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let numSamples: Int32 = sampleRate * 10
        let dataSize: Int32 = numSamples * Int32(channels) * Int32(bitsPerSample / 8)
        let totalSize: Int32 = 36 + dataSize

        var data = Data()
        data.reserveCapacity(Int(totalSize + 8))
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        data.append(withUnsafeBytes(of: totalSize.littleEndian) { Data($0) })
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45])
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])
        let fmtSize: Int32 = 16
        data.append(withUnsafeBytes(of: fmtSize.littleEndian) { Data($0) })
        let pcmFormat: Int16 = 1
        data.append(withUnsafeBytes(of: pcmFormat.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        let byteRate: Int32 = sampleRate * Int32(channels) * Int32(bitsPerSample / 8)
        data.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        let blockAlign: Int16 = channels * (bitsPerSample / 8)
        data.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        data.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })

        let twoPiF = 2.0 * Double.pi * 16.0 / Double(sampleRate)
        for i in 0..<numSamples {
            let sample = Int16((45.0 * sin(twoPiF * Double(i))).rounded())
            data.append(withUnsafeBytes(of: sample.littleEndian) { Data($0) })
        }
        return data
    }
}
