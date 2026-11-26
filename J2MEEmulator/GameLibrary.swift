import Foundation
import UIKit

@MainActor
final class NstLibrary {
    static let shared = NstLibrary()

    let rootDir: URL
    let externalDir: URL
    let bundledDir: URL
    let configsDir: URL
    let iconsDir: URL
    let displayPath: URL
    let homeTabPath: URL
    let proxyPath: URL

    private(set) var externalGames: [GameEntry] = []
    private(set) var bundledEntries: [String: GameEntry] = [:]
    var displayPrefs: DisplayPrefs
    var currentTab: HomeTab

    private var iconCache: [String: UIImage] = [:]

    let products: [CatalogProduct] = [
        CatalogProduct(
            id: "NJ",
            name: "Ninja School",
            subtitle: "Bản mod NST · VanTranidol_NokiaE6",
            iconKey: "nj",
            variants: [
                CatalogVariant(
                    productId: "NJ",
                    variantId: "NJ_V9_E6",
                    label: "Bản up V9 (VanTranidol_NokiaE6)",
                    multiplier: 1,
                    bundledJarName: "VanTranidol_NokiaE6.jar"
                ),
            ]
        ),
        CatalogProduct(
            id: "AVATAR",
            name: "Avatar",
            subtitle: "Chọn file .jar Avatar trong máy để chơi",
            iconKey: "avatar",
            variants: [
                CatalogVariant(
                    productId: "AVATAR",
                    variantId: "AVATAR_LOCAL",
                    label: "Thêm bản Avatar (.jar / .zip)",
                    multiplier: 1,
                    bundledJarName: nil
                ),
            ]
        ),
    ]

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.rootDir = base.appendingPathComponent("J2ME NST", isDirectory: true)
        self.externalDir = rootDir.appendingPathComponent("external", isDirectory: true)
        self.bundledDir = rootDir.appendingPathComponent("bundled", isDirectory: true)
        self.configsDir = rootDir.appendingPathComponent("configs", isDirectory: true)
        self.iconsDir = rootDir.appendingPathComponent("icons", isDirectory: true)
        self.displayPath = rootDir.appendingPathComponent("display.json")
        self.homeTabPath = rootDir.appendingPathComponent("home_tab.txt")
        self.proxyPath = rootDir.appendingPathComponent("proxy_config.json")

        let fm = FileManager.default
        for dir in [rootDir, externalDir, bundledDir, configsDir, iconsDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        if let data = try? Data(contentsOf: displayPath),
           let loaded = try? JSONDecoder().decode(DisplayPrefs.self, from: data) {
            self.displayPrefs = loaded
        } else {
            self.displayPrefs = DisplayPrefs()
        }

        if let rawTab = try? String(contentsOf: homeTabPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let tab = HomeTab(rawValue: rawTab) {
            self.currentTab = tab
        } else {
            self.currentTab = .mod
        }

        ensureBundledMods()
        reloadExternal()
    }

    func saveDisplayPrefs() {
        if let data = try? JSONEncoder().encode(displayPrefs) {
            try? data.write(to: displayPath, options: .atomic)
        }
    }

    func saveHomeTab(_ tab: HomeTab) {
        currentTab = tab
        try? tab.rawValue.write(to: homeTabPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Bundled Mods

    private func ensureBundledMods() {
        guard let resURL = Bundle.main.resourceURL else { return }
        let runtimeDir = resURL.appendingPathComponent("Runtime/j2mejs", isDirectory: true)
        let fm = FileManager.default

        for product in products {
            for variant in product.variants {
                guard let jarName = variant.bundledJarName else { continue }
                let srcJar = runtimeDir.appendingPathComponent(jarName)
                guard fm.fileExists(atPath: srcJar.path) else { continue }

                let destDir = bundledDir.appendingPathComponent(variant.variantId, isDirectory: true)
                let destJar = destDir.appendingPathComponent("game.jar")
                try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)

                if !fm.fileExists(atPath: destJar.path) {
                    try? fm.copyItem(at: srcJar, to: destJar)
                }

                let meta = JarInspector.inspectJar(at: destJar)
                let size = (try? fm.attributesOfItem(atPath: destJar.path)[.size] as? Int64) ?? 0
                let entry = GameEntry(
                    id: variant.variantId,
                    name: variant.label,
                    vendor: meta?.vendor.isEmpty == false ? meta!.vendor : "NST",
                    version: meta?.version.isEmpty == false ? meta!.version : "1.0",
                    isExternal: false,
                    iconKey: product.iconKey,
                    fileSize: size,
                    importedAt: Date()
                )
                bundledEntries[variant.variantId] = entry
            }
        }
    }

    func allPlayableGames() -> [GameEntry] {
        var list: [GameEntry] = []
        for product in products {
            for variant in product.variants {
                if let e = bundledEntries[variant.variantId] {
                    list.append(e)
                }
            }
        }
        list.append(contentsOf: externalGames)
        return list
    }

    func entry(for id: String) -> GameEntry? {
        if let b = bundledEntries[id] { return b }
        return externalGames.first(where: { $0.id == id })
    }

    func jarURL(for entry: GameEntry) -> URL {
        let dir = entry.isExternal ? externalDir : bundledDir
        return dir.appendingPathComponent(entry.id, isDirectory: true).appendingPathComponent("game.jar")
    }

    func saveURL(for entry: GameEntry, slot: Int) -> URL {
        let dir = entry.isExternal ? externalDir : bundledDir
        let gameDir = dir.appendingPathComponent(entry.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
        let name = slot <= 0 ? "save.zip" : "save_slot\(slot).zip"
        return gameDir.appendingPathComponent(name)
    }

    // MARK: - Icons

    func productIcon(_ key: String) -> UIImage? {
        if let cached = iconCache["prod_\(key)"] { return cached }
        if let url = Bundle.main.url(forResource: key, withExtension: "jpg"),
           let img = UIImage(contentsOfFile: url.path) {
            iconCache["prod_\(key)"] = img
            return img
        }
        if let url = Bundle.main.url(forResource: key, withExtension: "png"),
           let img = UIImage(contentsOfFile: url.path) {
            iconCache["prod_\(key)"] = img
            return img
        }
        return nil
    }

    func icon(for entry: GameEntry) -> UIImage? {
        if let cached = iconCache[entry.id] { return cached }

        let dir = entry.isExternal ? externalDir : bundledDir
        let iconFile = dir.appendingPathComponent(entry.id, isDirectory: true).appendingPathComponent("icon.png")
        if let img = UIImage(contentsOfFile: iconFile.path) {
            iconCache[entry.id] = img
            return img
        }

        if let key = entry.iconKey, let prodImg = productIcon(key) {
            iconCache[entry.id] = prodImg
            return prodImg
        }

        return nil
    }

    // MARK: - Per-Game Config

    func loadConfig(for gameId: String) -> GameConfig {
        let url = configsDir.appendingPathComponent("\(gameId).json")
        if let data = try? Data(contentsOf: url),
           let cfg = try? JSONDecoder().decode(GameConfig.self, from: data) {
            return cfg
        }
        return GameConfig()
    }

    func saveConfig(_ config: GameConfig, for gameId: String) {
        let url = configsDir.appendingPathComponent("\(gameId).json")
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func resetConfig(for gameId: String) -> GameConfig {
        let fresh = GameConfig()
        saveConfig(fresh, for: gameId)
        return fresh
    }

    // MARK: - External Games CRUD & Import (.jar / .zip)

    func reloadExternal() {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: externalDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            externalGames = []
            return
        }

        var loaded: [GameEntry] = []
        let decoder = JSONDecoder()
        for dir in dirs {
            let infoURL = dir.appendingPathComponent("info.json")
            let jarURL = dir.appendingPathComponent("game.jar")
            guard fm.fileExists(atPath: jarURL.path),
                  let data = try? Data(contentsOf: infoURL),
                  let entry = try? decoder.decode(GameEntry.self, from: data) else {
                continue
            }
            loaded.append(entry)
        }
        loaded.sort { $0.importedAt > $1.importedAt }
        externalGames = loaded
    }

    struct ImportOutcome {
        var installed: [GameEntry] = []
        var rejected: [(String, String)] = []
    }

    func importURLs(_ urls: [URL]) -> ImportOutcome {
        var outcome = ImportOutcome()

        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }

            let fileName = url.lastPathComponent
            guard let rawData = readCoordinated(url: url) else {
                outcome.rejected.append((fileName, "không đọc được file"))
                continue
            }

            guard rawData.count >= 4, rawData[0] == 0x50, rawData[1] == 0x4B else {
                outcome.rejected.append((fileName, "không phải file jar"))
                continue
            }

            // First try as direct J2ME JAR
            if let meta = JarInspector.inspectJarData(rawData, fallbackName: url.deletingPathExtension().lastPathComponent) {
                if let entry = installExternalJar(bytes: rawData, meta: meta) {
                    outcome.installed.append(entry)
                } else {
                    outcome.rejected.append((fileName, "không lưu được"))
                }
                continue
            }

            // Otherwise check if it's a ZIP wrapping one or more JARs
            let embedded = JarInspector.extractEmbeddedJars(from: rawData)
            if embedded.isEmpty {
                outcome.rejected.append((fileName, "không phải game J2ME (thiếu MIDlet-1)"))
                continue
            }

            for (jarName, jarBytes) in embedded {
                let fallback = (jarName as NSString).deletingPathExtension
                if let meta = JarInspector.inspectJarData(jarBytes, fallbackName: fallback) {
                    if let entry = installExternalJar(bytes: jarBytes, meta: meta) {
                        outcome.installed.append(entry)
                    } else {
                        outcome.rejected.append((jarName, "không lưu được"))
                    }
                } else {
                    outcome.rejected.append((jarName, "không phải game J2ME (thiếu MIDlet-1)"))
                }
            }
        }

        reloadExternal()
        return outcome
    }

    func scanDocumentsDirectory() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first,
              let files = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return
        }
        let candidates = files.filter {
            let ext = $0.pathExtension.lowercased()
            return ext == "jar" || ext == "zip"
        }
        guard !candidates.isEmpty else { return }
        let res = importURLs(candidates)
        if !res.installed.isEmpty {
            for f in candidates {
                try? fm.removeItem(at: f)
            }
        }
    }

    func rename(entry: GameEntry, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, entry.isExternal else { return }
        guard let idx = externalGames.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = externalGames[idx]
        updated.name = trimmed
        let infoURL = externalDir.appendingPathComponent(entry.id, isDirectory: true).appendingPathComponent("info.json")
        if let data = try? JSONEncoder().encode(updated) {
            try? data.write(to: infoURL, options: .atomic)
            externalGames[idx] = updated
        }
    }

    func clearSaveData(for entry: GameEntry) {
        let fm = FileManager.default
        let dir = (entry.isExternal ? externalDir : bundledDir)
            .appendingPathComponent(entry.id, isDirectory: true)
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for item in items where item.lastPathComponent.hasPrefix("save") && item.pathExtension == "zip" {
            try? fm.removeItem(at: item)
        }
    }

    func deleteExternal(entry: GameEntry) {
        guard entry.isExternal else { return }
        let fm = FileManager.default
        let gameDir = externalDir.appendingPathComponent(entry.id, isDirectory: true)
        try? fm.removeItem(at: gameDir)
        let cfgURL = configsDir.appendingPathComponent("\(entry.id).json")
        try? fm.removeItem(at: cfgURL)
        iconCache.removeValue(forKey: entry.id)
        ProxyStore.shared.clearGame(entry.id)
        reloadExternal()
    }

    private func installExternalJar(bytes: Data, meta: JarMetadata) -> GameEntry? {
        let fm = FileManager.default
        let id = "ext_\(UUID().uuidString.prefix(12).lowercased())"
        let dir = externalDir.appendingPathComponent(id, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let jarURL = dir.appendingPathComponent("game.jar")
            try bytes.write(to: jarURL, options: .atomic)

            if let iconData = meta.iconData {
                let iconURL = dir.appendingPathComponent("icon.png")
                try? iconData.write(to: iconURL, options: .atomic)
            }

            let entry = GameEntry(
                id: id,
                name: meta.name,
                vendor: meta.vendor,
                version: meta.version,
                isExternal: true,
                iconKey: nil,
                fileSize: Int64(bytes.count),
                importedAt: Date()
            )
            let infoData = try JSONEncoder().encode(entry)
            try infoData.write(to: dir.appendingPathComponent("info.json"), options: .atomic)
            return entry
        } catch {
            try? fm.removeItem(at: dir)
            return nil
        }
    }

    private func readCoordinated(url: URL) -> Data? {
        if let direct = try? Data(contentsOf: url) {
            return direct
        }
        var coordErr: NSError?
        var readData: Data?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordErr) { coordURL in
            readData = try? Data(contentsOf: coordURL)
        }
        return readData
    }
}
