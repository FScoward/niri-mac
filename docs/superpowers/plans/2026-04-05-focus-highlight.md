# Focus Highlight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** フォーカス中ウィンドウに枠線、非フォーカスウィンドウにディムオーバーレイを表示し、ステータスバーメニューから個別にON/OFFできるようにする。

**Architecture:** `FocusOverlayManager`（新規 Bridge クラス）が NSPanel オーバーレイのライフサイクルを管理し、`WindowManager.applyLayout()` 末尾で `update(focusedID:allFrames:config:)` を呼ぶ。NSPanel は `ignoresMouseEvents = true` / `level: .floating` で既存ウィンドウの上に重なる。Quartz → Cocoa 座標変換が必要。

**Tech Stack:** Swift, AppKit (NSPanel, NSView, CALayer), CoreGraphics, Swift Testing

---

## ファイルマップ

| ファイル | 変更種別 | 責務 |
|---|---|---|
| `Sources/NiriMac/Engine/LayoutConfig.swift` | 修正 | フォーカス設定値 5 プロパティ追加 |
| `Sources/NiriMac/Bridge/FocusOverlayManager.swift` | 新規 | NSPanel 生成・位置更新・削除 |
| `Sources/NiriMac/Orchestrator/WindowManager.swift` | 修正 | config を var 化、focusOverlayManager 統合、toggle メソッド追加 |
| `Sources/NiriMac/App/NiriMacApp.swift` | 修正 | ステータスバーメニューにトグル 2 項目追加 |
| `Tests/NiriMacTests/FocusOverlayManagerTests.swift` | 新規 | FocusOverlayManager のロジックテスト |

---

## Task 1: LayoutConfig にフォーカス設定を追加

**Files:**
- Modify: `Sources/NiriMac/Engine/LayoutConfig.swift`

- [ ] **Step 1: 設定プロパティを追加する**

`Sources/NiriMac/Engine/LayoutConfig.swift` の末尾の `}` の直前に以下を追加する:

```swift
    // MARK: - Focus Highlight

    /// フォーカス枠線の表示有無
    var focusBorderEnabled: Bool = false

    /// 枠線の色（デフォルト: システムブルー）
    var focusBorderColor: CGColor = NSColor.systemBlue.cgColor

    /// 枠線の幅（px）
    var focusBorderWidth: CGFloat = 4.0

    /// 非フォーカスウィンドウのディム表示有無
    var focusDimEnabled: Bool = false

    /// ディムの不透明度（0.0〜1.0）
    var focusDimOpacity: CGFloat = 0.4
```

ファイル先頭に `import AppKit` が必要（`NSColor` 参照のため）。現在は `import CoreGraphics` のみなので追加する:

```swift
import AppKit
import CoreGraphics
```

- [ ] **Step 2: ビルドして確認する**

```bash
swift build 2>&1 | head -20
```

Expected: `Build complete!`（エラーなし）

- [ ] **Step 3: コミット**

```bash
git add Sources/NiriMac/Engine/LayoutConfig.swift
git commit -m "feat: LayoutConfig にフォーカスハイライト設定を追加"
```

---

## Task 2: FocusOverlayManager を実装する

**Files:**
- Create: `Sources/NiriMac/Bridge/FocusOverlayManager.swift`
- Create: `Tests/NiriMacTests/FocusOverlayManagerTests.swift`

- [ ] **Step 1: テストファイルを作成する**

`Tests/NiriMacTests/FocusOverlayManagerTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import NiriMac

@Suite("FocusOverlayManager Tests")
struct FocusOverlayManagerTests {

    @Test func quartzToCocoaConversion() {
        // スクリーン高さ 900 と仮定
        let screenHeight: CGFloat = 900
        let quartzFrame = CGRect(x: 100, y: 50, width: 400, height: 300)
        // Cocoa Y = screenHeight - quartzY - height = 900 - 50 - 300 = 550
        let cocoaFrame = FocusOverlayManager.quartzToCocoa(quartzFrame, screenHeight: screenHeight)
        #expect(abs(cocoaFrame.origin.x - 100) < 0.001)
        #expect(abs(cocoaFrame.origin.y - 550) < 0.001)
        #expect(abs(cocoaFrame.width - 400) < 0.001)
        #expect(abs(cocoaFrame.height - 300) < 0.001)
    }

    @Test func expandedBorderFrame() {
        let base = CGRect(x: 100, y: 100, width: 400, height: 300)
        let expanded = base.insetBy(dx: -4, dy: -4)
        #expect(abs(expanded.origin.x - 96) < 0.001)
        #expect(abs(expanded.origin.y - 96) < 0.001)
        #expect(abs(expanded.width - 408) < 0.001)
        #expect(abs(expanded.height - 308) < 0.001)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
swift test --filter FocusOverlayManagerTests 2>&1 | tail -10
```

Expected: `error: no such module 'NiriMac'` または `quartzToCocoa` が見つからないエラー

- [ ] **Step 3: FocusOverlayManager を実装する**

`Sources/NiriMac/Bridge/FocusOverlayManager.swift` を新規作成:

```swift
import AppKit
import CoreGraphics

/// フォーカスウィンドウの枠線・ディム効果を NSPanel オーバーレイで表示する。
///
/// - borderPanel: フォーカス中ウィンドウ周囲の枠線パネル（1枚）
/// - dimPanels: 非フォーカスウィンドウごとの半透明オーバーレイ（WindowID → NSPanel）
///
/// WindowManager.applyLayout() の末尾から update(focusedID:allFrames:config:) を呼ぶこと。
/// parkedWindowIDs（画面外退避中）のウィンドウはオーバーレイ対象外とする。
final class FocusOverlayManager {

    private var borderPanel: NSPanel?
    private var dimPanels: [WindowID: NSPanel] = [:]

    // MARK: - Public API

    /// レイアウト適用後にオーバーレイを更新する。
    ///
    /// - Parameters:
    ///   - focusedID: 現在フォーカス中のウィンドウID（nil の場合は全オーバーレイを非表示）
    ///   - allFrames: (WindowID, Quartzフレーム) の配列。parkedWindowIDs は含まない。
    ///   - config: LayoutConfig（focusBorderEnabled 等を参照）
    func update(
        focusedID: WindowID?,
        allFrames: [(WindowID, CGRect)],
        config: LayoutConfig
    ) {
        updateBorder(focusedID: focusedID, allFrames: allFrames, config: config)
        updateDim(focusedID: focusedID, allFrames: allFrames, config: config)
    }

    /// 全オーバーレイを非表示にして解放する。アプリ終了時・stop() から呼ぶ。
    func removeAll() {
        borderPanel?.orderOut(nil)
        borderPanel = nil
        dimPanels.values.forEach { $0.orderOut(nil) }
        dimPanels.removeAll()
    }

    // MARK: - Quartz → Cocoa 座標変換（テスト可能な static メソッド）

    /// Quartz 座標系（原点=メインスクリーン左上、Y下向き）を
    /// Cocoa 座標系（原点=メインスクリーン左下、Y上向き）へ変換する。
    static func quartzToCocoa(_ frame: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.origin.x,
            y: screenHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    // MARK: - Private

    private func updateBorder(
        focusedID: WindowID?,
        allFrames: [(WindowID, CGRect)],
        config: LayoutConfig
    ) {
        guard config.focusBorderEnabled, let fid = focusedID,
              let quartzFrame = allFrames.first(where: { $0.0 == fid })?.1
        else {
            borderPanel?.orderOut(nil)
            return
        }

        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let expanded = quartzFrame.insetBy(dx: -config.focusBorderWidth, dy: -config.focusBorderWidth)
        let cocoaFrame = Self.quartzToCocoa(expanded, screenHeight: screenHeight)

        let panel = borderPanel ?? makeBorderPanel()
        borderPanel = panel

        // CALayer で枠線を描画
        if let layer = panel.contentView?.layer {
            layer.borderColor = config.focusBorderColor
            layer.borderWidth = config.focusBorderWidth
            layer.cornerRadius = 6
        }

        panel.setFrame(cocoaFrame, display: true)
        panel.orderFront(nil)
    }

    private func updateDim(
        focusedID: WindowID?,
        allFrames: [(WindowID, CGRect)],
        config: LayoutConfig
    ) {
        // 不要になったパネルを削除
        let currentIDs = Set(allFrames.map { $0.0 })
        let obsolete = dimPanels.keys.filter { !currentIDs.contains($0) }
        obsolete.forEach {
            dimPanels[$0]?.orderOut(nil)
            dimPanels.removeValue(forKey: $0)
        }

        guard config.focusDimEnabled else {
            dimPanels.values.forEach { $0.orderOut(nil) }
            return
        }

        let screenHeight = NSScreen.screens.first?.frame.height ?? 0

        for (wid, quartzFrame) in allFrames {
            if wid == focusedID { continue }    // フォーカス中はディム不要

            let cocoaFrame = Self.quartzToCocoa(quartzFrame, screenHeight: screenHeight)
            let panel = dimPanels[wid] ?? makeDimPanel(opacity: config.focusDimOpacity)
            dimPanels[wid] = panel

            // 不透明度が変わった場合は更新
            panel.backgroundColor = NSColor(white: 0, alpha: config.focusDimOpacity)

            panel.setFrame(cocoaFrame, display: true)
            panel.orderFront(nil)
        }

        // focusedID のパネルが残っていれば隠す
        if let fid = focusedID {
            dimPanels[fid]?.orderOut(nil)
        }
    }

    // MARK: - NSPanel ファクトリ

    private func makeBasePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView?.wantsLayer = true
        return panel
    }

    private func makeBorderPanel() -> NSPanel {
        makeBasePanel()
    }

    private func makeDimPanel(opacity: CGFloat) -> NSPanel {
        let panel = makeBasePanel()
        panel.backgroundColor = NSColor(white: 0, alpha: opacity)
        return panel
    }
}
```

- [ ] **Step 4: テストを実行して確認する**

```bash
swift test --filter FocusOverlayManagerTests 2>&1 | tail -10
```

Expected:
```
Test run started.
Testing Library Version: ...
◇ Test Suite "FocusOverlayManagerTests" started
✔ quartzToCocoaConversion (...)
✔ expandedBorderFrame (...)
Test run with 2 tests passed after ...
```

- [ ] **Step 5: ビルド確認**

```bash
swift build 2>&1 | head -20
```

Expected: `Build complete!`

- [ ] **Step 6: コミット**

```bash
git add Sources/NiriMac/Bridge/FocusOverlayManager.swift \
        Tests/NiriMacTests/FocusOverlayManagerTests.swift
git commit -m "feat: FocusOverlayManager を追加（枠線・ディムオーバーレイ管理）"
```

---

## Task 3: WindowManager に FocusOverlayManager を統合する

**Files:**
- Modify: `Sources/NiriMac/Orchestrator/WindowManager.swift`

- [ ] **Step 1: `config` を `var` に変更し `focusOverlayManager` を追加する**

`WindowManager.swift` の以下の行を修正する:

変更前:
```swift
    private let config: LayoutConfig
```

変更後:
```swift
    private var config: LayoutConfig
    private let focusOverlayManager = FocusOverlayManager()
```

- [ ] **Step 2: `stop()` に `removeAll()` を追加する**

`stop()` メソッド（106行目付近）を修正する:

変更前:
```swift
    func stop() {
        keyboard.stop()
        mouse.stop()
        observer.stopObserving()
        stopDisplayLink()
```

変更後:
```swift
    func stop() {
        focusOverlayManager.removeAll()
        keyboard.stop()
        mouse.stop()
        observer.stopObserving()
        stopDisplayLink()
```

- [ ] **Step 3: `applyLayout()` 末尾にオーバーレイ更新を追加する**

`applyLayout()` の `lastComputedFrames = allFrames` の直後（613行目付近）に追加する:

変更前:
```swift
        lastComputedFrames = allFrames
    }
```

変更後:
```swift
        lastComputedFrames = allFrames

        // フォーカスオーバーレイを更新（parkedWindowIDs を除いた可視フレームのみ渡す）
        let visibleFrames = allFrames.filter { !parkedWindowIDs.contains($0.0) }
        let screenIdx = activeScreenIndex()
        let focusedID: WindowID? = screenIdx < screens.count
            ? screens[screenIdx].activeWorkspace.activeWindowID
            : nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.focusOverlayManager.update(
                focusedID: focusedID,
                allFrames: visibleFrames,
                config: self.config
            )
        }
    }
```

- [ ] **Step 4: `toggleFocusBorder()` と `toggleFocusDim()` メソッドを追加する**

`WindowManager.swift` の `// MARK: - Actions` セクション近く（`handleAction` の前後）に追加する:

```swift
    // MARK: - Focus Highlight Toggles

    var focusBorderEnabled: Bool { config.focusBorderEnabled }
    var focusDimEnabled: Bool { config.focusDimEnabled }

    func toggleFocusBorder() {
        config.focusBorderEnabled.toggle()
        needsLayout = true
    }

    func toggleFocusDim() {
        config.focusDimEnabled.toggle()
        needsLayout = true
    }
```

- [ ] **Step 5: ビルド確認**

```bash
swift build 2>&1 | head -20
```

Expected: `Build complete!`

- [ ] **Step 6: コミット**

```bash
git add Sources/NiriMac/Orchestrator/WindowManager.swift
git commit -m "feat: WindowManager に FocusOverlayManager を統合"
```

---

## Task 4: ステータスバーメニューにトグルを追加する

**Files:**
- Modify: `Sources/NiriMac/App/NiriMacApp.swift`

- [ ] **Step 1: メニュー項目のプロパティを追加する**

`NiriMacApp.swift` のプロパティ宣言部（`pinMenuItem` の下）に追加する:

変更前:
```swift
    private var pinMenuItem: NSMenuItem?
    /// menuWillOpen 時点のカラムインデックスを保持（クリック後のフォーカス変化対策）
    private var pinnedTargetColumnIndex: Int?
```

変更後:
```swift
    private var pinMenuItem: NSMenuItem?
    private var focusBorderMenuItem: NSMenuItem?
    private var focusDimMenuItem: NSMenuItem?
    /// menuWillOpen 時点のカラムインデックスを保持（クリック後のフォーカス変化対策）
    private var pinnedTargetColumnIndex: Int?
```

- [ ] **Step 2: `setupStatusBar()` にメニュー項目を追加する**

`setupStatusBar()` の `menu.addItem(pinItem)` の直後に追加する:

変更前:
```swift
        menu.addItem(pinItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
```

変更後:
```swift
        menu.addItem(pinItem)
        menu.addItem(NSMenuItem.separator())

        let borderItem = NSMenuItem(title: "Focus Border", action: #selector(toggleFocusBorder), keyEquivalent: "")
        borderItem.target = self
        self.focusBorderMenuItem = borderItem
        menu.addItem(borderItem)

        let dimItem = NSMenuItem(title: "Focus Dim", action: #selector(toggleFocusDim), keyEquivalent: "")
        dimItem.target = self
        self.focusDimMenuItem = dimItem
        menu.addItem(dimItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
```

- [ ] **Step 3: `menuWillOpen` にチェックマーク更新を追加する**

変更前:
```swift
    func menuWillOpen(_ menu: NSMenu) {
        pinnedTargetColumnIndex = windowManager?.activeColumnIndex
        let isPinned = windowManager?.activeColumnIsPinned ?? false
        pinMenuItem?.title = isPinned ? "Unpin Column" : "Pin Column"
    }
```

変更後:
```swift
    func menuWillOpen(_ menu: NSMenu) {
        pinnedTargetColumnIndex = windowManager?.activeColumnIndex
        let isPinned = windowManager?.activeColumnIsPinned ?? false
        pinMenuItem?.title = isPinned ? "Unpin Column" : "Pin Column"
        focusBorderMenuItem?.state = windowManager?.focusBorderEnabled == true ? .on : .off
        focusDimMenuItem?.state = windowManager?.focusDimEnabled == true ? .on : .off
    }
```

- [ ] **Step 4: トグルアクションメソッドを追加する**

`togglePin()` の下に追加する:

```swift
    @objc private func toggleFocusBorder() {
        windowManager?.toggleFocusBorder()
    }

    @objc private func toggleFocusDim() {
        windowManager?.toggleFocusDim()
    }
```

- [ ] **Step 5: ビルド確認**

```bash
swift build 2>&1 | head -20
```

Expected: `Build complete!`

- [ ] **Step 6: 全テスト実行**

```bash
swift test 2>&1 | tail -10
```

Expected: 全テスト PASS

- [ ] **Step 7: コミット**

```bash
git add Sources/NiriMac/App/NiriMacApp.swift
git commit -m "feat: ステータスバーメニューに Focus Border / Focus Dim トグルを追加"
```

---

## 動作確認手順

```bash
bash make-app.sh
open NiriMac.app
```

1. ステータスバー「N」→「Focus Border」をクリック → チェックマークが付く
2. ウィンドウを複数開く → フォーカス中ウィンドウの周囲に青い枠線が表示される
3. Ctrl+Opt+→ でフォーカス移動 → 枠線が新しいフォーカスウィンドウへ移る
4. 「Focus Dim」をクリック → 非フォーカスウィンドウが暗くなる
5. 「Focus Border」を再クリック → 枠線が消える（ディムのみ残る）
6. ログ確認: `tail -f /tmp/niri-mac.log`
