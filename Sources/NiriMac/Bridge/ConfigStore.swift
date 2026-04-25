import AppKit
import Foundation

enum ConfigStore {
    struct Config {
        var meta: NSEvent.ModifierFlags
        var scrollLayout: NSEvent.ModifierFlags
        var scrollFocus: NSEvent.ModifierFlags
    }

    private struct Payload: Codable {
        var metaModifiers: [String]
        var scrollLayoutModifiers: [String]
        var scrollFocusModifiers: [String]
    }

    static func load(from url: URL = defaultURL) -> Config {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return Config(
                meta: [.control, .option],
                scrollLayout: [.option],
                scrollFocus: [.control, .option]
            )
        }
        return Config(
            meta: flags(from: payload.metaModifiers),
            scrollLayout: flags(from: payload.scrollLayoutModifiers),
            scrollFocus: flags(from: payload.scrollFocusModifiers)
        )
    }

    static func save(
        meta: NSEvent.ModifierFlags,
        scrollLayout: NSEvent.ModifierFlags,
        scrollFocus: NSEvent.ModifierFlags,
        to url: URL = defaultURL
    ) {
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let payload = Payload(
                metaModifiers: strings(from: meta),
                scrollLayoutModifiers: strings(from: scrollLayout),
                scrollFocusModifiers: strings(from: scrollFocus)
            )
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[config] ⚠️ 設定ファイルの保存に失敗しました: \(error)")
        }
    }

    static let defaultURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("niri-mac")
            .appendingPathComponent("config.json")
    }()

    private static let modifierPairs: [(String, NSEvent.ModifierFlags)] = [
        ("control", .control),
        ("option",  .option),
        ("command", .command),
        ("shift",   .shift),
    ]

    static func strings(from flags: NSEvent.ModifierFlags) -> [String] {
        modifierPairs.compactMap { name, flag in flags.contains(flag) ? name : nil }
    }

    static func flags(from strings: [String]) -> NSEvent.ModifierFlags {
        strings.reduce(into: NSEvent.ModifierFlags()) { result, s in
            if let pair = modifierPairs.first(where: { $0.0 == s }) {
                result.insert(pair.1)
            }
        }
    }
}
