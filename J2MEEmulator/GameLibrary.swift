import Combine
import Foundation

struct Game: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let fileSize: Int64
    let importedAt: Date

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case fileSize
        case importedAt
    }
}

private struct ImportReport: Sendable {
    var games: [Game] = []
    var failures: [String] = []
}

@MainActor
final class GameLibrary: ObservableObject {
    @Published private(set) var games: [Game] = []
    @Published private(set) var isImporting = false
    @Published var errorMessage: String?

    let directory: URL

    init() {
        self.directory = URL.applicationSupportDirectory.appendingPathComponent("J2ME NSV", isDirectory: true)
        do {
            self.games = try LibraryDisk.load(from: directory)
        } catch {
            self.games = []
            self.errorMessage = "Không đọc được thư viện game. \(error.localizedDescription)"
        }
        loadPreinstalledGames()
    }

    func jarURL(for game: Game) -> URL {
        directory
            .appendingPathComponent(game.id.uuidString, isDirectory: true)
            .appendingPathComponent("game.jar")
    }

    private func loadPreinstalledGames() {
        guard let resourceURL = Bundle.main.resourceURL else { return }
        let runtimeDir = resourceURL.appendingPathComponent("Runtime/j2mejs", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: runtimeDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let jarFiles = entries.filter { url in
            url.pathExtension.lowercased() == "jar" &&
            url.lastPathComponent.lowercased() != "classes.jar"
        }

        for jarURL in jarFiles {
            let baseName = jarURL.deletingPathExtension().lastPathComponent
            if games.contains(where: { $0.name == baseName }) {
                continue
            }
            if let imported = try? LibraryDisk.importGame(at: jarURL, to: directory) {
                games.append(imported)
            }
        }
    }

    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        let targetDir = directory
        let report = await Task.detached(priority: .userInitiated) {
            var result = ImportReport()
            for url in urls {
                do {
                    let game = try LibraryDisk.importGame(at: url, to: targetDir)
                    result.games.append(game)
                } catch {
                    result.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return result
        }.value

        if !report.games.isEmpty {
            games.insert(contentsOf: report.games.reversed(), at: 0)
        }
        if !report.failures.isEmpty {
            errorMessage = report.failures.joined(separator: "\n")
        }
    }

    func downloadFromURL(_ url: URL) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        do {
            let (tempURL, response) = try await URLSession.shared.download(from: url)
            let suggested = response.suggestedFilename ?? url.lastPathComponent
            let fileName = suggested.lowercased().hasSuffix(".jar") ? suggested : "\(suggested).jar"

            let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: stagingDir) }

            let stagedFile = stagingDir.appendingPathComponent(fileName)
            try FileManager.default.moveItem(at: tempURL, to: stagedFile)

            let targetDir = directory
            let imported = try await Task.detached(priority: .userInitiated) {
                try LibraryDisk.importGame(at: stagedFile, to: targetDir)
            }.value

            games.insert(imported, at: 0)
        } catch {
            errorMessage = "Không tải được tệp JAR từ link: \(error.localizedDescription)"
        }
    }

    func scanDocumentsDirectory() async {
        guard !isImporting else { return }

        let docsURL = URL.documentsDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: docsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let jarFiles = entries.filter { $0.pathExtension.lowercased() == "jar" }
        guard !jarFiles.isEmpty else { return }

        isImporting = true
        defer { isImporting = false }

        let targetDir = directory
        let report = await Task.detached(priority: .userInitiated) {
            var result = ImportReport()
            for url in jarFiles {
                do {
                    let game = try LibraryDisk.importGame(at: url, to: targetDir)
                    result.games.append(game)
                    try? FileManager.default.removeItem(at: url)
                } catch {
                    result.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return result
        }.value

        if !report.games.isEmpty {
            games.insert(contentsOf: report.games.reversed(), at: 0)
        }
        if !report.failures.isEmpty {
            errorMessage = report.failures.joined(separator: "\n")
        }
    }

    func remove(_ game: Game) {
        do {
            try LibraryDisk.remove(game, from: directory)
            games.removeAll { $0.id == game.id }
        } catch {
            errorMessage = "Không xóa được \(game.name): \(error.localizedDescription)"
        }
    }
}

private enum LibraryDisk {
    enum ImportError: LocalizedError {
        case invalidType
        case fileTooLarge
        case unreadableFile
        case corruptArchive

        var errorDescription: String? {
            switch self {
            case .invalidType:
                return "Hãy chọn tệp game có đuôi .jar hoặc tệp nén hợp lệ."
            case .fileTooLarge:
                return "Tệp JAR vượt quá giới hạn 64 MiB."
            case .unreadableFile:
                return "Không đọc được tệp từ ứng dụng Tệp."
            case .corruptArchive:
                return "Tệp JAR bị hỏng hoặc có định dạng không hợp lệ."
            }
        }
    }

    private static let maxArchiveSize: Int64 = 64 * 1024 * 1024
    private static let zipMagic: [UInt8] = [0x50, 0x4B, 0x03, 0x04]

    static func load(from directory: URL) throws -> [Game] {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let entries = try fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        )

        var loaded: [Game] = []
        let decoder = JSONDecoder()

        for entry in entries {
            let name = entry.lastPathComponent
            if name.hasPrefix(".import-") || name.hasPrefix(".delete-") {
                try? fm.removeItem(at: entry)
                continue
            }

            guard let folderID = UUID(uuidString: name) else {
                continue
            }

            let metaURL = entry.appendingPathComponent("game.json")
            guard let data = try? Data(contentsOf: metaURL),
                  let game = try? decoder.decode(Game.self, from: data),
                  game.id == folderID else {
                continue
            }

            let jarURL = directory
                .appendingPathComponent(game.id.uuidString, isDirectory: true)
                .appendingPathComponent("game.jar")
            guard fm.fileExists(atPath: jarURL.path) else {
                continue
            }

            loaded.append(game)
        }

        loaded.sort { $0.importedAt > $1.importedAt }
        return loaded
    }

    static func importGame(at sourceURL: URL, to directory: URL) throws -> Game {
        let ext = sourceURL.pathExtension.lowercased()
        let fm = FileManager.default
        let id = UUID()

        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let tempDir = directory.appendingPathComponent(".import-\(id.uuidString)", isDirectory: true)
        let stagedJar = tempDir.appendingPathComponent("game.jar")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var committed = false
        defer {
            if !committed {
                try? fm.removeItem(at: tempDir)
            }
        }

        try copyFile(at: sourceURL, to: stagedJar)

        let size = try archiveSize(at: stagedJar)
        if ext != "jar" && ext != "zip" && !isZipHeader(at: stagedJar) {
            throw ImportError.invalidType
        }
        try verifyArchiveHeader(at: stagedJar)

        let rawTitle = sourceURL.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawTitle.isEmpty ? "Game Java" : rawTitle

        let game = Game(id: id, name: title, fileSize: size, importedAt: Date())
        let metaData = try JSONEncoder().encode(game)
        let metaURL = tempDir.appendingPathComponent("game.json")
        try metaData.write(to: metaURL, options: .atomic)

        let finalDir = directory.appendingPathComponent(id.uuidString, isDirectory: true)
        try fm.moveItem(at: tempDir, to: finalDir)
        committed = true
        return game
    }

    static func remove(_ game: Game, from directory: URL) throws {
        let fm = FileManager.default
        let gameDir = directory.appendingPathComponent(game.id.uuidString, isDirectory: true)
        guard fm.fileExists(atPath: gameDir.path) else { return }

        let trashDir = directory.appendingPathComponent(".delete-\(game.id.uuidString)", isDirectory: true)
        try? fm.removeItem(at: trashDir)
        try fm.moveItem(at: gameDir, to: trashDir)
        try fm.removeItem(at: trashDir)
    }

    private static func copyFile(at sourceURL: URL, to destinationURL: URL) throws {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try? fm.removeItem(at: destinationURL)
        }

        do {
            try fm.copyItem(at: sourceURL, to: destinationURL)
            return
        } catch {
            // Fall back to NSFileCoordinator for iCloud / FileProvider items.
        }

        var coordinatorError: NSError?
        var copyResult: Result<Void, Error>?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinatorError) { coordinatedURL in
            copyResult = Result {
                if fm.fileExists(atPath: destinationURL.path) {
                    try? fm.removeItem(at: destinationURL)
                }
                try fm.copyItem(at: coordinatedURL, to: destinationURL)
            }
        }

        if let copyResult {
            if case .success = copyResult {
                return
            }
        }

        if let data = try? Data(contentsOf: sourceURL) {
            try data.write(to: destinationURL, options: .atomic)
            return
        }

        throw ImportError.unreadableFile
    }

    private static func archiveSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let fileSize = values.fileSize, fileSize > 0 else {
            throw ImportError.corruptArchive
        }
        let size = Int64(fileSize)
        if size > maxArchiveSize {
            throw ImportError.fileTooLarge
        }
        return size
    }

    private static func verifyArchiveHeader(at url: URL) throws {
        guard isZipHeader(at: url) else {
            throw ImportError.corruptArchive
        }
    }

    private static func isZipHeader(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount: 4) else {
            return false
        }
        return bytes == Data(zipMagic)
    }
}
