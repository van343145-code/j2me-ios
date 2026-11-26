import Foundation
import Network

// MARK: - ProxyInfo & ProxyStore (Exact 1:1 from J2me.Host.ProxyStore & ProxyInfo)

struct ProxyInfo: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    var type: String // "socks5" or "http"
    var host: String
    var port: Int
    var user: String
    var pass: String
    var label: String

    var displayRow: String {
        let proto = type.lowercased() == "http" ? "HTTP" : "SOCKS5"
        let base = "\(proto) \(host):\(port)"
        if !label.isEmpty {
            return "\(base) (\(label))"
        }
        if !user.isEmpty {
            return "\(base) · \(user)"
        }
        return base
    }
}

private struct ProxyConfigFile: Codable {
    var schema: Int = 2
    var nextId: Int = 1
    var proxies: [ProxyInfo] = []
    var routes: [String: Int] = [:]
}

@MainActor
final class ProxyStore {
    static let shared = ProxyStore()

    static let testHost = "1.1.1.1"
    static let testPort = 80

    private let fileURL: URL
    private var state = ProxyConfigFile()

    private init() {
        self.fileURL = NstLibrary.shared.proxyPath
        load()
    }

    var proxies: [ProxyInfo] { state.proxies }

    func find(id: Int) -> ProxyInfo? {
        state.proxies.first(where: { $0.id == id })
    }

    func routeCount(for proxyId: Int) -> Int {
        state.routes.values.filter { $0 == proxyId }.count
    }

    func proxyIdForScreen(gameId: String, slot: Int) -> Int {
        state.routes[routeKey(gameId: gameId, slot: slot)] ?? 0
    }

    func proxyForSlot(gameId: String, slot: Int) -> ProxyInfo? {
        let pid = proxyIdForScreen(gameId: gameId, slot: slot)
        guard pid > 0 else { return nil }
        return find(id: pid)
    }

    func assignScreen(gameId: String, slot: Int, proxyId: Int) {
        let key = routeKey(gameId: gameId, slot: slot)
        if proxyId <= 0 {
            state.routes.removeValue(forKey: key)
        } else {
            state.routes[key] = proxyId
        }
        save()
    }

    func clearGame(_ gameId: String) {
        let prefix = "\(gameId)\u{1F}"
        state.routes = state.routes.filter { !$0.key.hasPrefix(prefix) }
        save()
    }

    @discardableResult
    func add(type: String, host: String, port: Int, user: String, pass: String, label: String = "") -> ProxyInfo? {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty, port >= 1, port <= 65535 else { return nil }
        let normType = normalizeType(type)
        let info = ProxyInfo(
            id: state.nextId,
            type: normType,
            host: cleanHost,
            port: port,
            user: user.trimmingCharacters(in: .whitespacesAndNewlines),
            pass: pass.trimmingCharacters(in: .whitespacesAndNewlines),
            label: label.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        state.nextId += 1
        state.proxies.append(info)
        save()
        return info
    }

    func update(_ updated: ProxyInfo) {
        guard let idx = state.proxies.firstIndex(where: { $0.id == updated.id }) else { return }
        var copy = updated
        copy.type = normalizeType(updated.type)
        state.proxies[idx] = copy
        save()
    }

    func remove(id: Int) -> Bool {
        guard routeCount(for: id) == 0 else { return false }
        let before = state.proxies.count
        state.proxies.removeAll { $0.id == id }
        if state.proxies.count != before {
            save()
            return true
        }
        return false
    }

    func importLines(_ text: String, type: String) -> (added: Int, duplicates: Int) {
        let normType = normalizeType(type)
        var added = 0
        var dupes = 0
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        for raw in lines {
            guard let parsed = Self.parseLine(raw, defaultType: normType) else { continue }
            let exists = state.proxies.contains {
                $0.type == parsed.type && $0.host.caseInsensitiveCompare(parsed.host) == .orderedSame
                    && $0.port == parsed.port && $0.user == parsed.user && $0.pass == parsed.pass
            }
            if exists {
                dupes += 1
                continue
            }
            _ = add(type: parsed.type, host: parsed.host, port: parsed.port, user: parsed.user, pass: parsed.pass)
            added += 1
        }
        return (added, dupes)
    }

    static func parseLine(_ raw: String, defaultType: String) -> ProxyInfo? {
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }

        var kind = defaultType
        if line.lowercased().hasPrefix("socks5://") {
            kind = "socks5"
            line = String(line.dropFirst(9))
        } else if line.lowercased().hasPrefix("http://") {
            kind = "http"
            line = String(line.dropFirst(7))
        }

        // Support user:pass@host:port
        if let atIdx = line.lastIndex(of: "@") {
            let authPart = String(line[..<atIdx])
            let hostPart = String(line[line.index(after: atIdx)...])
            let hp = hostPart.split(separator: ":", maxSplits: 1)
            guard hp.count == 2, let port = Int(hp[1]), (1...65535).contains(port) else { return nil }
            let up = authPart.split(separator: ":", maxSplits: 1)
            let user = up.count >= 1 ? String(up[0]) : ""
            let pass = up.count >= 2 ? String(up[1]) : ""
            return ProxyInfo(id: 0, type: kind, host: String(hp[0]), port: port, user: user, pass: pass, label: "")
        }

        // Standard ip:port or ip:port:user:pass
        let parts = line.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count >= 2, let port = Int(parts[1]), (1...65535).contains(port) else { return nil }
        let host = String(parts[0]).trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return nil }
        let user = parts.count >= 3 ? String(parts[2]) : ""
        let pass = parts.count >= 4 ? String(parts[3]) : ""
        return ProxyInfo(id: 0, type: kind, host: host, port: port, user: user, pass: pass, label: "")
    }

    private func routeKey(gameId: String, slot: Int) -> String {
        "\(gameId)\u{1F}\(slot)\u{1F}@screen"
    }

    private func normalizeType(_ t: String) -> String {
        t.lowercased() == "http" ? "http" : "socks5"
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(ProxyConfigFile.self, from: data) else {
            return
        }
        state = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - Real SOCKS5 (RFC 1928/1929) & HTTP CONNECT Dialer via NWConnection

enum ProxyDialerError: LocalizedError {
    case invalidEndpoint
    case timeout
    case handshakeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "Địa chỉ proxy không hợp lệ"
        case .timeout: return "Quá thời gian kết nối proxy"
        case .handshakeFailed(let msg): return msg
        }
    }
}

enum ProxyDialer {
    private static let dialQueue = DispatchQueue(label: "vn.j2menst.proxy.dial", attributes: .concurrent)

    /// Opens an `NWConnection` to `(targetHost, targetPort)`, optionally tunnelling through SOCKS5 or HTTP CONNECT.
    static func dial(
        targetHost: String,
        targetPort: Int,
        proxy: ProxyInfo?,
        timeoutMs: Int = 8000
    ) async throws -> NWConnection {
        guard let proxy else {
            guard let port = NWEndpoint.Port(rawValue: UInt16(targetPort)) else {
                throw ProxyDialerError.invalidEndpoint
            }
            let conn = NWConnection(host: NWEndpoint.Host(targetHost), port: port, using: .tcp)
            try await connectReady(conn, timeoutMs: timeoutMs)
            return conn
        }

        guard let proxyPort = NWEndpoint.Port(rawValue: UInt16(proxy.port)) else {
            throw ProxyDialerError.invalidEndpoint
        }
        let conn = NWConnection(host: NWEndpoint.Host(proxy.host), port: proxyPort, using: .tcp)
        do {
            try await connectReady(conn, timeoutMs: timeoutMs)
            if proxy.type.lowercased() == "http" {
                try await performHTTPConnect(conn, targetHost: targetHost, targetPort: targetPort, proxy: proxy)
            } else {
                try await performSOCKS5(conn, targetHost: targetHost, targetPort: targetPort, proxy: proxy)
            }
            return conn
        } catch {
            conn.cancel()
            throw error
        }
    }

    static func testProxy(_ proxy: ProxyInfo) async -> String {
        let start = Date()
        do {
            let conn = try await dial(
                targetHost: ProxyStore.testHost,
                targetPort: ProxyStore.testPort,
                proxy: proxy,
                timeoutMs: 6000
            )
            conn.cancel()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return "Kết nối OK (\(ms) ms)"
        } catch {
            return "Lỗi: \(error.localizedDescription)"
        }
    }

    private final class DialGate: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        private let conn: NWConnection
        private let cont: CheckedContinuation<Void, Error>

        init(conn: NWConnection, cont: CheckedContinuation<Void, Error>) {
            self.conn = conn
            self.cont = cont
        }

        func finish(_ result: Result<Void, Error>) {
            lock.lock()
            if finished {
                lock.unlock()
                return
            }
            finished = true
            lock.unlock()
            conn.stateUpdateHandler = nil
            switch result {
            case .success: cont.resume()
            case .failure(let err): cont.resume(throwing: err)
            }
        }
    }

    private static func connectReady(_ conn: NWConnection, timeoutMs: Int) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let gate = DialGate(conn: conn, cont: cont)

            dialQueue.asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) {
                gate.finish(.failure(ProxyDialerError.timeout))
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.finish(.success(()))
                case .failed(let err):
                    gate.finish(.failure(err))
                case .cancelled:
                    gate.finish(.failure(ProxyDialerError.handshakeFailed("Kết nối bị hủy")))
                default:
                    break
                }
            }
            conn.start(queue: dialQueue)
        }
    }

    private static func sendBytes(_ conn: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { err in
                if let err {
                    cont.resume(throwing: err)
                } else {
                    cont.resume()
                }
            })
        }
    }

    private static func readExact(_ conn: NWConnection, count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            conn.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, err in
                if let err {
                    cont.resume(throwing: err)
                } else if let data, data.count >= count {
                    cont.resume(returning: data)
                } else {
                    cont.resume(throwing: ProxyDialerError.handshakeFailed("Proxy đóng kết nối sớm"))
                }
            }
        }
    }

    private static func performSOCKS5(_ conn: NWConnection, targetHost: String, targetPort: Int, proxy: ProxyInfo) async throws {
        let hasAuth = !proxy.user.isEmpty || !proxy.pass.isEmpty
        var greeting = Data([0x05])
        if hasAuth {
            greeting.append(contentsOf: [0x02, 0x00, 0x02])
        } else {
            greeting.append(contentsOf: [0x01, 0x00])
        }
        try await sendBytes(conn, greeting)

        let methodResp = try await readExact(conn, count: 2)
        guard methodResp[0] == 0x05 else {
            throw ProxyDialerError.handshakeFailed("Không phải server SOCKS5")
        }
        let chosen = methodResp[1]
        if chosen == 0xFF {
            throw ProxyDialerError.handshakeFailed("SOCKS5 từ chối phương thức xác thực")
        }

        if chosen == 0x02 {
            let uBytes = Data(proxy.user.utf8)
            let pBytes = Data(proxy.pass.utf8)
            guard uBytes.count <= 255, pBytes.count <= 255 else {
                throw ProxyDialerError.handshakeFailed("User/pass proxy quá dài")
            }
            var auth = Data([0x01, UInt8(uBytes.count)])
            auth.append(uBytes)
            auth.append(UInt8(pBytes.count))
            auth.append(pBytes)
            try await sendBytes(conn, auth)

            let authResp = try await readExact(conn, count: 2)
            guard authResp[1] == 0x00 else {
                throw ProxyDialerError.handshakeFailed("Sai user/pass SOCKS5")
            }
        }

        let hostBytes = Data(targetHost.utf8)
        guard hostBytes.count <= 255 else {
            throw ProxyDialerError.invalidEndpoint
        }
        var req = Data([0x05, 0x01, 0x00, 0x03, UInt8(hostBytes.count)])
        req.append(hostBytes)
        req.append(UInt8((targetPort >> 8) & 0xFF))
        req.append(UInt8(targetPort & 0xFF))
        try await sendBytes(conn, req)

        let head = try await readExact(conn, count: 4)
        guard head[0] == 0x05, head[1] == 0x00 else {
            throw ProxyDialerError.handshakeFailed("SOCKS5 CONNECT thất bại (mã \(head[1]))")
        }
        switch head[3] {
        case 0x01: // IPv4 + port
            _ = try await readExact(conn, count: 6)
        case 0x03: // Domain len + domain + port
            let l = try await readExact(conn, count: 1)
            _ = try await readExact(conn, count: Int(l[0]) + 2)
        case 0x04: // IPv6 + port
            _ = try await readExact(conn, count: 18)
        default:
            throw ProxyDialerError.handshakeFailed("SOCKS5 ATYP không hợp lệ")
        }
    }

    private static func performHTTPConnect(_ conn: NWConnection, targetHost: String, targetPort: Int, proxy: ProxyInfo) async throws {
        var req = "CONNECT \(targetHost):\(targetPort) HTTP/1.1\r\nHost: \(targetHost):\(targetPort)\r\n"
        if !proxy.user.isEmpty || !proxy.pass.isEmpty {
            let cred = Data("\(proxy.user):\(proxy.pass)".utf8).base64EncodedString()
            req += "Proxy-Authorization: Basic \(cred)\r\n"
        }
        req += "Proxy-Connection: Keep-Alive\r\n\r\n"
        try await sendBytes(conn, Data(req.utf8))

        let endMarker = Data("\r\n\r\n".utf8)
        var acc = Data()
        while acc.count < 8192 {
            let chunk: Data = try await withCheckedThrowingContinuation { cont in
                conn.receive(minimumIncompleteLength: 1, maximumLength: 2048) { data, _, _, err in
                    if let err { cont.resume(throwing: err) }
                    else if let data, !data.isEmpty { cont.resume(returning: data) }
                    else { cont.resume(throwing: ProxyDialerError.handshakeFailed("HTTP proxy đóng kết nối")) }
                }
            }
            acc.append(chunk)
            if acc.range(of: endMarker) != nil { break }
        }
        guard let text = String(data: acc, encoding: .utf8),
              let firstLine = text.components(separatedBy: "\r\n").first,
              firstLine.contains(" 200") else {
            throw ProxyDialerError.handshakeFailed("HTTP CONNECT bị từ chối")
        }
    }
}
