# Meta Key & Scroll Modifier Configuration — Design Spec

**Date:** 2026-04-25  
**Status:** Approved

## Overview

キーボードショートカットのベース修飾キー（Keyboard Meta）と、マウス/トラックパッドスクロールの修飾キー（Scroll: Layout / Scroll: Focus）をステータスバーメニューから自由に変更できるようにする。変更は次回起動時に反映される。

## Requirements

- 以下の3つの修飾キーセットを、Control / Option / Command / Shift の自由な組み合わせで設定できる
  1. **Keyboard Meta**: キーボードショートカットのベース修飾キー（デフォルト: `Ctrl+Opt`）
  2. **Scroll: Layout**: レイアウトスクロールのトリガー修飾キー（デフォルト: `Option`）
  3. **Scroll: Focus**: カラムフォーカス移動スクロールのトリガー修飾キー（デフォルト: `Ctrl+Opt`）
- 設定はステータスバーメニューの GUI から変更する
- 変更は次回起動時に反映される（即時反映なし）
- メニューから「Restart to Apply...」で再起動できる
- `Ctrl` のみ + 水平スクロールによるレイアウトスクロールは対象外（ハードコードのまま）

## Architecture

### Data Model

`LayoutConfig` に3フィールドを追加する：

```swift
// Engine/LayoutConfig.swift
var metaModifiers: NSEvent.ModifierFlags = [.control, .option]
var scrollLayoutModifiers: NSEvent.ModifierFlags = [.option]
var scrollFocusModifiers: NSEvent.ModifierFlags = [.control, .option]
```

### Config Persistence — `ConfigStore.swift`（新規）

`ExclusionStore` と同パターン。`~/.config/niri-mac/config.json` に JSON で保存。

```json
{
  "metaModifiers": ["control", "option"],
  "scrollLayoutModifiers": ["option"],
  "scrollFocusModifiers": ["control", "option"]
}
```

- 起動時に `NiriMacApp` が `ConfigStore.load()` → `LayoutConfig` の各フィールドにセット
- メニュー変更時に `ConfigStore.save()` を呼ぶ
- ファイル不在・パース失敗時はデフォルト値を使用

### KeyboardShortcutManager — 動的バインディング生成

現在のハードコード `bindings` 配列を削除し、`start()` 時に `metaModifiers` から動的生成する。

バインディング tier：

| tier | 修飾キー | 代表アクション |
|------|----------|----------------|
| meta | `metaModifiers` | フォーカス移動・基本操作 |
| meta+shift | `metaModifiers ∪ [.shift]` | カラム並べ替え・ウィンドウ並べ替え |
| meta+cmd | `metaModifiers ∪ [.command]` | ワークスペース切り替え |
| meta+cmd+shift | `metaModifiers ∪ [.command, .shift]` | ウィンドウをワークスペース移動 |

**競合制約:** `metaModifiers` に `.command` を含む場合、tier1 と tier3 が同一になるため競合する。この場合メニューで警告を表示する（設定自体は保存可能だが、ワークスペース操作が機能しなくなる旨を明示）。

### MouseEventManager — 動的 suppress ロジック

現在の suppress ロジック（`Option` のみ固定）を動的化する。

```swift
// 変更前（ハードコード）
let suppress = cgFlags.contains(.maskAlternate)
            && !cgFlags.contains(.maskControl)
            && !cgFlags.contains(.maskCommand)

// 変更後（動的）
// scrollLayoutModifiers を外部から注入し、それとフラグが一致する場合に suppress
let suppress = matchesModifiers(cgFlags, required: scrollLayoutModifiers)
```

`MouseEventManager` は `scrollLayoutModifiers: NSEvent.ModifierFlags` を保持し、`WindowManager` から渡されるようにする。

### WindowManager — 動的スクロールハンドラ

`handleScroll` 内のハードコード修飾キー判定を `LayoutConfig` の値で置き換える：

```swift
// 変更前
if filtered == [.control, .option] { // カラムフォーカス移動
if filtered == [.option] {           // レイアウトスクロール

// 変更後
if filtered == config.scrollFocusModifiers {
if filtered == config.scrollLayoutModifiers {
```

### Status Bar Menu — UI

3つの修飾キーサブメニューと「Restart to Apply...」を追加：

```
Keyboard Meta ▶
  ✓ Control (⌃)
  ✓ Option  (⌥)
    Command (⌘)   ← ⚠️ チェック時「ワークスペース操作と競合します」を表示
    Shift   (⇧)

Scroll: Layout ▶
    Control (⌃)
  ✓ Option  (⌥)
    Command (⌘)
    Shift   (⇧)

Scroll: Focus ▶
  ✓ Control (⌃)
  ✓ Option  (⌥)
    Command (⌘)
    Shift   (⇧)

──────────────
(再起動後に反映)

Restart to Apply...   ← いずれかの設定変更後に enabled になる
```

バリデーション（3つ全てに共通）：
- チェック数 < 1 → 変更を拒否し「最低1つ選択してください」を表示
- Keyboard Meta で `.command` を追加した場合 → 「⚠️ ワークスペース操作と競合します」を表示（拒否はしない）

「Restart to Apply...」の動作：
- 全設定未変更時は grayed out
- クリック → 確認アラート「再起動して設定変更を適用しますか？」→ OK で再起動
- 再起動実装: `Process` で `open 'NiriMac.app'` をスリープ後に起動し、`NSApplication.shared.terminate(nil)` で終了

## Data Flow

```
起動時:
ConfigStore.load()
  → LayoutConfig.metaModifiers
  → LayoutConfig.scrollLayoutModifiers
  → LayoutConfig.scrollFocusModifiers
  → KeyboardShortcutManager.buildBindings(meta: metaModifiers)
  → MouseEventManager.scrollLayoutModifiers = scrollLayoutModifiers
  → WindowManager が scrollFocusModifiers / scrollLayoutModifiers を参照

メニュー変更時:
ユーザーがトグル → バリデーション → ConfigStore.save() → "Restart to Apply..." が enabled に

再起動時:
"Restart to Apply..." クリック → 確認アラート → NSApplication 再起動
```

## Files Changed

| ファイル | 変更種別 | 内容 |
|----------|----------|------|
| `Engine/LayoutConfig.swift` | 変更 | `metaModifiers` / `scrollLayoutModifiers` / `scrollFocusModifiers` 追加 |
| `Bridge/ConfigStore.swift` | **新規** | JSON 永続化（load/save） |
| `Bridge/KeyboardShortcutManager.swift` | 変更 | bindings を動的生成に変更 |
| `Bridge/MouseEventManager.swift` | 変更 | suppress ロジックを動的化、`scrollLayoutModifiers` を注入 |
| `Orchestrator/WindowManager.swift` | 変更 | スクロールハンドラの修飾キー判定を動的化 |
| `App/NiriMacApp.swift` | 変更 | ConfigStore 読み込み・3つのサブメニュー・Restart メニュー追加 |

## Out of Scope

- `Ctrl` のみ + 水平スクロールによるレイアウトスクロール（ハードコードのまま）
- 即時反映（再起動が必要）
- アクションごとの個別キーバインド設定
