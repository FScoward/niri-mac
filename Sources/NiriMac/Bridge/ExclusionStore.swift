import Foundation

/// 除外アプリ設定の永続化を担う。読み書きのみ、副作用なし。
enum ExclusionStore {
    private struct Payload: Codable {
        var excludedBundleIDs: [String]
    }

    /// ファイルから除外 bundleID セットを読み込む。
    /// ファイル不在・パース失敗時は空セットを返す。
    static func load(from url: URL = defaultURL) -> Set<String> {
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            print("[exclusion] ⚠️ 設定ファイルのパースに失敗しました: \(url.path)")
            return []
        }
        return Set(payload.excludedBundleIDs)
    }

    /// 除外 bundleID セットをファイルに書き込む。
    /// ディレクトリが存在しない場合は自動作成する。
    static func save(_ ids: Set<String>, to url: URL = defaultURL) {
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let payload = Payload(excludedBundleIDs: ids.sorted())
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[exclusion] ⚠️ 設定ファイルの保存に失敗しました: \(error)")
        }
    }

    static let defaultURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".config")
            .appendingPathComponent("niri-mac")
            .appendingPathComponent("excluded-apps.json")
    }()
}
