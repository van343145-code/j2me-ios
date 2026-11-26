import Darwin
import Foundation

/// Rock-solid POSIX 127.0.0.1 loopback HTTP/1.1 server.
/// Never sends TCP RST after final chunk (uses clean `shutdown(fd, SHUT_WR)` + drain before `close`),
/// and binds strictly to `127.0.0.1` so iOS Local Network permission never blocks runtime loading.
final class LoopbackServer: @unchecked Sendable {
    enum ServerError: Error {
        case socketFailed(Int32)
        case bindFailed(Int32)
        case listenFailed(Int32)
        case missingPort
    }

    private static let headerEnd = Data("\r\n\r\n".utf8)
    private static let maxHeaderBytes = 16384

    private let root: URL
    private let game: URL
    private let save: URL
    private let acceptQueue = DispatchQueue(label: "vn.j2menst.loopback.accept")
    private let workerQueue = DispatchQueue(label: "vn.j2menst.loopback.worker", attributes: .concurrent)

    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var stopped = false

    init(root: URL, game: URL, save: URL) throws {
        self.root = root.standardizedFileURL
        self.game = game
        self.save = save
    }

    deinit {
        stop()
    }

    func start(ready: @escaping @Sendable (Result<URL, Error>) -> Void) {
        acceptQueue.async { [weak self] in
            guard let self else { return }
            do {
                let url = try self.openAndListen()
                ready(.success(url))
                self.acceptLoop()
            } catch {
                ready(.failure(error))
            }
        }
    }

    func stop() {
        lock.lock()
        let fd = listenFD
        listenFD = -1
        stopped = true
        lock.unlock()

        if fd >= 0 {
            Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
    }

    private func openAndListen() throws -> URL {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.socketFailed(errno) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // ephemeral port
        addr.sin_addr = in_addr(s_addr: UInt32(INADDR_LOOPBACK).bigEndian)

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let err = errno
            Darwin.close(fd)
            throw ServerError.bindFailed(err)
        }

        guard Darwin.listen(fd, 64) == 0 else {
            let err = errno
            Darwin.close(fd)
            throw ServerError.listenFailed(err)
        }

        var boundAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameRes = withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.getsockname(fd, sa, &len)
            }
        }
        let port = UInt16(bigEndian: boundAddr.sin_port)
        guard nameRes == 0, port > 0, let url = URL(string: "http://127.0.0.1:\(port)/index.html") else {
            Darwin.close(fd)
            throw ServerError.missingPort
        }

        lock.lock()
        if stopped {
            lock.unlock()
            Darwin.close(fd)
            throw ServerError.missingPort
        }
        listenFD = fd
        lock.unlock()

        return url
    }

    private func acceptLoop() {
        while true {
            lock.lock()
            let fd = listenFD
            let isStopped = stopped
            lock.unlock()

            if isStopped || fd < 0 { break }

            var clientAddr = sockaddr_in()
            var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    Darwin.accept(fd, sa, &clientLen)
                }
            }

            if clientFD < 0 {
                if errno == EINTR { continue }
                break
            }

            workerQueue.async { [weak self] in
                self?.handleClient(clientFD)
            }
        }
    }

    private func handleClient(_ fd: Int32) {
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &yes, socklen_t(MemoryLayout<Int32>.size))

        var tv = timeval(tv_sec: 15, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        defer {
            Darwin.shutdown(fd, SHUT_WR)
            // Brief drain so client receives FIN cleanly instead of TCP RST
            var drainTV = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &drainTV, socklen_t(MemoryLayout<timeval>.size))
            var sink = [UInt8](repeating: 0, count: 512)
            while Darwin.recv(fd, &sink, sink.count, 0) > 0 {}
            Darwin.close(fd)
        }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while buffer.count < Self.maxHeaderBytes {
            let n = Darwin.recv(fd, &chunk, chunk.count, 0)
            if n > 0 {
                buffer.append(chunk, count: n)
                if buffer.range(of: Self.headerEnd) != nil {
                    break
                }
            } else if n < 0 && errno == EINTR {
                continue
            } else {
                return
            }
        }

        guard let range = buffer.range(of: Self.headerEnd),
              let headerText = String(data: buffer.subdata(in: 0..<range.lowerBound), encoding: .utf8),
              let requestLine = headerText.components(separatedBy: "\r\n").first else {
            writeResponse(fd: fd, status: "400 Bad Request", contentType: "text/plain", body: Data(), includeBody: false)
            return
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            writeResponse(fd: fd, status: "400 Bad Request", contentType: "text/plain", body: Data(), includeBody: false)
            return
        }

        let method = String(parts[0])
        if method == "OPTIONS" {
            writeResponse(fd: fd, status: "204 No Content", contentType: "text/plain", body: Data(), includeBody: false)
            return
        }
        guard method == "GET" || method == "HEAD" else {
            writeResponse(fd: fd, status: "405 Method Not Allowed", contentType: "text/plain", body: Data(), includeBody: false)
            return
        }

        let rawTarget = String(parts[1])
        let path: String
        if let qIdx = rawTarget.firstIndex(of: "?") {
            path = String(rawTarget[..<qIdx])
        } else {
            path = rawTarget
        }

        guard let fileURL = file(for: path),
              let body = try? Data(contentsOf: fileURL) else {
            writeResponse(fd: fd, status: "404 Not Found", contentType: "text/plain", body: Data(), includeBody: false)
            return
        }

        let mime = contentType(for: fileURL)
        writeResponse(fd: fd, status: "200 OK", contentType: mime, body: body, includeBody: method != "HEAD")
    }

    private func writeResponse(fd: Int32, status: String, contentType: String, body: Data, includeBody: Bool) {
        let header = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n"
            + "Access-Control-Allow-Origin: *\r\n"
            + "Cache-Control: no-store\r\n"
            + "X-Content-Type-Options: nosniff\r\n\r\n"

        guard sendAll(fd: fd, data: Data(header.utf8)) else { return }
        if includeBody && !body.isEmpty {
            _ = sendAll(fd: fd, data: body)
        }
    }

    private func sendAll(fd: Int32, data: Data) -> Bool {
        data.withUnsafeBytes { rawBuf -> Bool in
            guard let base = rawBuf.bindMemory(to: UInt8.self).baseAddress else { return true }
            var sent = 0
            let total = data.count
            while sent < total {
                let n = Darwin.send(fd, base.advanced(by: sent), total - sent, 0)
                if n > 0 {
                    sent += n
                } else if n < 0 && errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }

    private func file(for path: String) -> URL? {
        let fm = FileManager.default

        if path == "/game/current.jar" {
            return fm.fileExists(atPath: game.path) ? game : nil
        }

        if path == "/game/save.zip" {
            return fm.fileExists(atPath: save.path) ? save : nil
        }

        if path == "/certs/_main.ks" {
            let certURL = root.appendingPathComponent("certs/_main.ks")
            return fm.fileExists(atPath: certURL.path) ? certURL : nil
        }

        guard path.hasPrefix("/"),
              let decoded = path.removingPercentEncoding,
              !decoded.contains(".."),
              !decoded.contains("\\"),
              !decoded.contains("\0") else {
            return nil
        }

        let trimmed = String(decoded.dropFirst())
        let relative = trimmed.isEmpty ? "index.html" : trimmed
        let candidate = root.appendingPathComponent(relative).standardizedFileURL

        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else { return nil }

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: candidate.path, isDirectory: &isDir), !isDir.boolValue else {
            return nil
        }
        return candidate
    }

    private func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js":   return "text/javascript; charset=utf-8"
        case "css":  return "text/css; charset=utf-8"
        case "json": return "application/json"
        case "png":  return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "wav":  return "audio/wav"
        case "wasm": return "application/wasm"
        case "zip":  return "application/zip"
        case "jar":  return "application/java-archive"
        default:     return "application/octet-stream"
        }
    }
}
