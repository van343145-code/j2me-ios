import Combine
import Foundation
import UIKit
import WebKit

@MainActor
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: EmulatorSession?

    init(delegate: EmulatorSession) {
        self.delegate = delegate
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

@MainActor
final class EmulatorSession: NSObject, ObservableObject, WKNavigationDelegate {
    private enum State {
        case idle
        case starting
        case running
        case stopping
        case stopped
    }

    private static let zipMagic: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
    private static let startupTimeoutNanoseconds: UInt64 = 35_000_000_000
    private static let stopTimeoutNanoseconds: UInt64 = 2_000_000_000
    private static let fallbackLaunchNanoseconds: UInt64 = 3_500_000_000

    private static let keyCodes: Set<String> = [
        "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight",
        "Enter", "OK", "F1", "F2", "KeyE", "KeyR",
        "Digit0", "Digit1", "Digit2", "Digit3", "Digit4",
        "Digit5", "Digit6", "Digit7", "Digit8", "Digit9",
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "*", "#", "Star", "Hash", "SoftLeft", "SoftRight",
    ]

    @Published private(set) var isReady = false
    @Published private(set) var isDisplayVisible = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var pressedCodes: Set<String> = []

    private(set) var isTextEditing = false
    let webView: WKWebView

    private let gameURL: URL
    private let gameID: UUID
    private let onExit: () -> Void

    private var state: State = .idle
    private var isLaunched = false
    private var isPaused = false
    private var saveURL: URL?
    private var server: LoopbackServer?
    private var networkBridge: GameNetworkBridge?
    private var timeoutTask: Task<Void, Never>?
    private var stopCallbacks: [() -> Void] = []
    private var keySources: [String: Set<String>] = [:]
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(gameURL: URL, gameID: UUID, onExit: @escaping () -> Void) {
        self.gameURL = gameURL
        self.gameID = gameID
        self.onExit = onExit

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        webView.navigationDelegate = self
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
    }

    func start() {
        guard state == .idle else { return }
        state = .starting

        guard let resourceURL = Bundle.main.resourceURL else {
            errorMessage = "Không tìm thấy trình giả lập trong ứng dụng."
            finish()
            return
        }

        let runtimeURL = resourceURL.appendingPathComponent("Runtime/j2mejs", isDirectory: true)
        let classesURL = runtimeURL.appendingPathComponent("java/classes.jar")
        let certsURL = runtimeURL.appendingPathComponent("certs/_main.ks")

        let fm = FileManager.default
        guard fm.isReadableFile(atPath: certsURL.path) else {
            errorMessage = "Thiếu kho chứng chỉ của trình giả lập."
            finish()
            return
        }

        guard let handle = try? FileHandle(forReadingFrom: classesURL) else {
            errorMessage = "Thiếu tệp hệ thống Java của trình giả lập."
            finish()
            return
        }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 4),
              header == Data(Self.zipMagic) else {
            errorMessage = "Thiếu tệp hệ thống Java của trình giả lập."
            finish()
            return
        }

        let saveFileURL = gameURL.deletingLastPathComponent().appendingPathComponent("save.zip")
        self.saveURL = saveFileURL

        let loopback: LoopbackServer
        do {
            loopback = try LoopbackServer(root: runtimeURL, game: gameURL, save: saveFileURL)
        } catch {
            errorMessage = "Không mở được trình giả lập trên thiết bị này."
            finish()
            return
        }

        self.server = loopback
        webView.configuration.userContentController.add(WeakMessageHandler(delegate: self), name: "j2me")
        self.networkBridge = GameNetworkBridge(webView: webView)

        armTimeout("Trình giả lập không khởi động được.")

        loopback.start { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.state == .starting else { return }
                switch result {
                case .success(let url):
                    self.webView.load(URLRequest(url: url))
                case .failure:
                    self.errorMessage = "Không mở được trình giả lập trên thiết bị này."
                    self.finish()
                }
            }
        }
    }

    func setKey(_ code: String, pressed: Bool, source: String) {
        guard state == .running, Self.keyCodes.contains(code) else { return }

        var sources = keySources[code] ?? []
        let wasPressed = !sources.isEmpty

        if pressed {
            sources.insert(source)
        } else {
            sources.remove(source)
        }

        if sources.isEmpty {
            keySources.removeValue(forKey: code)
        } else {
            keySources[code] = sources
        }

        let isNowPressed = !sources.isEmpty
        pressedCodes = Set(keySources.keys)

        guard wasPressed != isNowPressed else { return }
        let action = isNowPressed ? "keyDown" : "keyUp"
        webView.evaluateJavaScript("window.Input.\(action)('\(code)');", completionHandler: nil)
    }

    func releaseAllKeys() {
        let codes = Array(keySources.keys)
        keySources.removeAll()
        pressedCodes.removeAll()

        for code in codes {
            webView.evaluateJavaScript("window.Input.keyUp('\(code)');", completionHandler: nil)
        }
    }

    func beginBackgroundTask() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "J2ME-NSV-AFK") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        let taskID = backgroundTask
        backgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(taskID)
    }

    func stop(onFinished: (() -> Void)? = nil) {
        if state == .stopped {
            onFinished?()
            return
        }

        if let onFinished {
            stopCallbacks.append(onFinished)
        }

        if state == .stopping {
            return
        }

        let wasRunning = (state == .running)
        state = .stopping

        releaseAllKeys()
        isReady = false
        isDisplayVisible = false
        networkBridge?.close()
        timeoutTask?.cancel()
        timeoutTask = nil

        guard wasRunning else {
            finish()
            return
        }

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.stopTimeoutNanoseconds)
            guard !Task.isCancelled else { return }
            self?.finish()
        }

        webView.callAsyncJavaScript(
            "return await window.j2meAPI.getSaveData();",
            arguments: [:],
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self, self.state == .stopping else { return }
            if case .success(let value) = result,
               let base64 = value as? String,
               let data = Data(base64Encoded: base64),
               data.starts(with: Self.zipMagic),
               let saveURL = self.saveURL {
                try? data.write(to: saveURL, options: .atomic)
            }
            self.finish()
        }
    }

    private func launchGame() {
        guard state == .starting || state == .running, !isLaunched else { return }
        isLaunched = true

        armTimeout("Game chưa khởi động được. Hãy kiểm tra tệp JAR.")

        webView.callAsyncJavaScript(
            "await window.nsvLaunch(); return true;",
            arguments: [:],
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self, self.state == .starting || self.state == .running else { return }
            if case .failure(let error) = result {
                print("[launchGame JS Error]: \(error)")
                self.errorMessage = "Game chưa khởi động được. Hãy kiểm tra tệp JAR."
                self.finish()
            }
        }
    }

    private func armTimeout(_ message: String) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.startupTimeoutNanoseconds)
            guard !Task.isCancelled, let self else { return }
            guard self.state == .starting else { return }
            self.errorMessage = message
            self.finish()
        }
    }

    private func finish() {
        guard state != .stopped else { return }
        state = .stopped

        isReady = false
        isDisplayVisible = false
        isTextEditing = false
        keySources.removeAll()
        pressedCodes.removeAll()

        timeoutTask?.cancel()
        timeoutTask = nil

        networkBridge?.close()
        networkBridge = nil

        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "j2me")
        webView.loadHTMLString("", baseURL: nil)

        server?.stop()
        server = nil
        endBackgroundTask()

        let callbacks = stopCallbacks
        stopCallbacks.removeAll()
        for callback in callbacks {
            callback()
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "j2me",
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            return
        }

        switch type {
        case "ready":
            if state == .starting {
                launchGame()
            }

        case "choicePresented":
            guard state == .starting else { return }
            timeoutTask?.cancel()
            timeoutTask = nil
            isDisplayVisible = true

        case "choiceCompleted":
            guard state == .starting else { return }
            isDisplayVisible = false
            armTimeout("Chương trình đã chọn chưa khởi động được.")

        case "gameReady":
            guard state == .starting || state == .running else { return }
            timeoutTask?.cancel()
            timeoutTask = nil
            state = .running
            isReady = true
            isDisplayVisible = true
            errorMessage = nil
            if isPaused {
                webView.evaluateJavaScript("window.j2meAPI.pause();", completionHandler: nil)
            }

        case "launchError":
            guard state == .starting || state == .running else { return }
            let msg = (body["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            errorMessage = (msg?.isEmpty == false) ? msg : "Game chưa khởi động được. Hãy kiểm tra tệp JAR."
            finish()

        case "jsError":
            let msg = (body["message"] as? String) ?? ""
            print("[J2ME JS ERROR]: \(msg)")

        case "saveDataWritten":
            guard state == .running || state == .stopping else { return }
            if let base64 = body["data"] as? String,
               let data = Data(base64Encoded: base64),
               data.starts(with: Self.zipMagic),
               let saveURL = self.saveURL {
                try? data.write(to: saveURL, options: .atomic)
            }

        case "textEditing":
            guard state == .running else { return }
            let active = (body["active"] as? Bool) ?? false
            isTextEditing = active
            if active {
                releaseAllKeys()
            }

        case "evalNative":
            guard state == .starting || state == .running else { return }
            networkBridge?.handle(body)

        case "exit":
            guard state == .starting || state == .running else { return }
            stop { [weak self] in
                self?.onExit()
            }

        default:
            break
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else {
            return .cancel
        }
        if url.absoluteString == "about:blank" {
            return .allow
        }
        if let host = url.host, host == "127.0.0.1" || host == "localhost" {
            return .allow
        }
        return .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.fallbackLaunchNanoseconds)
            guard let self, self.state == .starting, !self.isLaunched else { return }
            print("[iOS] Fallback trigger launchGame after 3.5s")
            self.launchGame()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationFailed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationFailed(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard state == .starting || state == .running else { return }
        errorMessage = "Trình giả lập đã dừng. Hãy mở lại game."
        finish()
    }

    private func navigationFailed(_ error: Error) {
        guard state == .starting || state == .running else { return }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        errorMessage = "Không tải được trình giả lập: \(error.localizedDescription)"
        finish()
    }
}
