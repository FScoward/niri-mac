# タイリング除外アプリ機能 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 特定アプリをタイリング管理から完全除外し、ステータスバーメニューと JSON ファイルで設定を永続化する。

**Architecture:** `ExclusionStore`（Bridge層）が `~/.config/niri-mac/excluded-apps.json` を読み書きし、`LayoutConfig.excludedBundleIDs` に値を渡す。`WindowManager` はウィンドウ登録時に bundleID をチェックして除外。`NiriMacApp` がステータスバーの「Excluded Apps」サブメニューを通じて `WindowManager` の公開 API を呼び出す。

**Tech Stack:** Swift 5.9+, Swift Testing framework (`import Testing`), Foundation (FileManager/JSONEncoder)

---

## ファイルマップ

| ファイル | 変更種別 | 責務 |
|----------|----------|------|
| `Sources/NiriMac/Bridge/ExclusionStore.swift` | **新規作成** | JSON の読み書きのみ |
| `Tests/NiriMacTests/ExclusionStoreTests.swift` | **新規作成** | ExclusionStore のユニットテスト |
| `Sources/NiriMac/Engine/LayoutConfig.swift` | **修正** | `excludedBundleIDs: Set<String>` フィールド追加 |
| `Sources/NiriMac/Orchestrator/WindowManager.swift` | **修正** | `isExcluded` / `excludeApp` / `includeApp` / `focusedAppBundleID` / `excludedApps` 追加、登録ロジックにガード追加 |
| `Sources/NiriMac/App/NiriMacApp.swift` | **修正** | 「Excluded Apps」サブメニュー追加 |

---

## Task 1: ExclusionStore を実装する

**Files:**
- Create: `Sources/NiriMac/Bridge/ExclusionStore.swift`
- Create: `Tests/NiriMacTests/ExclusionStoreTests.swift`

### Step 1.1: テストファイルを作成して失敗させる

- [ ] `Tests/NiriMacTests/ExclusionStoreTests.swift` を作成する:

```swift
import Testing
import Foundation
@testable import NiriMac

@Suite("ExclusionStore Tests")
struct ExclusionStoreTests {

    // テスト用に一時ディレクトリを使う
    private func makeTempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("excluded-apps.json")
    }

    @Test func loadReturnsEmptyWhenFileNotFound() {
        let url = makeTempURL()
        let result = ExclusionStore.load(from: url)
        #expect(result.isEmpty)
    }

    @Test func saveAndLoad() throws {
        let url = makeTempURL()
        let ids: Set<String> = ["com.apple.finder", "com.docker.docker"]
        ExclusionStore.save(ids, to: url)
        let loaded = ExclusionStore.load(from: url)
        #expect(loaded == ids)
    }

    @Test func loadReturnsEmptyWhenFileCorrupted() throws {
        let url = makeTempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        let result = ExclusionStore.load(from: url)
        #expect(result.isEmpty)
    }

    @Test func saveCreatesDirectoryIfNeeded() {
        let url = makeTempURL()
        // ディレクトリを事前作成しない
        ExclusionStore.save(["com.test.app"], to: url)
        let loaded = ExclusionStore.load(from: url)
        #expect(loaded == ["com.test.app"])
    }
}
```

- [ ] テストを実行して失敗を確認する:

```bash
swift test --filter ExclusionStoreTests 2>&1 | tail -20
```

Expected: `error: cannot find type 'ExclusionStore' in scope`

### Step 1.2: ExclusionStore を実装する

- [ ] `Sources/NiriMac/Bridge/ExclusionStore.swift` を作成する:

```swift
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
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = Payload(excludedBundleIDs: ids.sorted())
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static let defaultURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".config")
            .appendingPathComponent("niri-mac")
            .appendingPathComponent("excluded-apps.json")
    }()
}
```

### Step 1.3: テストを実行して全て通ることを確認する

- [ ] テストを実行する:

```bash
swift test --filter ExclusionStoreTests 2>&1 | tail -20
```

Expected: `Test run with 4 tests passed`

### Step 1.4: コミット

- [ ] コミットする:

```bash
git add Sources/NiriMac/Bridge/ExclusionStore.swift Tests/NiriMacTests/ExclusionStoreTests.swift
git commit -m "feat: ExclusionStore — 除外アプリ設定の JSON 永続化"
```

---

## Task 2: LayoutConfig に excludedBundleIDs を追加する

**Files:**
- Modify: `Sources/NiriMac/Engine/LayoutConfig.swift`

### Step 2.1: `LayoutConfig` にフィールドを追加する

- [ ] `Sources/NiriMac/Engine/LayoutConfig.swift` の末尾（`}`の直前）に追加する:

```swift
    // MARK: - App Exclusion

    /// タイリングから除外するアプリの bundleID セット
    var excludedBundleIDs: Set<String> = []
```

完成後のファイル末尾:

```swift
    /// ディムの不透明度（0.0〜1.0）
    var focusDimOpacity: CGFloat = 0.4

    // MARK: - App Exclusion

    /// タイリングから除外するアプリの bundleID セット
    var excludedBundleIDs: Set<String> = []
}
```

### Step 2.2: ビルドが通ることを確認する

- [ ] ビルドする:

```bash
swift build 2>&1 | tail -10
```

Expected: `Build complete!`

### Step 2.3: コミット

- [ ] コミットする:

```bash
git add Sources/NiriMac/Engine/LayoutConfig.swift
git commit -m "feat: LayoutConfig に excludedBundleIDs フィールドを追加"
```

---

## Task 3: WindowManager に除外ロジックと公開 API を追加する

**Files:**
- Modify: `Sources/NiriMac/Orchestrator/WindowManager.swift`

### Step 3.1: `start()` で ExclusionStore から設定を読み込む

- [ ] `WindowManager.start()` の `setupScreens()` 呼び出しより前に追記する:

```swift
// 除外アプリ設定を読み込む
config.excludedBundleIDs = ExclusionStore.load()
niriLog("[exclusion] loaded \(config.excludedBundleIDs.count) excluded apps: \(config.excludedBundleIDs.sorted())")
```

完成後のイメージ（`start()` 内、`guard AccessibilityBridge.checkPermission()` の後）:

```swift
// 除外アプリ設定を読み込む
config.excludedBundleIDs = ExclusionStore.load()
niriLog("[exclusion] loaded \(config.excludedBundleIDs.count) excluded apps: \(config.excludedBundleIDs.sorted())")

setupScreens()
discoverExistingWindows()
```

### Step 3.2: `isExcluded` ヘルパーを追加する

- [ ] `WindowManager` の `// MARK: - Setup` セクションの直前（`private func setupScreens()` の上）に追加する:

```swift
// MARK: - App Exclusion

private func isExcluded(_ window: WindowInfo) -> Bool {
    guard let bundleID = window.ownerBundleID else { return false }
    return config.excludedBundleIDs.contains(bundleID)
}
```

### Step 3.3: `discoverExistingWindows` に除外ガードを追加する

- [ ] `discoverExistingWindows()` 内の `for window in windows {` ループを修正する:

変更前:
```swift
for window in windows {
    windowRegistry[window.id] = window
    assignWindowToScreen(window)
}
```

変更後:
```swift
for window in windows {
    guard !isExcluded(window) else {
        niriLog("[exclusion] skip '\(window.ownerBundleID ?? "?")'  windowID=\(window.id)")
        continue
    }
    windowRegistry[window.id] = window
    assignWindowToScreen(window)
}
```

### Step 3.4: `handleWindowCreated` に除外ガードを追加する

- [ ] `handleWindowCreated(_:)` の先頭の guard 直後に追加する:

変更前:
```swift
private func handleWindowCreated(_ window: WindowInfo) {
    guard windowRegistry[window.id] == nil else { return }

    // windowRegistry に未登録のウィンドウのみ追加
    windowRegistry[window.id] = window
```

変更後:
```swift
private func handleWindowCreated(_ window: WindowInfo) {
    guard windowRegistry[window.id] == nil else { return }
    guard !isExcluded(window) else {
        niriLog("[exclusion] skip '\(window.ownerBundleID ?? "?")'  windowID=\(window.id)")
        return
    }

    // windowRegistry に未登録のウィンドウのみ追加
    windowRegistry[window.id] = window
```

### Step 3.5: メニューバー用の公開 API を追加する

- [ ] `WindowManager` の `// MARK: - Focus Highlight Toggles` の直前に追加する:

```swift
// MARK: - App Exclusion API（メニューバー用）

/// 現在フォーカス中のアプリの bundleID（取得できない場合は nil）
var focusedAppBundleID: String? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    return app.bundleIdentifier
}

/// 除外アプリ一覧（bundleID と表示名のペア）
var excludedApps: [(bundleID: String, name: String)] {
    config.excludedBundleIDs.sorted().map { bundleID in
        let name = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first?.localizedName
            ?? bundleID
        return (bundleID: bundleID, name: name)
    }
}

/// アプリを除外リストに追加し、既存ウィンドウをレイアウトから即座に削除する
func excludeApp(bundleID: String) {
    guard !config.excludedBundleIDs.contains(bundleID) else { return }
    config.excludedBundleIDs.insert(bundleID)
    ExclusionStore.save(config.excludedBundleIDs)
    niriLog("[exclusion] excluded '\(bundleID)'")

    // 既にタイリングに入っているウィンドウを即座に除去
    let toRemove = windowRegistry.values
        .filter { $0.ownerBundleID == bundleID }
        .map { $0.id }
    for id in toRemove {
        handleWindowDestroyed(id)
    }
}

/// アプリを除外リストから削除する（ウィンドウ復帰は次回起動時）
func includeApp(bundleID: String) {
    config.excludedBundleIDs.remove(bundleID)
    ExclusionStore.save(config.excludedBundleIDs)
    niriLog("[exclusion] included '\(bundleID)'")
}
```

### Step 3.6: `syncWindowsForCurrentSpace` にも除外ガードを追加する

スペース切り替え時にもウィンドウが追加される箇所が2つあるため、両方に除外チェックを追加する。

- [ ] `syncWindowsForCurrentSpace()` 内の「保存済みカラムに含まれていない新規ウィンドウを末尾に追加」箇所を修正する:

変更前:
```swift
for window in freshWindows where newWindowIDs.contains(window.id) {
    windowRegistry[window.id] = window
    axBridge.registerElement(window.axElement, for: window.id)
    let col = Column(windows: [window.id], width: window.frame.width)
    restoredColumns.append(col)
    niriLog("[space-sync] added new window to layout: \(window.id)")
}
```

変更後:
```swift
for window in freshWindows where newWindowIDs.contains(window.id) {
    guard !isExcluded(window) else { continue }
    windowRegistry[window.id] = window
    axBridge.registerElement(window.axElement, for: window.id)
    let col = Column(windows: [window.id], width: window.frame.width)
    restoredColumns.append(col)
    niriLog("[space-sync] added new window to layout: \(window.id)")
}
```

- [ ] 同関数内の「初回訪問: レイアウトをクリアして再構築」の `assignWindowToScreen` 箇所を修正する:

変更前:
```swift
for window in freshWindows where currentSpaceWindowIDs.contains(window.id) {
    windowRegistry[window.id] = window
    axBridge.registerElement(window.axElement, for: window.id)
    assignWindowToScreen(window)
}
```

変更後:
```swift
for window in freshWindows where currentSpaceWindowIDs.contains(window.id) {
    guard !isExcluded(window) else { continue }
    windowRegistry[window.id] = window
    axBridge.registerElement(window.axElement, for: window.id)
    assignWindowToScreen(window)
}
```

### Step 3.7: ビルドが通ることを確認する

- [ ] ビルドする:

```bash
swift build 2>&1 | tail -10
```

Expected: `Build complete!`

### Step 3.8: コミット

- [ ] コミットする:

```bash
git add Sources/NiriMac/Orchestrator/WindowManager.swift
git commit -m "feat: WindowManager に除外ロジックと公開 API を追加"
```

---

## Task 4: ステータスバーに「Excluded Apps」サブメニューを追加する

**Files:**
- Modify: `Sources/NiriMac/App/NiriMacApp.swift`

### Step 4.1: `NiriMacApp` にプロパティを追加する

- [ ] `NiriMacApp` クラスの既存プロパティ群（`focusDimMenuItem` の直後）に追加する:

```swift
private var excludedAppsMenuItem: NSMenuItem?
```

### Step 4.2: `setupStatusBar()` にサブメニューを追加する

- [ ] `setupStatusBar()` 内で `let borderItem = ...` の直前に以下を追加する:

```swift
let excludedAppsItem = NSMenuItem(title: "Excluded Apps", action: nil, keyEquivalent: "")
excludedAppsItem.submenu = NSMenu()
self.excludedAppsMenuItem = excludedAppsItem
menu.addItem(excludedAppsItem)
menu.addItem(NSMenuItem.separator())
```

完成後のメニュー順序:
1. `niri-mac`（タイトル）
2. セパレータ
3. `Pin Column`
4. セパレータ
5. `Excluded Apps ▶`（サブメニュー）
6. セパレータ
7. `Focus Border`
8. `Focus Dim`
9. セパレータ
10. `Quit`

### Step 4.3: `menuWillOpen` でサブメニューを動的生成する

- [ ] `menuWillOpen(_:)` の末尾に追加する:

```swift
// Excluded Apps サブメニューを動的生成
if let submenu = excludedAppsMenuItem?.submenu {
    submenu.removeAllItems()

    // 「現在のアプリを除外」
    let excludeCurrentItem = NSMenuItem(
        title: "Exclude Current App",
        action: #selector(excludeCurrentApp),
        keyEquivalent: ""
    )
    excludeCurrentItem.target = self
    if windowManager?.focusedAppBundleID == nil {
        excludeCurrentItem.isEnabled = false
    }
    submenu.addItem(excludeCurrentItem)

    // 除外済みアプリがあればセパレータ＋リスト
    if let apps = windowManager?.excludedApps, !apps.isEmpty {
        submenu.addItem(NSMenuItem.separator())
        for app in apps {
            let item = NSMenuItem(
                title: app.name,
                action: #selector(includeApp(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = app.bundleID
            item.state = .on
            submenu.addItem(item)
        }
    }
}
```

### Step 4.4: アクションメソッドを追加する

- [ ] `NiriMacApp` に以下のメソッドを追加する（`@objc private func quit()` の直前）:

```swift
@objc private func excludeCurrentApp() {
    guard let bundleID = windowManager?.focusedAppBundleID else { return }
    windowManager?.excludeApp(bundleID: bundleID)
}

@objc private func includeApp(_ sender: NSMenuItem) {
    guard let bundleID = sender.representedObject as? String else { return }
    windowManager?.includeApp(bundleID: bundleID)
}
```

### Step 4.5: ビルドが通ることを確認する

- [ ] ビルドする:

```bash
swift build 2>&1 | tail -10
```

Expected: `Build complete!`

### Step 4.6: 全テストが通ることを確認する

- [ ] テストを実行する:

```bash
swift test 2>&1 | tail -20
```

Expected: 全テスト PASS

### Step 4.7: コミット

- [ ] コミットする:

```bash
git add Sources/NiriMac/App/NiriMacApp.swift
git commit -m "feat: ステータスバーに Excluded Apps サブメニューを追加"
```

---

## Task 5: 動作確認

### Step 5.1: アプリをビルドして起動する

- [ ] アプリバンドルを作成して起動する:

```bash
bash make-app.sh && open NiriMac.app
```

### Step 5.2: 除外機能を手動テストする

- [ ] Docker Desktop など除外したいアプリをフォーカスする
- [ ] ステータスバー「N」→「Excluded Apps」→「Exclude Current App」をクリックする
- [ ] 対象アプリのウィンドウがタイリングから外れることを確認する
- [ ] `~/.config/niri-mac/excluded-apps.json` が生成されていることを確認する:

```bash
cat ~/.config/niri-mac/excluded-apps.json
```

Expected:
```json
{"excludedBundleIDs":["com.docker.docker"]}
```

- [ ] ログで除外が記録されていることを確認する:

```bash
grep exclusion /tmp/niri-mac.log
```

Expected: `[exclusion] excluded 'com.docker.docker'` など

### Step 5.3: 再起動後も設定が維持されることを確認する

- [ ] アプリを終了して再起動する:

```bash
pkill -f NiriMac; sleep 1; open NiriMac.app
```

- [ ] 除外アプリがタイリングされていないことを確認する
- [ ] ステータスバー「Excluded Apps」サブメニューに除外済みアプリが表示されることを確認する

### Step 5.4: 除外解除をテストする

- [ ] サブメニューの除外済みアプリ名をクリックして解除する
- [ ] `~/.config/niri-mac/excluded-apps.json` から該当エントリが消えることを確認する:

```bash
cat ~/.config/niri-mac/excluded-apps.json
```

Expected: `{"excludedBundleIDs":[]}`

---

## 完了チェックリスト

- [ ] Task 1: ExclusionStore 実装・テスト通過・コミット
- [ ] Task 2: LayoutConfig フィールド追加・コミット
- [ ] Task 3: WindowManager 除外ロジック・API 追加・コミット
- [ ] Task 4: ステータスバーサブメニュー追加・コミット
- [ ] Task 5: 動作確認完了
