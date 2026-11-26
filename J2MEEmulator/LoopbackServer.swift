import Foundation
import Network

final class LoopbackServer: @unchecked Sendable {
    enum ServerError: Error {
        case missingPort
    }

    private static let headerEnd = Data("\r\n\r\n".utf8)
    private static let maxHeaderBytes = 8192
    private static let maxClients = 64
    private static let chunkSize = 65536
    private static let clientTimeout: TimeInterval = 15.0

    private let root: URL
    private let game: URL
    private let save: URL
    private let queue = DispatchQueue(label: "vn.j2mensv.runtime.http")
    private let listener: NWListener
    private var clients: [ObjectIdentifier: NWConnection] = [:]
    private var hasDeliveredReady = false

    init(root: URL, game: URL, save: URL) throws {
        self.root = root.standardizedFileURL
        self.game = game
        self.save = save

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        self.listener = try NWListener(using: parameters, on: .any)
    }

    func start(ready: @escaping @Sendable (Result<URL, Error>) -> Void) {
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, !self.hasDeliveredReady else { return }
            switch state {
            case .ready:
                self.hasDeliveredReady = true
                guard let port = self.listener.port,
                      let url = URL(string: "http://127.0.0.1:\(port.rawValue)/index.html") else {
                    ready(.failure(ServerError.missingPort))
                    return
                }
                ready(.success(url))
            case .failed(let error):
                self.hasDeliveredReady = true
                ready(.failure(error))
            case .cancelled:
                self.hasDeliveredReady = true
                ready(.failure(ServerError.missingPort))
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            guard self.clients.count < Self.maxClients else {
                connection.cancel()
                return
            }

            let key = ObjectIdentifier(connection)
            self.clients[key] = connection
            connection.start(queue: self.queue)
            self.receiveRequest(on: connection, accumulated: Data())

            self.queue.asyncAfter(deadline: .now() + Self.clientTimeout) { [weak self, weak connection] in
                guard let self, let connection else { return }
                let id = ObjectIdentifier(connection)
                if self.clients.removeValue(forKey: id) != nil {
                    connection.cancel()
                }
            }
        }

        listener.start(queue: queue)
    }

    func stop() {
        queue.async { [self] in
            listener.stateUpdateHandler = nil
            listener.newConnectionHandler = nil
            listener.cancel()

            for connection in clients.values {
                connection.cancel()
            }
            clients.removeAll()
        }
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxHeaderBytes) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            let key = ObjectIdentifier(connection)
            if error != nil {
                self.clients.removeValue(forKey: key)
                connection.cancel()
                return
            }

            var buffer = accumulated
            if let data, !data.isEmpty {
                buffer.append(data)
            } else if isComplete {
                self.clients.removeValue(forKey: key)
                connection.cancel()
                return
            }

            if let range = buffer.range(of: Self.headerEnd) {
                let headerData = buffer.subdata(in: 0..<range.lowerBound)
                self.respond(to: headerData, on: connection)
                return
            }

            if buffer.count >= Self.maxHeaderBytes || isComplete {
                self.clients.removeValue(forKey: key)
                connection.cancel()
                return
            }

            self.receiveRequest(on: connection, accumulated: buffer)
        }
    }

    private func respond(to headerData: Data, on connection: NWConnection) {
        guard let requestText = String(data: headerData, encoding: .utf8),
              let requestLine = requestText.components(separatedBy: "\r\n").first else {
            sendResponse(status: "400 Bad Request", contentType: "text/plain", body: Data(), includeBody: false, on: connection)
            return
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            sendResponse(status: "400 Bad Request", contentType: "text/plain", body: Data(), includeBody: false, on: connection)
            return
        }

        let method = parts[0]
        guard method == "GET" || method == "HEAD" else {
            sendResponse(status: "400 Bad Request", contentType: "text/plain", body: Data(), includeBody: false, on: connection)
            return
        }

        let rawTarget = parts[1]
        let path: String
        if let queryIndex = rawTarget.firstIndex(of: "?") {
            path = String(rawTarget[..<queryIndex])
        } else {
            path = String(rawTarget)
        }

        guard let fileURL = file(for: path),
              let body = try? Data(contentsOf: fileURL) else {
            sendResponse(status: "404 Not Found", contentType: "text/plain", body: Data(), includeBody: false, on: connection)
            return
        }

        let mime = contentType(for: fileURL)
        sendResponse(status: "200 OK", contentType: mime, body: body, includeBody: method != "HEAD", on: connection)
    }

    private func sendResponse(
        status: String,
        contentType: String,
        body: Data,
        includeBody: Bool,
        on connection: NWConnection
    ) {
        var header = "HTTP/1.1 "
        header.append(status)
        header.append("\r\nContent-Type: ")
        header.append(contentType)
        header.append("\r\nContent-Length: ")
        header.append(String(body.count))
        header.append("\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n")

        var payload = Data(header.utf8)
        if includeBody && !body.isEmpty {
            payload.append(body)
        }

        sendPayload(payload, offset: 0, chunkSize: Self.chunkSize, on: connection)
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
        guard candidate.path.hasPrefix(rootPrefix) else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }

        return candidate
    }

    private func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html":
            return "text/html; charset=utf-8"
        case "js":
            return "text/javascript; charset=utf-8"
        case "css":
            return "text/css; charset=utf-8"
        case "json":
            return "application/json"
        case "png":
            return "image/png"
        case "wasm":
            return "application/wasm"
        case "zip":
            return "application/zip"
        case "jar":
            return "application/java-archive"
        default:
            return "application/octet-stream"
        }
    }

    private func sendPayload(_ payload: Data, offset: Int, chunkSize: Int, on connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        guard offset < payload.count else {
            clients.removeValue(forKey: key)
            connection.cancel()
            return
        }

        let end = min(offset + chunkSize, payload.count)
        let isFinal = end >= payload.count
        let chunk = payload.subdata(in: offset..<end)
        let context: NWConnection.ContentContext = isFinal ? .finalMessage : .defaultMessage

        connection.send(content: chunk, contentContext: context, isComplete: isFinal, completion: .contentProcessed { [weak self] error in
            guard let self else {
                connection.cancel()
                return
            }

            if error != nil || isFinal {
                self.clients.removeValue(forKey: key)
                connection.cancel()
                return
            }

            self.queue.async { [weak self] in
                self?.sendPayload(payload, offset: end, chunkSize: chunkSize, on: connection)
            }
        })
    }
}
