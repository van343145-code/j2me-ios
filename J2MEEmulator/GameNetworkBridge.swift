import Foundation
import Network
import WebKit

@MainActor
final class GameNetworkBridge {
    private final class Socket {
        let token = UUID()
        let connection: NWConnection
        var timeout: Task<Void, Never>?
        var started = false
        var ready = false
        var pendingBytes = 0

        init(connection: NWConnection) {
            self.connection = connection
        }
    }

    private struct HTTPResult: Sendable {
        let statusCode: Int
        let data: String
    }

    private static let allowedSchemes = ["http", "https"]
    private static let allowedMethods = ["GET", "HEAD", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]
    private static let blockedHeaders = [
        "connection",
        "content-length",
        "host",
        "proxy-authorization",
        "transfer-encoding",
        "upgrade",
    ]
    private static let headerNameAllowed = CharacterSet(
        charactersIn: "!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    )

    private static let maxConcurrentRequests = 16
    private static let maxConcurrentSockets = 16
    private static let maxURLBytes = 8192
    private static let maxHeadersCount = 32
    private static let maxHeaderValueBytes = 8192
    private static let maxRequestBodyBytes = 1_048_576
    private static let maxRequestBase64Bytes = 1_398_104
    private static let maxResponseBytes = 16 * 1024 * 1024
    private static let maxSocketWriteBytes = 256 * 1024
    private static let maxSocketPendingBytes = 1_048_576
    private static let socketReadChunkBytes = 65536

    private weak var webView: WKWebView?
    private let http: URLSession
    private var requests: [String: Task<Void, Never>] = [:]
    private var sockets: [String: Socket] = [:]

    init(webView: WKWebView) {
        self.webView = webView
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0
        self.http = URLSession(configuration: config)
    }

    func close() {
        for task in requests.values {
            task.cancel()
        }
        requests.removeAll()

        for socket in sockets.values {
            socket.timeout?.cancel()
            socket.connection.stateUpdateHandler = nil
            socket.connection.cancel()
        }
        sockets.removeAll()

        http.invalidateAndCancel()
    }

    func handle(_ message: [String: Any]) {
        guard let command = message["command"] as? String else { return }
        let data = (message["data"] as? [String: Any]) ?? [:]

        switch command {
        case "request":
            guard let id = identifier(message["requestId"], prefix: "request_") else { return }
            request(id, data: data)
        case "connectSocket":
            guard let id = identifier(data["__socketId"], prefix: "socket_") else { return }
            prepareSocket(id, data: data)
        case "onSocket":
            guard let id = identifier(data["id"], prefix: "socket_") else { return }
            startSocket(id)
        case "invokeSocket":
            guard let id = identifier(data["id"], prefix: "socket_") else { return }
            invokeSocket(id, data: data)
        default:
            break
        }
    }

    private func identifier(_ raw: Any?, prefix: String) -> String? {
        guard let id = raw as? String,
              id.utf8.count <= 24,
              id.hasPrefix(prefix) else {
            return nil
        }

        let suffix = id.utf8.dropFirst(prefix.utf8.count)
        guard !suffix.isEmpty, suffix.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            return nil
        }
        return id
    }

    private func request(_ id: String, data: [String: Any]) {
        guard requests[id] == nil, requests.count < Self.maxConcurrentRequests else {
            finishRequest(id, result: nil)
            return
        }

        guard let urlRequest = makeRequest(data) else {
            finishRequest(id, result: nil)
            return
        }

        let session = http
        let task = Task { [weak self] in
            let result = try? await Self.load(urlRequest, using: session)
            guard !Task.isCancelled else { return }
            self?.finishRequest(id, result: result)
        }
        requests[id] = task
    }

    private func finishRequest(_ id: String, result: HTTPResult?) {
        requests.removeValue(forKey: id)
        guard let webView else { return }

        let script = """
        const callbacks = window.__j2meNetworkCallbacks;
        const callback = callbacks[id];
        delete callbacks[id];
        if (typeof callback === 'function') callback({ statusCode: status, data });
        """
        let arguments: [String: Any] = [
            "id": id,
            "status": result?.statusCode ?? 0,
            "data": result?.data ?? "",
        ]
        webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page, completionHandler: nil)
    }

    private func makeRequest(_ data: [String: Any]) -> URLRequest? {
        guard let urlString = data["url"] as? String,
              urlString.utf8.count <= Self.maxURLBytes,
              let components = URLComponents(string: urlString),
              let scheme = components.scheme?.lowercased(),
              Self.allowedSchemes.contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil,
              components.password == nil,
              let url = components.url else {
            return nil
        }

        let method = ((data["method"] as? String) ?? "GET").uppercased()
        guard Self.allowedMethods.contains(method) else {
            return nil
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15.0)
        request.httpMethod = method

        if let headers = data["headers"] as? [String: String] {
            guard headers.count <= Self.maxHeadersCount else { return nil }
            for (name, value) in headers {
                guard !name.isEmpty,
                      name.utf8.count <= Self.maxHeaderValueBytes,
                      value.utf8.count <= Self.maxHeaderValueBytes,
                      name.unicodeScalars.allSatisfy({ Self.headerNameAllowed.contains($0) }),
                      !value.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" || $0.value == 0 }) else {
                    return nil
                }

                let lower = name.lowercased()
                if Self.blockedHeaders.contains(lower) {
                    continue
                }
                request.setValue(value, forHTTPHeaderField: name)
            }
        }

        if let bodyString = data["data"] as? String {
            let encoding = (data["encoding"] as? String)?.lowercased()
            if encoding == "base64" {
                guard bodyString.utf8.count <= Self.maxRequestBase64Bytes,
                      let decoded = Data(base64Encoded: bodyString),
                      decoded.count <= Self.maxRequestBodyBytes else {
                    return nil
                }
                request.httpBody = decoded
            } else {
                guard bodyString.utf8.count <= Self.maxRequestBodyBytes else {
                    return nil
                }
                request.httpBody = Data(bodyString.utf8)
            }
        }

        return request
    }

    private nonisolated static func load(_ request: URLRequest, using session: URLSession) async throws -> HTTPResult {
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let isHead = request.httpMethod == "HEAD"
        let expected = response.expectedContentLength
        if !isHead && expected > Int64(maxResponseBytes) {
            bytes.task.cancel()
            throw URLError(.dataLengthExceedsMaximum)
        }

        var buffer = Data()
        if !isHead {
            if expected > 0 && expected <= Int64(maxResponseBytes) {
                buffer.reserveCapacity(Int(expected))
            }
            var iterator = bytes.makeAsyncIterator()
            while let byte = try await iterator.next() {
                buffer.append(byte)
                if buffer.count > maxResponseBytes {
                    bytes.task.cancel()
                    throw URLError(.dataLengthExceedsMaximum)
                }
            }
        }

        return HTTPResult(statusCode: httpResponse.statusCode, data: buffer.base64EncodedString())
    }

    private func validSocketHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.utf8.count <= 253 else {
            return false
        }
        if IPv6Address(host) != nil {
            return true
        }
        return host.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) ||
            (byte >= 65 && byte <= 90) ||
            (byte >= 97 && byte <= 122) ||
            byte == 45 || byte == 46
        }
    }

    private func prepareSocket(_ id: String, data: [String: Any]) {
        guard sockets[id] == nil, sockets.count < Self.maxConcurrentSockets else {
            return
        }

        guard let host = data["host"] as? String,
              validSocketHost(host) else {
            return
        }

        let portInt: Int
        if let intVal = data["port"] as? Int {
            portInt = intVal
        } else if let numVal = data["port"] as? NSNumber {
            portInt = numVal.intValue
        } else {
            return
        }

        guard portInt >= 1 && portInt <= 65535,
              let port = NWEndpoint.Port(rawValue: UInt16(portInt)) else {
            return
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        let socket = Socket(connection: connection)
        sockets[id] = socket

        let rawTimeout: Int
        if let t = data["timeout"] as? Int {
            rawTimeout = t
        } else if let n = data["timeout"] as? NSNumber {
            rawTimeout = n.intValue
        } else {
            rawTimeout = 5000
        }
        let clampedMs = min(max(rawTimeout, 1000), 12000)
        let token = socket.token

        socket.timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(clampedMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.finishSocket(id, token: token, event: "error")
        }
    }

    private func startSocket(_ id: String) {
        guard let socket = sockets[id] else {
            emitSocket(id, event: "error", data: "", terminal: true)
            return
        }

        guard !socket.started else { return }
        socket.started = true
        let token = socket.token

        socket.connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self,
                      let current = self.sockets[id],
                      current.token == token else {
                    return
                }

                switch state {
                case .ready:
                    current.timeout?.cancel()
                    current.timeout = nil
                    guard !current.ready else { return }
                    current.ready = true
                    self.emitSocket(id, event: "connect", data: "", terminal: false)
                    self.receive(id, token: token)
                case .failed:
                    self.finishSocket(id, token: token, event: "error")
                case .cancelled:
                    self.finishSocket(id, token: token, event: current.ready ? "close" : "error")
                default:
                    break
                }
            }
        }

        socket.connection.start(queue: .main)
    }

    private func receive(_ id: String, token: UUID) {
        guard let socket = sockets[id], socket.token == token else { return }

        socket.connection.receive(minimumIncompleteLength: 1, maximumLength: Self.socketReadChunkBytes) { [weak self] content, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self,
                      let current = self.sockets[id],
                      current.token == token else {
                    return
                }

                if let content, !content.isEmpty {
                    let encoded = content.base64EncodedString()
                    self.emitSocket(id, event: "data", data: encoded, terminal: false) { [weak self] in
                        guard let self else { return }
                        if error != nil {
                            self.finishSocket(id, token: token, event: "error")
                        } else if isComplete {
                            self.finishSocket(id, token: token, event: "close")
                        } else {
                            self.receive(id, token: token)
                        }
                    }
                    return
                }

                if error != nil {
                    self.finishSocket(id, token: token, event: "error")
                } else if isComplete {
                    self.finishSocket(id, token: token, event: "close")
                } else {
                    self.receive(id, token: token)
                }
            }
        }
    }

    private func invokeSocket(_ id: String, data: [String: Any]) {
        guard let socket = sockets[id],
              let method = data["method"] as? String else {
            return
        }

        let token = socket.token
        if method == "destroy" {
            finishSocket(id, token: token, event: "close")
            return
        }

        if method == "write" {
            guard socket.ready,
                  let encoded = data["data"] as? String,
                  let payload = Data(base64Encoded: encoded) else {
                finishSocket(id, token: token, event: "error")
                return
            }

            guard payload.count <= Self.maxSocketWriteBytes,
                  socket.pendingBytes + payload.count <= Self.maxSocketPendingBytes else {
                finishSocket(id, token: token, event: "error")
                return
            }

            let byteCount = payload.count
            socket.pendingBytes += byteCount

            socket.connection.send(
                content: payload,
                contentContext: .defaultMessage,
                isComplete: true,
                completion: .contentProcessed { [weak self] error in
                    Task { @MainActor [weak self] in
                        guard let self,
                              let current = self.sockets[id],
                              current.token == token else {
                            return
                        }
                        current.pendingBytes = max(0, current.pendingBytes - byteCount)
                        if error != nil {
                            self.finishSocket(id, token: token, event: "error")
                        }
                    }
                }
            )
        }
    }

    private func finishSocket(_ id: String, token: UUID, event: String) {
        guard let socket = sockets[id], socket.token == token else { return }
        sockets.removeValue(forKey: id)
        socket.timeout?.cancel()
        socket.timeout = nil
        socket.connection.stateUpdateHandler = nil
        socket.connection.cancel()
        emitSocket(id, event: event, data: "", terminal: true)
    }

    private func emitSocket(
        _ id: String,
        event: String,
        data: String,
        terminal: Bool,
        completion: (() -> Void)? = nil
    ) {
        guard let webView else {
            completion?()
            return
        }

        let script = """
        const callbacks = window.__j2meSocketCallbacks;
        const callback = callbacks[id];
        if (terminal) delete callbacks[id];
        if (typeof callback === 'function') callback({ event, data });
        """
        let arguments: [String: Any] = [
            "id": id,
            "event": event,
            "data": data,
            "terminal": terminal,
        ]
        webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { _ in
            completion?()
        }
    }
}
