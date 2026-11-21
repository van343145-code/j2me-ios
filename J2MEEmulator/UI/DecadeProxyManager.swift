//
//  DecadeProxyManager.swift
//  J2MEEmulator
//
//  1:1 Replica of Decade APK Proxy System:
//  - Proxy Storage & CRUD (SOCKS5 & HTTP with Auth)
//  - Multi-line Bulk Import (ip:port:user:pass)
//  - Real-time Connection Testing & Latency (ms) Measurement
//  - Per-Game-Tab Proxy Routing & Assignment (Matching ProxyConfig.java)
//  - Immediate Socket Disconnect to trigger in-game reconnect
//

import UIKit
import Network

// ============================================================
// MARK: - Data Models
// ============================================================

struct ProxyItem: Codable, Equatable {
    let id: Int
    var type: String       // "socks5" or "http"
    var host: String
    var port: Int
    var user: String
    var pass: String
    var label: String
    var lastLatencyMs: Int?
    var lastTestStatus: String?

    var isSocks5: Bool { type.lowercased() == "socks5" }
    var hasAuth: Bool { !user.isEmpty }

    var displayTitle: String {
        return label.isEmpty ? "\(host):\(port)" : label
    }

    var displaySubtitle: String {
        var parts: [String] = []
        parts.append(isSocks5 ? "SOCKS5" : "HTTP")
        if hasAuth {
            parts.append("👤 \(user)")
        } else {
            parts.append("Không mật khẩu")
        }
        if let lat = lastLatencyMs, lat > 0 {
            parts.append("⚡ \(lat)ms")
        } else if let status = lastTestStatus {
            parts.append("⚠️ \(status)")
        }
        return parts.joined(separator: " • ")
    }
}

// ============================================================
// MARK: - DecadeProxyManager
// ============================================================

class DecadeProxyManager {
    static let shared = DecadeProxyManager()

    private let fileURL: URL
    private(set) var proxies: [ProxyItem] = []
    private var nextId: Int = 1

    // Route assignments: routeKey(appId, slot, tabPrefix) -> proxyId (Matching Android ProxyConfig)
    private var tabAssignments: [String: Int] = [:]

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("decade_proxies.json")
        loadProxies()
        loadAssignments()
    }

    // MARK: - Persistence

    func loadProxies() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([ProxyItem].self, from: data) else {
            proxies = []
            return
        }
        proxies = list
        nextId = (proxies.map { $0.id }.max() ?? 0) + 1
    }

    func saveProxies() {
        if let data = try? JSONEncoder().encode(proxies) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func loadAssignments() {
        if let dict = UserDefaults.standard.dictionary(forKey: "decade_proxy_routes") as? [String: Int] {
            tabAssignments = dict
        } else {
            tabAssignments = [:]
        }
    }

    private func saveAssignments() {
        UserDefaults.standard.set(tabAssignments, forKey: "decade_proxy_routes")
    }

    // MARK: - CRUD

    func addProxy(type: String, host: String, port: Int, user: String = "", pass: String = "", label: String? = nil) -> ProxyItem {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? label!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "\(cleanHost):\(port)"

        let item = ProxyItem(
            id: nextId,
            type: type.lowercased(),
            host: cleanHost,
            port: port,
            user: user.trimmingCharacters(in: .whitespacesAndNewlines),
            pass: pass,
            label: cleanLabel,
            lastLatencyMs: nil,
            lastTestStatus: nil
        )
        nextId += 1
        proxies.append(item)
        saveProxies()
        return item
    }

    func updateProxy(_ item: ProxyItem) {
        if let idx = proxies.firstIndex(where: { $0.id == item.id }) {
            proxies[idx] = item
            saveProxies()
        }
    }

    func deleteProxy(id: Int) {
        proxies.removeAll { $0.id == id }
        saveProxies()

        // Remove proxy from all tab and screen route assignments
        tabAssignments = tabAssignments.filter { $0.value != id }
        saveAssignments()
        syncAllToNative()
    }

    func findById(_ id: Int) -> ProxyItem? {
        return proxies.first { $0.id == id }
    }

    // MARK: - Bulk Import

    func importBulk(text: String) -> Int {
        return importProxies(text: text)
    }

    func importProxies(text: String, defaultType: String = "socks5") -> Int {
        let lines = text.components(separatedBy: .newlines)
        var count = 0

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("//") { continue }

            var curType = defaultType.lowercased()
            var body = line

            if body.hasPrefix("socks5://") {
                curType = "socks5"
                body = String(body.dropFirst(9))
            } else if body.hasPrefix("http://") {
                curType = "http"
                body = String(body.dropFirst(7))
            }

            var host = ""
            var port = 0
            var user = ""
            var pass = ""

            if body.contains("@") {
                let parts = body.components(separatedBy: "@")
                if parts.count == 2 {
                    let auth = parts[0].components(separatedBy: ":")
                    user = auth.first ?? ""
                    pass = auth.count > 1 ? auth[1] : ""
                    let hp = parts[1].components(separatedBy: ":")
                    host = hp.first ?? ""
                    port = Int(hp.count > 1 ? hp[1] : "") ?? 0
                }
            } else {
                let parts = body.components(separatedBy: ":")
                if parts.count >= 2 {
                    host = parts[0]
                    port = Int(parts[1]) ?? 0
                    if parts.count >= 4 {
                        user = parts[2]
                        pass = parts[3]
                    }
                }
            }

            if !host.isEmpty && port > 0 && port <= 65535 {
                _ = addProxy(type: curType, host: host, port: port, user: user, pass: pass)
                count += 1
            }
        }

        return count
    }

    // MARK: - Testing Connection & Latency

    func testProxy(item: ProxyItem, completion: @escaping (Bool, Int?, String?) -> Void) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let host = NWEndpoint.Host(item.host)
        guard let port = NWEndpoint.Port(rawValue: UInt16(item.port)) else {
            completion(false, nil, "Cổng không hợp lệ")
            return
        }

        let params = NWParameters.tcp
        params.prohibitExpensivePaths = false
        let connection = NWConnection(host: host, port: port, using: params)

        var finished = false
        let queue = DispatchQueue(label: "decade.proxy.test")

        connection.stateUpdateHandler = { [weak self] state in
            guard !finished else { return }
            switch state {
            case .ready:
                finished = true
                let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
                connection.cancel()

                DispatchQueue.main.async {
                    if var updated = self?.proxies.first(where: { $0.id == item.id }) {
                        updated.lastLatencyMs = elapsedMs
                        updated.lastTestStatus = "OK (\(elapsedMs)ms)"
                        self?.updateProxy(updated)
                    }
                    completion(true, elapsedMs, nil)
                }

            case .failed(let err):
                finished = true
                connection.cancel()
                DispatchQueue.main.async {
                    if var updated = self?.proxies.first(where: { $0.id == item.id }) {
                        updated.lastTestStatus = "Lỗi kết nối"
                        self?.updateProxy(updated)
                    }
                    completion(false, nil, err.localizedDescription)
                }

            case .waiting(let err):
                finished = true
                connection.cancel()
                DispatchQueue.main.async {
                    completion(false, nil, "Chờ timeout: \(err.localizedDescription)")
                }

            default:
                break
            }
        }

        connection.start(queue: queue)

        // 6 second timeout
        queue.asyncAfter(deadline: .now() + 6.0) {
            if !finished {
                finished = true
                connection.cancel()
                DispatchQueue.main.async {
                    completion(false, nil, "Quá thời gian kết nối (Timeout 6s)")
                }
            }
        }
    }

    // MARK: - Per-Game-Tab Route Assignment (Matching ProxyConfig.java)

    static func routeKey(appId: String, slot: Int, tabPrefix: String?) -> String {
        let cleanApp = appId.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = (tabPrefix != nil && !tabPrefix!.isEmpty) ? tabPrefix! : "@screen"
        return "\(cleanApp)\u{1F}\(slot)\u{1F}\(scope)"
    }

    func assignScreen(appId: String, slot: Int, proxyId: Int?) {
        let key = DecadeProxyManager.routeKey(appId: appId, slot: slot, tabPrefix: nil)
        if let pid = proxyId, pid > 0 {
            tabAssignments[key] = pid
        } else {
            tabAssignments.removeValue(forKey: key)
        }
        saveAssignments()
        syncToNative(appId: appId, slot: slot)
    }

    func proxyForScreen(appId: String, slot: Int) -> ProxyItem? {
        let key = DecadeProxyManager.routeKey(appId: appId, slot: slot, tabPrefix: nil)
        if let pid = tabAssignments[key], pid > 0 {
            return findById(pid)
        }
        return nil
    }

    func assignTab(appId: String, slot: Int, tabPrefix: String, proxyId: Int?) {
        let key = DecadeProxyManager.routeKey(appId: appId, slot: slot, tabPrefix: tabPrefix)
        if let pid = proxyId, pid > 0 {
            tabAssignments[key] = pid
        } else {
            tabAssignments.removeValue(forKey: key)
        }
        saveAssignments()
        syncToNative(appId: appId, slot: slot)
    }

    func assignTabs(appId: String, slot: Int, tabPrefixes: [String], proxyId: Int?) {
        for prefix in tabPrefixes {
            let key = DecadeProxyManager.routeKey(appId: appId, slot: slot, tabPrefix: prefix)
            if let pid = proxyId, pid > 0 {
                tabAssignments[key] = pid
            } else {
                tabAssignments.removeValue(forKey: key)
            }
        }
        saveAssignments()
        syncToNative(appId: appId, slot: slot)
    }

    func proxyForTab(appId: String, slot: Int, tabPrefix: String) -> ProxyItem? {
        let key = DecadeProxyManager.routeKey(appId: appId, slot: slot, tabPrefix: tabPrefix)
        if let pid = tabAssignments[key], pid > 0 {
            return findById(pid)
        }
        return nil
    }

    func listAssignedRoutes() -> [String: Int] {
        return tabAssignments
    }

    // MARK: - Native Bridge Synchronization

    func syncToNative(appId: String, slot: Int) {
        guard slot >= 0 && slot < 16 else { return }

        // 1. Clear existing tab rules for slot
        jvm_bridge_clear_tab_proxies(Int32(slot))

        // 2. Set screen default proxy
        if let sp = proxyForScreen(appId: appId, slot: slot) {
            let ptype: Int32 = sp.isSocks5 ? 0 : 1
            sp.host.withCString { hPtr in
                sp.user.withCString { uPtr in
                    sp.pass.withCString { pPtr in
                        jvm_bridge_set_slot_proxy(Int32(slot), ptype, hPtr, Int32(sp.port), uPtr, pPtr)
                    }
                }
            }
        } else {
            jvm_bridge_set_slot_proxy(Int32(slot), -1, "", 0, "", "")
        }

        // 3. Set tab-specific proxies
        for (k, pid) in tabAssignments {
            let parts = k.components(separatedBy: "\u{1F}")
            guard parts.count == 3, parts[0] == appId, Int(parts[1]) == slot else { continue }
            let prefix = parts[2]
            if prefix != "@screen", let tp = findById(pid) {
                let ptype: Int32 = tp.isSocks5 ? 0 : 1
                prefix.withCString { prefPtr in
                    tp.host.withCString { hPtr in
                        tp.user.withCString { uPtr in
                            tp.pass.withCString { pPtr in
                                jvm_bridge_set_tab_proxy(Int32(slot), prefPtr, ptype, hPtr, Int32(tp.port), uPtr, pPtr)
                            }
                        }
                    }
                }
            }
        }
    }

    func syncAllToNative() {
        let sessions = activeGameViewController?.tabSessions ?? []
        for session in sessions {
            syncToNative(appId: session.appName, slot: session.slotIndex)
        }
    }

    func disconnectActiveSockets(for slot: Int) {
        jvm_bridge_disconnect_slot_sockets(Int32(slot))
    }
}
