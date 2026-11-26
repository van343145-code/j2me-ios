import Compression
import CoreGraphics
import Foundation
import UIKit

// MARK: - Home & Catalog Models

enum HomeTab: String, Codable {
    case mod
    case own

    var title: String {
        switch self {
        case .mod: return "Bản mod NST"
        case .own: return "Bản của bạn"
        }
    }
}

struct CatalogVariant: Codable, Equatable {
    let productId: String
    let variantId: String
    let label: String
    let multiplier: Int
    let bundledJarName: String?
}

struct CatalogProduct: Equatable {
    let id: String
    let name: String
    let subtitle: String
    let iconKey: String
    let variants: [CatalogVariant]
}

struct GameEntry: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var vendor: String
    var version: String
    let isExternal: Bool
    let iconKey: String?
    let fileSize: Int64
    let importedAt: Date

    var subtitle: String {
        var parts: [String] = []
        if !vendor.isEmpty { parts.append(vendor) }
        if !version.isEmpty { parts.append("v\(version)") }
        if parts.isEmpty {
            return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - GameConfig (Exact 1:1 defaults from J2me.Host.GameConfig)

struct GameConfig: Codable, Equatable {
    var screenWidth: Int = 240
    var screenHeight: Int = 320
    var screenBackgroundColor: Int = 0xD0D0D0
    var screenScaleType: Int = 1         // 0 = 1:1, 1 = fit aspect, 2 = stretch
    var screenGravity: Int = 1           // 1 = top-center
    var screenScaleRatio: Int = 100
    var screenFilter: Bool = false
    var forceFullscreen: Bool = false
    var showFps: Bool = false
    var fpsLimit: Int = 30
    var fontSizeSmall: Int = 18
    var fontSizeMedium: Int = 22
    var fontSizeLarge: Int = 26
    var fontAntiAlias: Bool = true
    var touchInput: Bool = true
    var vkEnabled: Bool = true
    var vkType: Int = 7
    var vkAlpha: Int = 64
    var vkBgColor: Int = 0xD0D0D0
    var vkFgColor: Int = 0x000080
    var vkBgColorSelected: Int = 0x000080
    var vkFgColorSelected: Int = 0xFFFFFF
    var vkOutlineColor: Int = 0xFFFFFF
    var vkFeedback: Bool = false
    var vkForceOpacity: Bool = false
}

// MARK: - DisplayPrefs (Exact 1:1 from J2me.Host.DisplayPrefs)

struct DisplayPrefs: Codable, Equatable {
    static let minSize = 64
    static let maxSize = 2048
    static let defaultWidth = 240

    var width: Int = DisplayPrefs.defaultWidth
    var height: Int = 0 // 0 = auto-fit to screen aspect above keypad

    static func clampSize(_ v: Int) -> Int {
        min(max(v, minSize), maxSize)
    }

    mutating func setFromText(widthText: String, heightText: String, autoFor: ((Int) -> Int)? = nil) {
        let trimmedW = widthText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedH = heightText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsedW = Int(trimmedW), parsedW > 0 {
            width = Self.clampSize(parsedW)
        } else {
            width = Self.defaultWidth
        }

        if trimmedH.isEmpty {
            height = 0
        } else if let parsedH = Int(trimmedH), parsedH > 0 {
            let clamped = Self.clampSize(parsedH)
            if let auto = autoFor?(width), clamped == auto {
                height = 0
            } else {
                height = clamped
            }
        } else {
            height = 0
        }
    }

    func describe(autoHeight: Int) -> String {
        if height > 0 {
            return "\(width) × \(height)"
        }
        return "\(width) × \(autoHeight) (tự khớp)"
    }
}

struct VirtualSize: Equatable {
    let width: Int
    let height: Int
    let autoFit: Bool
}

// MARK: - PlayLayout & GameLayout (Exact 1:1 math from J2me.Host.PlayLayout & GameLayout)

enum PlayLayout {
    static let tabBar: CGFloat = 44.0
    static let maxBandShare: CGFloat = 0.45

    static func keySizeFor(width: CGFloat, height: CGFloat) -> CGFloat {
        let shortSide = min(width, height)
        let longSide = max(width, height)
        guard shortSide > 0 else { return 48 }
        if width <= height && (longSide / shortSide) >= 2.0 {
            return shortSide / 6.5
        }
        return longSide / 12.0
    }

    static func band(areaW: CGFloat, areaH: CGFloat) -> CGFloat {
        let ks = keySizeFor(width: areaW, height: areaH + tabBar)
        return min(ks * 3.0, areaH * maxBandShare)
    }

    static func reservesBand(areaW: CGFloat, areaH: CGFloat, keyboard: Bool) -> Bool {
        keyboard && areaH > areaW
    }

    static func autoVirtualHeight(areaW: CGFloat, areaH: CGFloat, vw: Int, keyboard: Bool = true) -> Int {
        guard areaW > 0, areaH > 0 else { return max(64, (vw * 4) / 3) }
        let b: CGFloat = keyboard ? band(areaW: areaW, areaH: areaH) : 0
        let availH = max(1, areaH - b)
        let raw = Int(round((availH * CGFloat(vw)) / areaW))
        let minH = (vw * 3) / 4
        let maxH = vw * 2
        return min(max(raw, minH), maxH)
    }

    static func resolve(prefs: DisplayPrefs, keyboard: Bool, areaW: CGFloat, areaH: CGFloat) -> VirtualSize {
        let w = DisplayPrefs.clampSize(prefs.width)
        if prefs.height > 0 {
            return VirtualSize(width: w, height: DisplayPrefs.clampSize(prefs.height), autoFit: false)
        }
        if areaH > areaW {
            let h = autoVirtualHeight(areaW: areaW, areaH: areaH, vw: w, keyboard: keyboard)
            return VirtualSize(width: w, height: h, autoFit: true)
        } else {
            let h = max(DisplayPrefs.minSize, (w * 4) / 3)
            return VirtualSize(width: w, height: h, autoFit: true)
        }
    }

    static func autoHeightFor(width: Int, areaW: CGFloat, areaH: CGFloat) -> Int {
        let clampedW = DisplayPrefs.clampSize(width)
        if areaH > areaW {
            return autoVirtualHeight(areaW: areaW, areaH: areaH, vw: clampedW, keyboard: true)
        }
        return max(DisplayPrefs.minSize, (clampedW * 4) / 3)
    }

    static func gameRect(
        areaW: CGFloat,
        areaH: CGFloat,
        vw: Int,
        vh: Int,
        config: GameConfig,
        keyboard: Bool,
        autoFit: Bool,
        pixelScale: CGFloat
    ) -> CGRect {
        let reserved: CGFloat = (reservesBand(areaW: areaW, areaH: areaH, keyboard: keyboard) && autoFit)
            ? band(areaW: areaW, areaH: areaH)
            : (reservesBand(areaW: areaW, areaH: areaH, keyboard: keyboard) ? band(areaW: areaW, areaH: areaH) : 0)
        let availH = max(1, areaH - reserved)
        return GameLayout.fit(
            areaW: areaW,
            areaH: availH,
            vw: vw,
            vh: vh,
            scaleType: config.forceFullscreen ? 2 : config.screenScaleType,
            scaleRatio: config.screenScaleRatio,
            gravity: config.screenGravity,
            pixelScale: pixelScale
        )
    }
}

enum GameLayout {
    static func fit(
        areaW: CGFloat,
        areaH: CGFloat,
        vw: Int,
        vh: Int,
        scaleType: Int,
        scaleRatio: Int,
        gravity: Int,
        pixelScale: CGFloat
    ) -> CGRect {
        let fvw = max(1, CGFloat(vw))
        let fvh = max(1, CGFloat(vh))
        var drawW: CGFloat
        var drawH: CGFloat

        switch scaleType {
        case 2: // stretch
            drawW = areaW
            drawH = areaH
        case 0: // 1:1
            let ps = max(1, pixelScale)
            drawW = fvw / ps
            drawH = fvh / ps
        default: // 1 = fit aspect
            let s = min(areaW / fvw, areaH / fvh)
            drawW = fvw * s
            drawH = fvh * s
        }

        let maxRatio = (scaleType == 0) ? 1000 : 100
        let ratio = CGFloat(min(max(scaleRatio, 1), maxRatio)) / 100.0
        drawW *= ratio
        drawH *= ratio

        let remW = areaW - drawW
        let remH = areaH - drawH
        let x: CGFloat
        let y: CGFloat

        switch gravity {
        case 0: // left-center
            x = 0
            y = remH * 0.5
        case 1: // top-center (J2ME NST default!)
            x = remW * 0.5
            y = 0
        case 2: // center
            x = remW * 0.5
            y = remH * 0.5
        case 3: // right-center
            x = remW
            y = remH * 0.5
        case 4: // bottom-center
            x = remW * 0.5
            y = remH
        default:
            x = remW * 0.5
            y = remH * 0.5
        }

        return CGRect(x: floor(x), y: floor(y), width: ceil(drawW), height: ceil(drawH))
    }
}

// MARK: - NstKeyboard Exact 15-Key Layout (Ported 1:1 from J2me.Host.NstKeyboard)

final class VKey {
    let label: String
    let code: Int
    let code2: Int
    let action: Int // 0 = none, 1 = Tab, 2 = Size
    var rect: CGRect = .zero
    var pressed: Bool = false
    var visible: Bool = true

    init(label: String, code: Int, code2: Int = 0, action: Int = 0) {
        self.label = label
        self.code = code
        self.code2 = code2
        self.action = action
    }
}

final class NstKeyboardModel {
    static let actionNone = 0
    static let actionTab = 1
    static let actionSize = 2

    private(set) var keys: [VKey] = []
    private(set) var keySize: CGFloat = 56
    private(set) var keyGap: CGFloat = 2.2
    private(set) var screenRect: CGRect = .zero
    private(set) var gameRect: CGRect = .zero

    private let upLeft: VKey
    private let kUp: VKey
    private let upRight: VKey
    private let kLeft: VKey
    private let fire: VKey
    private let kRight: VKey
    private let downLeft: VKey
    private let kDown: VKey
    private let downRight: VKey
    private let f1: VKey
    private let f2: VKey
    private let hp: VKey
    private let mp: VKey
    private let tab: VKey
    private let sizeKey: VKey

    init() {
        // Exact order & exact MIDP keycodes from NstKeyboard..ctor!
        upLeft    = VKey(label: "↖", code: -1, code2: -3)
        kUp       = VKey(label: "↑", code: -1)
        upRight   = VKey(label: "↗", code: -1, code2: -4)
        kLeft     = VKey(label: "←", code: -3)
        fire      = VKey(label: "OK", code: -5)
        kRight    = VKey(label: "→", code: -4)
        downLeft  = VKey(label: "↙", code: -2, code2: -3)
        kDown     = VKey(label: "↓", code: -2)
        downRight = VKey(label: "↘", code: -2, code2: -4)
        f1        = VKey(label: "F1", code: -6)
        f2        = VKey(label: "F2", code: -7)
        hp        = VKey(label: "HP", code: 42)  // '*' star key in Ninja School = HP!
        mp        = VKey(label: "MP", code: 35)  // '#' pound key in Ninja School = MP!
        tab       = VKey(label: "Tab", code: 0, action: NstKeyboardModel.actionTab)
        sizeKey   = VKey(label: "Size", code: 0, action: NstKeyboardModel.actionSize)

        keys = [
            upLeft, kUp, upRight,
            kLeft, fire, kRight,
            downLeft, kDown, downRight,
            f1, f2, hp, mp, tab, sizeKey,
        ]
    }

    func layout(screen: CGRect, game: CGRect, tabBar: CGFloat = PlayLayout.tabBar) {
        self.screenRect = screen
        self.gameRect = game

        let ks = PlayLayout.keySizeFor(width: screen.width, height: screen.height + tabBar)
        self.keySize = ks
        self.keyGap = ks * 0.04

        let belowGame = screen.maxY - game.maxY
        var hRatio = (belowGame / 3.0) / max(1, ks)
        if hRatio < 0.5 { hRatio = 1.0 }
        let kh = ks * hRatio

        // Right 3x3 D-Pad anchored to bottom-right
        downRight.rect = CGRect(x: screen.maxX - ks, y: screen.maxY - kh, width: ks, height: kh)
        kDown.rect     = west(of: downRight.rect)
        downLeft.rect  = west(of: kDown.rect)
        kLeft.rect     = north(of: downLeft.rect)
        kRight.rect    = north(of: downRight.rect)
        fire.rect      = north(of: kDown.rect)
        upRight.rect   = north(of: kRight.rect)
        kUp.rect       = west(of: upRight.rect)
        upLeft.rect    = west(of: kUp.rect)

        // Left 2x3 utility cluster anchored to bottom-left (with 0.25 * ks column gap!)
        tab.rect = CGRect(x: screen.minX, y: screen.maxY - kh, width: ks, height: kh)
        let eastTab = east(of: tab.rect)
        sizeKey.rect = eastTab.offsetBy(dx: ks * 0.25, dy: 0)
        hp.rect = north(of: tab.rect)
        mp.rect = north(of: sizeKey.rect)
        f1.rect = north(of: hp.rect)
        f2.rect = north(of: mp.rect)
    }

    func corner(for key: VKey) -> CGFloat {
        min(key.rect.width, key.rect.height) * 0.25
    }

    func keyObscuresGame(_ key: VKey) -> Bool {
        key.rect.intersects(gameRect)
    }

    func hitTest(_ point: CGPoint) -> VKey? {
        for key in keys.reversed() where key.visible {
            if key.rect.contains(point) {
                return key
            }
        }
        return nil
    }

    private func west(of r: CGRect) -> CGRect {
        CGRect(x: r.minX - r.width, y: r.minY, width: r.width, height: r.height)
    }

    private func east(of r: CGRect) -> CGRect {
        CGRect(x: r.maxX, y: r.minY, width: r.width, height: r.height)
    }

    private func north(of r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: r.minY - r.height, width: r.width, height: r.height)
    }
}

// MARK: - Lightweight Pure-Swift JAR/ZIP Inspector (Reads Manifest & MIDlet-Icon!)

struct JarMetadata {
    let name: String
    let vendor: String
    let version: String
    let mainClass: String
    let iconData: Data?
}

enum JarInspector {
    private struct ZipEntry {
        let name: String
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    static func inspectJar(at url: URL) -> JarMetadata? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return inspectJarData(data, fallbackName: url.deletingPathExtension().lastPathComponent)
    }

    static func inspectJarData(_ data: Data, fallbackName: String) -> JarMetadata? {
        let entries = parseCentralDirectory(data)
        guard !entries.isEmpty else { return nil }

        guard let manifestEntry = entries.first(where: { $0.name.uppercased() == "META-INF/MANIFEST.MF" }),
              let manifestData = extract(entry: manifestEntry, from: data),
              let manifestText = String(data: manifestData, encoding: .utf8)
                ?? String(data: manifestData, encoding: .isoLatin1) else {
            return nil
        }

        let props = parseManifest(manifestText)
        guard let midlet1 = props["MIDLET-1"] else { return nil }
        let parts = midlet1.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let mainClass = parts.last, !mainClass.isEmpty else { return nil }

        let midletName = props["MIDLET-NAME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let part0 = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (midletName?.isEmpty == false ? midletName : nil)
            ?? (part0?.isEmpty == false ? part0 : nil)
            ?? fallbackName
        let vendor = props["MIDLET-VENDOR"] ?? ""
        let version = props["MIDLET-VERSION"] ?? ""

        // Locate icon path (MIDlet-Icon or 2nd field of MIDlet-1)
        var iconCandidates: [String] = []
        if let rawIcon = props["MIDLET-ICON"], !rawIcon.isEmpty {
            iconCandidates.append(rawIcon)
        }
        if parts.count >= 2 && !parts[1].isEmpty {
            iconCandidates.append(parts[1])
        }

        var iconData: Data?
        for cand in iconCandidates {
            let normalized = cand.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            if let entry = entries.first(where: {
                $0.name.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).caseInsensitiveCompare(normalized) == .orderedSame
            }), let extracted = extract(entry: entry, from: data), UIImage(data: extracted) != nil {
                iconData = extracted
                break
            }
        }

        return JarMetadata(
            name: title,
            vendor: vendor,
            version: version,
            mainClass: mainClass,
            iconData: iconData
        )
    }

    /// If a `.zip` file wraps one or more `.jar` files, extract them as `(filename, bytes)`.
    static func extractEmbeddedJars(from zipData: Data) -> [(String, Data)] {
        let entries = parseCentralDirectory(zipData)
        var out: [(String, Data)] = []
        for entry in entries {
            guard entry.name.lowercased().hasSuffix(".jar"),
                  !entry.name.contains("__MACOSX"),
                  let bytes = extract(entry: entry, from: zipData),
                  bytes.count >= 4,
                  bytes[0] == 0x50, bytes[1] == 0x4B else {
                continue
            }
            let base = (entry.name as NSString).lastPathComponent
            out.append((base, bytes))
        }
        return out
    }

    private static func parseManifest(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var currentKey: String?
        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix(" "), let key = currentKey {
                result[key, default: ""] += String(line.dropFirst())
            } else if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                result[key] = value
                currentKey = key
            } else {
                currentKey = nil
            }
        }
        return result
    }

    private static func parseCentralDirectory(_ data: Data) -> [ZipEntry] {
        let count = data.count
        guard count >= 22 else { return [] }

        // Find End of Central Directory (0x06054b50)
        let searchStart = max(0, count - 65557)
        var eocd = -1
        for i in stride(from: count - 22, through: searchStart, by: -1) {
            if data[i] == 0x50 && data[i + 1] == 0x4B && data[i + 2] == 0x05 && data[i + 3] == 0x06 {
                eocd = i
                break
            }
        }
        guard eocd >= 0 else { return [] }

        let totalEntries = Int(readU16(data, eocd + 10))
        let cdOffset = Int(readU32(data, eocd + 16))
        guard cdOffset >= 0, cdOffset < count else { return [] }

        var entries: [ZipEntry] = []
        var pos = cdOffset
        for _ in 0..<totalEntries {
            guard pos + 46 <= count,
                  data[pos] == 0x50, data[pos + 1] == 0x4B, data[pos + 2] == 0x01, data[pos + 3] == 0x02 else {
                break
            }
            let method = readU16(data, pos + 10)
            let compSize = Int(readU32(data, pos + 20))
            let uncompSize = Int(readU32(data, pos + 24))
            let nameLen = Int(readU16(data, pos + 28))
            let extraLen = Int(readU16(data, pos + 30))
            let commentLen = Int(readU16(data, pos + 32))
            let localOff = Int(readU32(data, pos + 42))
            let nameEnd = pos + 46 + nameLen
            guard nameEnd <= count else { break }

            let name = String(data: data.subdata(in: (pos + 46)..<nameEnd), encoding: .utf8) ?? ""
            entries.append(ZipEntry(
                name: name,
                compressionMethod: method,
                compressedSize: compSize,
                uncompressedSize: uncompSize,
                localHeaderOffset: localOff
            ))
            pos = nameEnd + extraLen + commentLen
        }
        return entries
    }

    private static func extract(entry: ZipEntry, from data: Data) -> Data? {
        let off = entry.localHeaderOffset
        guard off >= 0, off + 30 <= data.count,
              data[off] == 0x50, data[off + 1] == 0x4B, data[off + 2] == 0x03, data[off + 3] == 0x04 else {
            return nil
        }
        let nameLen = Int(readU16(data, off + 26))
        let extraLen = Int(readU16(data, off + 28))
        let dataStart = off + 30 + nameLen + extraLen
        let dataEnd = dataStart + entry.compressedSize
        guard dataStart >= 0, dataEnd <= data.count, entry.uncompressedSize <= 32 * 1024 * 1024 else {
            return nil
        }

        let slice = data.subdata(in: dataStart..<dataEnd)
        if entry.compressionMethod == 0 {
            return slice
        }
        guard entry.compressionMethod == 8 else { return nil }

        let dstCap = max(entry.uncompressedSize, 1)
        var dst = Data(count: dstCap)
        let decodedSize = slice.withUnsafeBytes { srcBuf -> Int in
            guard let srcPtr = srcBuf.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return dst.withUnsafeMutableBytes { dstBuf -> Int in
                guard let dstPtr = dstBuf.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    dstPtr, dstCap,
                    srcPtr, slice.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decodedSize > 0 else { return nil }
        dst.count = decodedSize
        return dst
    }

    private static func readU16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
