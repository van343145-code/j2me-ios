//
//  MidletTabs.swift
//  J2MEEmulator
//
//  1:1 Port of Decade APK org.microemu.cldc.socket.proxy.MidletTabs
//  Reads internal game tabs from JAR MANIFEST.MF
//

import Foundation
import UIKit

struct MidletTab: Equatable {
    let index: Int        // 1-based index (1, 2, 3...)
    let name: String      // Display name (e.g. "1", "2", "Avatar", etc.)
    let prefix: String    // Package / class prefix (e.g. "a", "b", "c", etc.)
}

class MidletTabs {
    private static func prefixOf(_ className: String?) -> String {
        guard let name = className, !name.isEmpty else { return "" }
        let clean = name.replacingOccurrences(of: "/", with: ".").trimmingCharacters(in: .whitespaces)
        if let dotIdx = clean.firstIndex(of: ".") {
            return String(clean[..<dotIdx])
        }
        return clean
    }

    /// Read internal game tabs from a JAR file
    static func read(from jarPath: String?, appName: String? = nil) -> [MidletTab] {
        guard let path = jarPath, !path.isEmpty else {
            return defaultTabs()
        }

        // Try extracting META-INF/MANIFEST.MF from JAR
        guard let manifestData = ZIPReader.extractEntry(zipPath: path, entryName: "META-INF/MANIFEST.MF"),
              let manifestText = String(data: manifestData, encoding: .utf8) else {
            return defaultTabs()
        }

        return parseTabs(from: manifestText, appName: appName)
    }

    /// Parse tabs from manifest text
    static func parseTabs(from text: String, appName: String? = nil) -> [MidletTab] {
        var numberedTabs: [MidletTab] = []
        var midletTabs: [MidletTab] = []

        let lines = text.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let val = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

            // Pattern 1: Numbered index line "0: 1,/icon.png,a.bs"
            if let num = Int(key) {
                let parts = val.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                let name = parts.count > 0 && !parts[0].isEmpty ? parts[0] : "\(num + 1)"
                let cls = parts.count >= 3 ? parts[2] : (parts.count > 0 ? parts.last! : "")
                let prefix = prefixOf(cls)
                let tabPrefix = prefix.isEmpty ? "\(num + 1)" : prefix
                numberedTabs.append(MidletTab(index: num + 1, name: name, prefix: tabPrefix))
                continue
            }

            // Pattern 2: "MIDlet-1: 1,/icon.png,a.bs"
            if key.hasPrefix("MIDlet-"), let mIdx = Int(key.dropFirst(7)) {
                let parts = val.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                let name = parts.count > 0 && !parts[0].isEmpty ? parts[0] : "\(mIdx)"
                let cls = parts.count >= 3 ? parts[2] : (parts.count > 0 ? parts.last! : "")
                let prefix = prefixOf(cls)
                let tabPrefix = prefix.isEmpty ? "\(mIdx)" : prefix
                midletTabs.append(MidletTab(index: mIdx, name: name, prefix: tabPrefix))
                continue
            }
        }

        // If game has numbered tabs (like x27 with 0: 1 ... 26: 27), use ONLY numbered tabs!
        // In that case, MIDlet-1 is just the launcher class (e.g. MrQuyet launcher) and should not be a duplicate tab.
        if numberedTabs.count > 0 {
            numberedTabs.sort { $0.index < $1.index }
            return numberedTabs
        }

        // If game has multiple MIDlet entries (e.g. MIDlet-1, MIDlet-2...)
        if midletTabs.count > 1 {
            midletTabs.sort { $0.index < $1.index }
            return midletTabs
        }

        // If only 1 MIDlet (like Avatar 250 or an AngelChip slot mod):
        let cleanAppName = (appName ?? "").lowercased()
        let isMultiTabMod = cleanAppName.contains("x6") || cleanAppName.contains("x12") ||
                            cleanAppName.contains("x13") || cleanAppName.contains("x24") ||
                            cleanAppName.contains("x27") || cleanAppName.contains("x50") ||
                            cleanAppName.contains("angelchip") || cleanAppName.contains("mrquyet")

        if isMultiTabMod {
            return defaultTabs()
        }

        // For standard single game (like Avatar 250):
        if let single = midletTabs.first {
            let name = single.name.isEmpty ? (appName ?? "Avatar") : single.name
            let prefix = single.prefix.isEmpty ? "a" : single.prefix
            return [MidletTab(index: 1, name: name, prefix: prefix)]
        }

        return defaultTabs()
    }

    /// Default 27 tabs for multi-tab mods (AngelChip / MrQuyet / GameVn24h / SesonBlog)
    static func defaultTabs() -> [MidletTab] {
        var tabs: [MidletTab] = []
        for i in 1...27 {
            let prefix: String
            if i <= 26 {
                let scalar = UnicodeScalar(96 + i)! // 'a'...'z'
                prefix = String(scalar)
            } else {
                prefix = "aa"
            }
            tabs.append(MidletTab(index: i, name: "\(i)", prefix: prefix))
        }
        return tabs
    }
}
