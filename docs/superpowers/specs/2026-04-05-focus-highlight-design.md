# Focus Highlight Design

**Date:** 2026-04-05  
**Status:** Approved  
**Feature:** フォーカスウィンドウの視覚的区別（枠線 + ディム効果）

---

## 概要

フォーカス中のウィンドウを視覚的にわかりやすくするため、2つのオーバーレイ効果を追加する。

- **Focus Border**: フォーカス中ウィンドウの周囲に有色の枠線を表示
- **Focus Dim**: 非フォーカスウィンドウに半透明の暗いオーバーレイを重ねる

両効果は独立してON/OFFでき、ステータスバーメニューから切替可能。色・不透明度はデフォルト値として設定し将来の設定ファイル対応時に拡張する。

---

## アーキテクチャ

### 変更ファイル一覧

| ファイル | 変更種別 | 内容 |
|---|---|---|
| `Engine/LayoutConfig.swift` | 修正 | フォーカス関連設定値を追加 |
| `Bridge/FocusOverlayManager.swift` | 新規 | NSPanelオーバーレイ管理クラス |
| `Orchestrator/WindowManager.swift` | 修正 | `applyLayout` 末尾でオーバーレイ更新、`stop()` でクリア |
| `App/NiriMacApp.swift` | 修正 | ステータスバーメニューにトグル追加 |

### データフロー

```
CVDisplayLink tick
    ↓
WindowManager.applyLayout()
    ↓ computeWindowFrames() → allFrames
    ↓ AccessibilityBridge.setWindowFrame() （既存）
    ↓
FocusOverlayManager.update(focusedID:allFrames:config:)
    ├─ config.focusBorderEnabled → borderPanel を配置/非表示
    └─ config.focusDimEnabled   → dimPanels を配置/非表示
```

---

## 詳細設計

### 1. LayoutConfig への追加

```swift
// Engine/LayoutConfig.swift
var focusBorderEnabled: Bool = false
var focusBorderColor: CGColor = NSColor.systemBlue.cgColor
var focusBorderWidth: CGFloat = 4.0

var focusDimEnabled: Bool = false
var focusDimOpacity: CGFloat = 0.4
```

### 2. FocusOverlayManager

```swift
// Bridge/FocusOverlayManager.swift
final class FocusOverlayManager {
    private var borderPanel: NSPanel?
    private var dimPanels: [WindowID: NSPanel] = [:]

    func update(
        focusedID: WindowID?,
        allFrames: [(WindowID, CGRect)],
        config: LayoutConfig
    )

    func removeAll()
}
```

**NSPanel 共通設定:**
- `styleMask: .borderless`
- `level: .floating`
- `ignoresMouseEvents = true`
- `isOpaque = false`
- `backgroundColor = .clear`

**Focus Border パネル:**
- フォーカスウィンドウフレームを `borderWidth` 分外側に広げたフレームで配置
- `CALayer` の `borderColor` / `borderWidth` / `cornerRadius` で枠線を描画
- `focusBorderEnabled = false` または `focusedID = nil` の場合は非表示

**Focus Dim パネル:**
- 非フォーカスの各ウィンドウと同一フレームで配置
- `backgroundColor = NSColor(white: 0, alpha: focusDimOpacity)`
- `focusDimEnabled = false` の場合は全て非表示
- ウィンドウ増減に応じて `dimPanels` を追加/削除

### 3. WindowManager 統合

```swift
// applyLayout() 末尾に追加
let focusedID = activeWorkspace.activeWindowID
focusOverlayManager.update(
    focusedID: focusedID,
    allFrames: allFrames,
    config: config
)

// stop() に追加
focusOverlayManager.removeAll()
```

`parkedWindowIDs`（画面外に退避したウィンドウ）のフレームはオーバーレイ対象から除外する。

### 4. ステータスバーメニュー

`NiriMacApp.buildMenu()` に以下を追加（Pin Column の下）:

```
─────────────────
Focus Border    ✓/○
Focus Dim       ✓/○
─────────────────
```

トグル時: `config.focusBorderEnabled.toggle()` → `windowManager?.needsLayout = true`

---

## 設計上の判断

- **NSPanel を使う理由**: AXUIElement でサードパーティウィンドウの描画内容を変更することはできないため、オーバーレイウィンドウで視覚効果を実現する。
- **`level: .floating`**: ウィンドウマネージャが管理する通常ウィンドウより上に表示されるが、システムUIより下に留まる。
- **parkedWindowIDs の除外**: 画面外に退避したウィンドウにオーバーレイを重ねるとパフォーマンス劣化や誤表示の原因になるため除外する。
- **色・不透明度のUI**: 現時点ではメニューからON/OFFのみ。カラーピッカー等は将来の設定ファイル対応時に追加する。

---

## 将来の拡張

- 設定ファイル（JSON/TOML）から `focusBorderColor` / `focusDimOpacity` を読み込む
- アニメーション付きフェードイン/アウト（`animationDuration` を流用）
- ダークモード対応のデフォルトカラー自動選択
