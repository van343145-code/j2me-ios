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
final class EmulatorSession: NSObject, WKNavigationDelegate {
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
    private static let fallbackLaunchNanoseconds: UInt64 = 3_000_000_000

    let game: GameEntry
    let slotIndex: Int
    var config: GameConfig
    var virtualSize: VirtualSize
    let webView: WKWebView

    private(set) var isReady = false
    private(set) var errorMessage: String?

    var onStateChanged: (() -> Void)?
    var onExitRequested: (() -> Void)?

    private let gameURL: URL
    private let saveURL: URL
    private let proxyProvider: @MainActor () -> ProxyInfo?

    private var state: State = .idle
    private var isLaunched = false
    private var isBackgrounded = false
    private var server: LoopbackServer?
    private var networkBridge: GameNetworkBridge?
    private var timeoutTask: Task<Void, Never>?
    private var stopCallbacks: [() -> Void] = []

    init(
        game: GameEntry,
        slotIndex: Int,
        gameURL: URL,
        saveURL: URL,
        config: GameConfig,
        virtualSize: VirtualSize,
        proxyProvider: @escaping @MainActor () -> ProxyInfo?
    ) {
        self.game = game
        self.slotIndex = slotIndex
        self.gameURL = gameURL
        self.saveURL = saveURL
        self.config = config
        self.virtualSize = virtualSize
        self.proxyProvider = proxyProvider

        let webConfig = WKWebViewConfiguration()
        webConfig.websiteDataStore = .nonPersistent()
        webConfig.allowsInlineMediaPlayback = true
        webConfig.mediaTypesRequiringUserActionForPlayback = []

        self.webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 240, height: 320), configuration: webConfig)
        super.init()

        webView.navigationDelegate = self
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = true
        webView.backgroundColor = .black
    }

    func start() {
        guard state == .idle else { return }
        state = .starting
        errorMessage = nil
        onStateChanged?()

        guard let resourceURL = Bundle.main.resourceURL else {
            fail("Không tìm thấy trình giả lập trong ứng dụng.")
            return
        }

        let runtimeURL = resourceURL.appendingPathComponent("Runtime/j2mejs", isDirectory: true)
        let classesURL = runtimeURL.appendingPathComponent("java/classes.jar")
        let certsURL = runtimeURL.appendingPathComponent("certs/_main.ks")

        let fm = FileManager.default
        guard fm.isReadableFile(atPath: certsURL.path) else {
            fail("Thiếu kho chứng chỉ của trình giả lập.")
            return
        }
        guard fm.isReadableFile(atPath: classesURL.path) else {
            fail("Thiếu tệp hệ thống Java của trình giả lập.")
            return
        }
        guard fm.isReadableFile(atPath: gameURL.path) else {
            fail("Không tìm thấy tệp JAR của game.")
            return
        }

        let loopback: LoopbackServer
        do {
            loopback = try LoopbackServer(root: runtimeURL, game: gameURL, save: saveURL)
        } catch {
            fail("Không mở được máy chủ nội bộ: \(error.localizedDescription)")
            return
        }

        self.server = loopback
        webView.configuration.userContentController.add(WeakMessageHandler(delegate: self), name: "j2me")
        self.networkBridge = GameNetworkBridge(webView: webView, proxyProvider: proxyProvider)

        armTimeout("Trình giả lập không khởi động được.")

        loopback.start { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.state == .starting else { return }
                switch result {
                case .success(let url):
                    self.webView.load(URLRequest(url: url))
                case .failure(let err):
                    self.fail("Không mở được máy chủ nội bộ: \(err.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Key Input (Exact MIDP keycodes from NstKeyboard)

    func rawKeyDown(_ code: Int) {
        guard state == .running else { return }
        webView.evaluateJavaScript("window.Input && window.Input.rawKeyDown(\(code));", completionHandler: nil)
    }

    func rawKeyUp(_ code: Int) {
        guard state == .running else { return }
        webView.evaluateJavaScript("window.Input && window.Input.rawKeyUp(\(code));", completionHandler: nil)
    }

    func rawKeyRepeat(_ code: Int) {
        guard state == .running else { return }
        webView.evaluateJavaScript("window.Input && window.Input.rawKeyRepeat(\(code));", completionHandler: nil)
    }

    func releaseAllKeys() {
        guard state == .running || state == .starting else { return }
        webView.evaluateJavaScript("window.Input && window.Input.releaseAll();", completionHandler: nil)
    }

    // MARK: - Display Config & Background Throttle

    func applyConfig(_ newConfig: GameConfig, virtualSize newSize: VirtualSize? = nil) {
        self.config = newConfig
        if let newSize { self.virtualSize = newSize }
        pushConfigToWebView()
    }

    func setBackgrounded(_ bg: Bool) {
        guard isBackgrounded != bg else { return }
        isBackgrounded = bg
        guard state == .running || state == .starting else { return }
        webView.evaluateJavaScript("window.nstSetBackground && window.nstSetBackground(\(bg ? "true" : "false"));", completionHandler: nil)
    }

    func disconnectSockets() {
        networkBridge?.disconnectSockets()
    }

    private func pushConfigToWebView() {
        let scaleMode = config.forceFullscreen ? "stretch" : "fit"
        let js = """
        if (window.nstApplyConfig) {
          window.nstApplyConfig({
            width: \(virtualSize.width),
            height: \(virtualSize.height),
            scaleMode: '\(scaleMode)',
            filter: \(config.screenFilter ? "true" : "false"),
            fpsLimit: \(config.fpsLimit),
            touchEnabled: \(config.touchInput ? "true" : "false")
          });
        }
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Stop & Save

    func stop(onFinished: (() -> Void)? = nil) {
        if state == .stopped {
            onFinished?()
            return
        }
        if let onFinished {
            stopCallbacks.append(onFinished)
        }
        if state == .stopping { return }

        let wasRunning = (state == .running)
        state = .stopping
        releaseAllKeys()
        isReady = false
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
            "return window.j2meAPI ? await window.j2meAPI.getSaveData() : null;",
            arguments: [:],
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self, self.state == .stopping else { return }
            if case .success(let value) = result,
               let base64 = value as? String,
               let data = Data(base64Encoded: base64),
               data.starts(with: Self.zipMagic) {
                try? data.write(to: self.saveURL, options: .atomic)
            }
            self.finish()
        }
    }

    // MARK: - Internal Launch

    private func launchGame() {
        guard state == .starting || state == .running, !isLaunched else { return }
        isLaunched = true
        pushConfigToWebView()
        armTimeout("Game chưa khởi động được. Hãy kiểm tra tệp JAR.")

        webView.callAsyncJavaScript(
            "await window.nsvLaunch(); return true;",
            arguments: [:],
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self, self.state == .starting || self.state == .running else { return }
            if case .failure(let error) = result {
                self.fail("Game chưa khởi động được: \(error.localizedDescription)")
            }
        }
    }

    private func armTimeout(_ message: String) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.startupTimeoutNanoseconds)
            guard !Task.isCancelled, let self, self.state == .starting else { return }
            self.fail(message)
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        finish()
        onStateChanged?()
    }

    private func finish() {
        guard state != .stopped else { return }
        state = .stopped
        isReady = false
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

        let cbs = stopCallbacks
        stopCallbacks.removeAll()
        for cb in cbs { cb() }
    }

    // MARK: - WKScriptMessageHandler

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
            isReady = true
            onStateChanged?()

        case "choiceCompleted":
            guard state == .starting else { return }
            armTimeout("Chương trình đã chọn chưa khởi động được.")

        case "gameReady":
            guard state == .starting || state == .running else { return }
            timeoutTask?.cancel()
            timeoutTask = nil
            state = .running
            isReady = true
            errorMessage = nil
            pushConfigToWebView()
            if isBackgrounded {
                webView.evaluateJavaScript("window.nstSetBackground && window.nstSetBackground(true);", completionHandler: nil)
            }
            onStateChanged?()

        case "launchError":
            guard state == .starting || state == .running else { return }
            let msg = (body["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            fail((msg?.isEmpty == false) ? msg! : "Game chưa khởi động được. Hãy kiểm tra tệp JAR.")

        case "saveDataWritten":
            guard state == .running || state == .stopping else { return }
            if let base64 = body["data"] as? String,
               let data = Data(base64Encoded: base64),
               data.starts(with: Self.zipMagic) {
                try? data.write(to: saveURL, options: .atomic)
            }

        case "evalNative":
            guard state == .starting || state == .running else { return }
            networkBridge?.handle(body)

        case "exit":
            guard state == .starting || state == .running else { return }
            stop { [weak self] in
                self?.onExitRequested?()
            }

        default:
            break
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        if url.absoluteString == "about:blank" { return .allow }
        if let host = url.host, host == "127.0.0.1" || host == "localhost" { return .allow }
        return .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.fallbackLaunchNanoseconds)
            guard let self, self.state == .starting, !self.isLaunched else { return }
            self.launchGame()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavError(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard state == .starting || state == .running else { return }
        fail("Trình giả lập đã dừng. Hãy mở lại game.")
    }

    private func handleNavError(_ error: Error) {
        guard state == .starting || state == .running else { return }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        fail("Không tải được trình giả lập: \(error.localizedDescription)")
    }
}
