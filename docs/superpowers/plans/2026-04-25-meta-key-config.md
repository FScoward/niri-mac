# Meta Key & Scroll Modifier Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** キーボードショートカットとスクロールのベース修飾キーをステータスバーメニューから自由に変更し、`~/.config/niri-mac/config.json` に永続化する。

**Architecture:** `LayoutConfig` に3つの `NSEvent.ModifierFlags` フィールドを追加。`ConfigStore`（新規）で JSON 永続化。`KeyboardShortcutManager` は `init` 時に `metaModifiers` を受け取り動的バインディング生成。`MouseEventManager` の suppress ロジックと `WindowManager` のスクロールハンドラを config から読む。ステータスバーに3つの修飾キーサブメニューと「Restart to Apply...」を追加。

**Tech Stack:** Swift 5.9, AppKit, swift-testing (`@Suite`, `@Test`, `#expect`), `swift test --filter`

---

## File Map

| ファイル | 変更種別 |
|----------|----------|
| `Sources/NiriMac/Engine/LayoutConfig.swift` | 変更 — 3フィールド追加 |
| `Sources/NiriMac/Bridge/ConfigStore.swift` | **新規** — JSON load/save |
| `Sources/NiriMac/Bridge/KeyboardShortcutManager.swift` | 変更 — init + 動的バインディング |
| `Sources/NiriMac/Bridge/MouseEventManager.swift` | 変更 — suppress 動的化 |
| `Sources/NiriMac/Orchestrator/WindowManager.swift` | 変更 — scroll handler + init wiring |
| `Sources/NiriMac/App/NiriMacApp.swift` | 変更 — ConfigStore 読み込み + メニュー |
| `Tests/NiriMacTests/ConfigStoreTests.swift` | **新規** — load/save/roundtrip テスト |
| `Tests/NiriMacTests/KeyboardShortcutManagerTests.swift` | **新規** — 動的バインディングテスト |

---

### Task 1: LayoutConfig — modifier フィールド追加

**Files:**
- Modify: `Sources/NiriMac/Engine/LayoutConfig.swift`

- [ ] **Step 1: autoFitCenterWidthFraction の後に MARK と3フィールドを追加**

`Sources/NiriMac/Engine/LayoutConfig.swift` の末尾（`}` の直前）に追加:

```swift
    // MARK: - Modifier Keys

    /// キーボードショートカットのベース修飾キー
    var metaModifiers: NSEvent.ModifierFlags = [.control, .option]

    /// レイアウトスクロールのトリガー修飾キー
    var scrollLayoutModifiers: NSEvent.ModifierFlags = [.option]

    /// カラムフォーカス移動スクロールのトリガー修飾キー
    var scrollFocusModifiers: NSEvent.ModifierFlags = [.control, .option]
```

- [ ] **Step 2: ビルド確認**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: コミット**

```bash
git add Sources/NiriMac/Engine/LayoutConfig.swift
git commit -m "feat: add metaModifiers/scrollLayoutModifiers/scrollFocusModifiers to LayoutConfig"
```

---

### Task 2: ConfigStore — JSON 永続化 (TDD)

**Files:**
- Create: `Sources/NiriMac/Bridge/ConfigStore.swift`
- Create: `Tests/NiriMacTests/ConfigStoreTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/NiriMacTests/ConfigStoreTests.swift` を新規作成:

```swift
import Testing
import Foundation
import AppKit
@testable import NiriMac

@Suite("ConfigStore Tests")
struct ConfigStoreTests {

    private func makeTempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("config.json")
    }

    @Test func loadReturnsDefaultsWhenFileNotFound() {
        let url = makeTempURL()
        let result = ConfigStore.load(from: url)
        #expect(result.meta == [.control, .option])
        #expect(result.scrollLayout == [.option])
        #expect(result.scrollFocus == [.control, .option])
    }

    @Test func saveAndLoad() {
        let url = makeTempURL()
        ConfigStore.save(
            meta: [.command, .option],
            scrollLayout: [.control],
            scrollFocus: [.command, .shift],
            to: url
        )
        let result = ConfigStore.load(from: url)
        #expect(result.meta == [.command, .option])
        #expect(result.scrollLayout == [.control])
        #expect(result.scrollFocus == [.command, .shift])
    }

    @Test func loadReturnsDefaultsWhenFileCorrupted() throws {
        let url = makeTempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        let result = ConfigStore.load(from: url)
        #expect(result.meta == [.control, .option])
    }

    @Test func stringsFromFlagsRoundTrip() {
        let flags: NSEvent.ModifierFlags = [.control, .option, .command]
        let strings = ConfigStore.strings(from: flags)
        let restored = ConfigStore.flags(from: strings)
        #expect(restored == flags)
    }
}
```

- [ ] **Step 2: テストがコンパイルエラーで失敗することを確認**

```bash
swift test --filter ConfigStoreTests 2>&1 | tail -10
```

Expected: `error: cannot find type 'ConfigStore'`

- [ ] **Step 3: ConfigStore.swift を作成**

`Sources/NiriMac/Bridge/ConfigStore.swift` を新規作成:

```swift
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
```

- [ ] **Step 4: テストがパスすることを確認**

```bash
swift test --filter ConfigStoreTests 2>&1 | tail -10
```

Expected: `Test run with 4 tests passed.`

- [ ] **Step 5: コミット**

```bash
git add Sources/NiriMac/Bridge/ConfigStore.swift Tests/NiriMacTests/ConfigStoreTests.swift
git commit -m "feat: add ConfigStore for modifier key JSON persistence"
```

---

### Task 3: KeyboardShortcutManager — 動的バインディング生成 (TDD)

**Files:**
- Modify: `Sources/NiriMac/Bridge/KeyboardShortcutManager.swift`
- Create: `Tests/NiriMacTests/KeyboardShortcutManagerTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/NiriMacTests/KeyboardShortcutManagerTests.swift` を新規作成:

```swift
import Testing
import AppKit
@testable import NiriMac

@Suite("KeyboardShortcutManager Binding Tests")
struct KeyboardShortcutManagerTests {

    @Test func defaultMetaGenerates21Bindings() {
        let bindings = KeyboardShortcutManager.buildBindings(meta: [.control, .option])
        #expect(bindings.count == 21)
    }

    @Test func focusLeftUsesMetaModifiers() {
        let bindings = KeyboardShortcutManager.buildBindings(meta: [.command, .option])
        let b = bindings.first { $0.action == .focusLeft }
        #expect(b?.modifiers == [.command, .option])
    }

    @Test func moveColumnLeftUsesMetaPlusShift() {
        let bindings = KeyboardShortcutManager.buildBindings(meta: [.command, .option])
        let b = bindings.first { $0.action == .moveColumnLeft }
        #expect(b?.modifiers == [.command, .option, .shift])
    }

    @Test func switchWorkspaceUpUsesMetaPlusCommand() {
        let bindings = KeyboardShortcutManager.buildBindings(meta: [.control, .option])
        let b = bindings.first { $0.action == .switchWorkspaceUp }
        #expect(b?.modifiers == [.control, .option, .command])
    }

    @Test func moveWindowToWorkspaceUsesMetaPlusCommandShift() {
        let bindings = KeyboardShortcutManager.buildBindings(meta: [.control, .option])
        let b = bindings.first { $0.action == .moveWindowToWorkspaceUp }
        #expect(b?.modifiers == [.control, .option, .command, .shift])
    }
}
```

- [ ] **Step 2: テストがコンパイルエラーで失敗することを確認**

```bash
swift test --filter KeyboardShortcutManagerTests 2>&1 | tail -10
```

Expected: `error: type 'KeyboardShortcutManager' has no member 'buildBindings'`

- [ ] **Step 3: KeyboardShortcutManager を変更**

`Sources/NiriMac/Bridge/KeyboardShortcutManager.swift` の以下の箇所を変更する。

**3a. `private let bindings: [Binding] = [...]` ブロック全体を削除し、以下で置き換える:**

```swift
    private let bindings: [Binding]

    init(metaModifiers: NSEvent.ModifierFlags = [.control, .option]) {
        self.bindings = KeyboardShortcutManager.buildBindings(meta: metaModifiers)
    }

    static func buildBindings(meta: NSEvent.ModifierFlags) -> [Binding] {
        let metaShift    = meta.union([.shift])
        let metaCmd      = meta.union([.command])
        let metaCmdShift = meta.union([.command, .shift])
        return [
            // カラム間フォーカス
            Binding(modifiers: meta,         keyCode: 123, action: .focusLeft),
            Binding(modifiers: meta,         keyCode: 124, action: .focusRight),
            // カラム内ウィンドウ
            Binding(modifiers: meta,         keyCode: 126, action: .focusUp),
            Binding(modifiers: meta,         keyCode: 125, action: .focusDown),
            // カラム並べ替え
            Binding(modifiers: metaShift,    keyCode: 123, action: .moveColumnLeft),
            Binding(modifiers: metaShift,    keyCode: 124, action: .moveColumnRight),
            // ワークスペース切り替え
            Binding(modifiers: metaCmd,      keyCode: 126, action: .switchWorkspaceUp),
            Binding(modifiers: metaCmd,      keyCode: 125, action: .switchWorkspaceDown),
            // ウィンドウをワークスペース移動
            Binding(modifiers: metaCmdShift, keyCode: 126, action: .moveWindowToWorkspaceUp),
            Binding(modifiers: metaCmdShift, keyCode: 125, action: .moveWindowToWorkspaceDown),
            // カラム操作
            Binding(modifiers: meta,         keyCode: 36,  action: .consumeIntoColumnLeft),
            Binding(modifiers: metaShift,    keyCode: 36,  action: .expelFromColumn),
            // カラム幅・pin
            Binding(modifiers: meta,         keyCode: 15,  action: .cycleColumnWidth),
            Binding(modifiers: meta,         keyCode: 35,  action: .togglePin),
            // カラム内ウィンドウ並び替え
            Binding(modifiers: metaShift,    keyCode: 126, action: .moveWindowUpInColumn),
            Binding(modifiers: metaShift,    keyCode: 125, action: .moveWindowDownInColumn),
            // ウィンドウ高さリサイズ
            Binding(modifiers: meta,         keyCode: 27,  action: .shrinkWindowHeight),
            Binding(modifiers: meta,         keyCode: 24,  action: .growWindowHeight),
            // Auto-Fit
            Binding(modifiers: meta,         keyCode: 0,   action: .toggleAutoFit),
            // 終了
            Binding(modifiers: meta,         keyCode: 12,  action: .quit),
            // Re-layout
            Binding(modifiers: metaShift,    keyCode: 3,   action: .reLayout),
        ]
    }
```

- [ ] **Step 4: テストがパスすることを確認**

```bash
swift test --filter KeyboardShortcutManagerTests 2>&1 | tail -10
```

Expected: `Test run with 5 tests passed.`

- [ ] **Step 5: 全テストが通ることを確認**

```bash
swift test 2>&1 | tail -5
```

Expected: 全テスト pass

- [ ] **Step 6: コミット**

```bash
git add Sources/NiriMac/Bridge/KeyboardShortcutManager.swift Tests/NiriMacTests/KeyboardShortcutManagerTests.swift
git commit -m "feat: generate keyboard bindings dynamically from metaModifiers"
```

---

### Task 4: MouseEventManager — suppress ロジック動的化

**Files:**
- Modify: `Sources/NiriMac/Bridge/MouseEventManager.swift`

- [ ] **Step 1: scrollLayoutModifiers プロパティを追加**

`Sources/NiriMac/Bridge/MouseEventManager.swift` の `var onAppActivated` 宣言の直後に追加:

```swift
    /// レイアウトスクロールをトリガーする修飾キー（一致したスクロールはアプリに転送しない）
    var scrollLayoutModifiers: NSEvent.ModifierFlags = [.option]
```

- [ ] **Step 2: suppress ロジックを置き換える**

`handleCGEvent` 内の suppress 行（現在の以下のブロック）を:

```swift
            // Option のみのスクロールは WM が処理するのでアプリへ転送しない
            let suppress = cgFlags.contains(.maskAlternate)
                        && !cgFlags.contains(.maskControl)
                        && !cgFlags.contains(.maskCommand)
```

以下に置き換える:

```swift
            // scrollLayoutModifiers と一致するスクロールは WM が処理するのでアプリへ転送しない
            let suppress = cgFlagsMatchModifiers(cgFlags, required: scrollLayoutModifiers)
```

- [ ] **Step 3: ヘルパーメソッドを追加**

`MouseEventManager` クラスの末尾（`}` の直前）に追加:

```swift
    private func cgFlagsMatchModifiers(_ cgFlags: CGEventFlags, required: NSEvent.ModifierFlags) -> Bool {
        var flags: NSEvent.ModifierFlags = []
        if cgFlags.contains(.maskCommand)   { flags.insert(.command) }
        if cgFlags.contains(.maskAlternate) { flags.insert(.option) }
        if cgFlags.contains(.maskShift)     { flags.insert(.shift) }
        if cgFlags.contains(.maskControl)   { flags.insert(.control) }
        let filtered = flags.intersection([.command, .control, .option, .shift])
        let requiredFiltered = required.intersection([.command, .control, .option, .shift])
        return filtered == requiredFiltered
    }
```

- [ ] **Step 4: ビルドと全テスト確認**

```bash
swift build 2>&1 | tail -5 && swift test 2>&1 | tail -5
```

Expected: `Build complete!` → 全テスト pass

- [ ] **Step 5: コミット**

```bash
git add Sources/NiriMac/Bridge/MouseEventManager.swift
git commit -m "feat: make MouseEventManager suppress logic dynamic via scrollLayoutModifiers"
```

---

### Task 5: WindowManager — scroll handler + init wiring

**Files:**
- Modify: `Sources/NiriMac/Orchestrator/WindowManager.swift`

- [ ] **Step 1: init の keyboard/mouse 初期化を更新（101〜106行付近）**

現在:
```swift
    init(config: LayoutConfig = LayoutConfig()) {
        self.axBridge = AccessibilityBridge()
        self.observer = AXObserverBridge()
        self.keyboard = KeyboardShortcutManager()
        self.mouse = MouseEventManager()
        self.config = config
    }
```

以下に変更:
```swift
    init(config: LayoutConfig = LayoutConfig()) {
        self.axBridge = AccessibilityBridge()
        self.observer = AXObserverBridge()
        self.keyboard = KeyboardShortcutManager(metaModifiers: config.metaModifiers)
        self.mouse = MouseEventManager()
        self.config = config
        self.mouse.scrollLayoutModifiers = config.scrollLayoutModifiers
    }
```

- [ ] **Step 2: handleScroll の modifier フィルタを更新（1315行付近）**

現在:
```swift
        let filtered = flags.intersection([.control, .option])
```

以下に変更:
```swift
        let filtered = flags.intersection([.command, .control, .option, .shift])
```

- [ ] **Step 3: handleScroll の修飾キー比較を置き換える（1318行・1333行付近）**

現在:
```swift
        // Ctrl+Opt+スクロール → カラムフォーカス移動
        if filtered == [.control, .option] {
```

以下に変更:
```swift
        // scrollFocusModifiers+スクロール → カラムフォーカス移動
        if filtered == config.scrollFocusModifiers {
```

現在:
```swift
        // Option + スクロール → レイアウトスクロール（縦横どちらも使える）
        if filtered == [.option] {
```

以下に変更:
```swift
        // scrollLayoutModifiers + スクロール → レイアウトスクロール（縦横どちらも使える）
        if filtered == config.scrollLayoutModifiers {
```

- [ ] **Step 4: ビルドと全テスト確認**

```bash
swift build 2>&1 | tail -5 && swift test 2>&1 | tail -5
```

Expected: `Build complete!` → 全テスト pass

- [ ] **Step 5: コミット**

```bash
git add Sources/NiriMac/Orchestrator/WindowManager.swift
git commit -m "feat: wire metaModifiers/scrollModifiers from config into managers"
```

---

### Task 6: NiriMacApp — ConfigStore 読み込み + 修飾キーメニュー

**Files:**
- Modify: `Sources/NiriMac/App/NiriMacApp.swift`

- [ ] **Step 1: プロパティを追加**

`NiriMacApp` クラスの既存プロパティ（`autoFitMenuItem` 等）の直後に追加:

```swift
    private var pendingMeta: NSEvent.ModifierFlags = [.control, .option]
    private var pendingScrollLayout: NSEvent.ModifierFlags = [.option]
    private var pendingScrollFocus: NSEvent.ModifierFlags = [.control, .option]
    private var modifierChangePending = false
    private var restartMenuItem: NSMenuItem?
```

- [ ] **Step 2: applicationDidFinishLaunching を更新**

現在:
```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        printDiagnostics()
        setupStatusBar()

        let config = LayoutConfig()
        windowManager = WindowManager(config: config)
        windowManager?.start()
    }
```

以下に変更:
```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        printDiagnostics()

        let stored = ConfigStore.load()
        pendingMeta = stored.meta
        pendingScrollLayout = stored.scrollLayout
        pendingScrollFocus = stored.scrollFocus

        setupStatusBar()

        var config = LayoutConfig()
        config.metaModifiers = stored.meta
        config.scrollLayoutModifiers = stored.scrollLayout
        config.scrollFocusModifiers = stored.scrollFocus
        windowManager = WindowManager(config: config)
        windowManager?.start()
    }
```

- [ ] **Step 3: makeModifierSubmenu ヘルパーを追加**

`NiriMacApp` に以下のメソッドを追加:

```swift
    private func makeModifierSubmenu(title: String, current: NSEvent.ModifierFlags, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let pairs: [(String, NSEvent.ModifierFlags)] = [
            ("Control (⌃)", .control),
            ("Option (⌥)",  .option),
            ("Command (⌘)", .command),
            ("Shift (⇧)",   .shift),
        ]
        for (i, (label, flag)) in pairs.enumerated() {
            let mi = NSMenuItem(title: label, action: #selector(toggleModifier(_:)), keyEquivalent: "")
            mi.target = self
            mi.state = current.contains(flag) ? .on : .off
            mi.tag = tag * 10 + i
            submenu.addItem(mi)
        }
        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(NSMenuItem(title: "(再起動後に反映)", action: nil, keyEquivalent: ""))
        item.submenu = submenu
        return item
    }
```

- [ ] **Step 4: toggleModifier アクションを追加**

```swift
    private static let modifierFlagList: [NSEvent.ModifierFlags] = [.control, .option, .command, .shift]

    @objc private func toggleModifier(_ sender: NSMenuItem) {
        let group = sender.tag / 10
        let flagIndex = sender.tag % 10
        guard flagIndex < NiriMacApp.modifierFlagList.count else { return }
        let flag = NiriMacApp.modifierFlagList[flagIndex]

        switch group {
        case 1:
            if pendingMeta.contains(flag) { pendingMeta.remove(flag) } else { pendingMeta.insert(flag) }
            if pendingMeta.isEmpty { pendingMeta.insert(flag); return }
            sender.state = pendingMeta.contains(flag) ? .on : .off
            if pendingMeta.contains(.command) {
                let alert = NSAlert()
                alert.messageText = "⚠️ Command をメタキーに含めると\nワークスペース操作が機能しなくなります"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        case 2:
            if pendingScrollLayout.contains(flag) { pendingScrollLayout.remove(flag) } else { pendingScrollLayout.insert(flag) }
            if pendingScrollLayout.isEmpty { pendingScrollLayout.insert(flag); return }
            sender.state = pendingScrollLayout.contains(flag) ? .on : .off
        case 3:
            if pendingScrollFocus.contains(flag) { pendingScrollFocus.remove(flag) } else { pendingScrollFocus.insert(flag) }
            if pendingScrollFocus.isEmpty { pendingScrollFocus.insert(flag); return }
            sender.state = pendingScrollFocus.contains(flag) ? .on : .off
        default:
            return
        }

        ConfigStore.save(meta: pendingMeta, scrollLayout: pendingScrollLayout, scrollFocus: pendingScrollFocus)
        modifierChangePending = true
        restartMenuItem?.isEnabled = true
    }
```

- [ ] **Step 5: restartToApply アクションを追加**

```swift
    @objc private func restartToApply() {
        let alert = NSAlert()
        alert.messageText = "再起動して設定変更を適用しますか？"
        alert.addButton(withTitle: "再起動")
        alert.addButton(withTitle: "キャンセル")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 0.5; open '\(bundlePath)'"]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }
```

- [ ] **Step 6: setupStatusBar にサブメニューと Restart を追加**

`setupStatusBar()` 内、`reLayoutItem` の `menu.addItem(reLayoutItem)` の直後・`menu.addItem(NSMenuItem.separator())` の前に挿入:

```swift
        menu.addItem(reLayoutItem)  // ← 既存行（この直後に追記）

        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeModifierSubmenu(title: "Keyboard Meta", current: pendingMeta, tag: 1))
        menu.addItem(makeModifierSubmenu(title: "Scroll: Layout", current: pendingScrollLayout, tag: 2))
        menu.addItem(makeModifierSubmenu(title: "Scroll: Focus", current: pendingScrollFocus, tag: 3))

        let restartItem = NSMenuItem(title: "Restart to Apply...", action: #selector(restartToApply), keyEquivalent: "")
        restartItem.target = self
        restartItem.isEnabled = false
        self.restartMenuItem = restartItem
        menu.addItem(restartItem)
        // ↓ 既存の separator + Quit がこの後に続く
```

- [ ] **Step 7: ビルドと全テスト確認**

```bash
swift build 2>&1 | tail -10
swift test 2>&1 | tail -5
```

Expected: `Build complete!` → 全テスト pass

- [ ] **Step 8: コミット**

```bash
git add Sources/NiriMac/App/NiriMacApp.swift
git commit -m "feat: add modifier key config menu and restart-to-apply to status bar"
```

---

### Task 7: 手動動作確認

**Files:** なし（動作確認のみ）

- [ ] **Step 1: アプリバンドルをビルド**

```bash
bash make-app.sh
open NiriMac.app
```

- [ ] **Step 2: 初期状態の確認**

ステータスバー → 以下を確認:
- 「Keyboard Meta」サブメニュー → Control・Option がチェック済み
- 「Scroll: Layout」サブメニュー → Option のみチェック済み
- 「Scroll: Focus」サブメニュー → Control・Option がチェック済み
- 「Restart to Apply...」がグレーアウト

- [ ] **Step 3: メタキー変更とリスタートフロー**

1. 「Keyboard Meta」→ Control のチェックを外す
2. 「Restart to Apply...」が有効になることを確認
3. クリック → 確認ダイアログ → 「再起動」
4. 再起動後、ステータスバー → 「Keyboard Meta」→ Control がチェックなしのまま（永続化確認）

- [ ] **Step 4: 新しいメタキーで動作確認**

（Meta = Option のみに設定した場合）
- `Option + ←` → カラムフォーカス左移動
- `Option + →` → カラムフォーカス右移動
- `Option + Shift + ←` → カラム左並べ替え

- [ ] **Step 5: 設定ファイル確認**

```bash
cat ~/.config/niri-mac/config.json
```

Expected（例）:
```json
{
  "metaModifiers": ["option"],
  "scrollLayoutModifiers": ["option"],
  "scrollFocusModifiers": ["option"]
}
```
