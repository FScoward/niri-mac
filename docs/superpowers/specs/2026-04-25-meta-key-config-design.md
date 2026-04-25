# Meta Key Configuration — Design Spec

**Date:** 2026-04-25  
**Status:** Approved

## Overview

キーボードショートカットのベース修飾キー（メタキー）をステータスバーメニューから自由に変更できるようにする。変更は次回起動時に反映される。マウススクロールの修飾キーは対象外。

## Requirements

- ユーザーは Control / Option / Command / Shift を自由に組み合わせてメタキーを設定できる
- 設定はステータスバーメニューの GUI から変更する
- 変更は次回起動時に反映される（即時反映なし）
- メニューから「Restart to Apply」で再起動できる
- マウススクロールの修飾キー（Ctrl スクロール、Option スクロール）は変更対象外

## Architecture

### Data Model

`LayoutConfig` に `metaModifiers` を追加する：

```swift
// Engine/LayoutConfig.swift
var metaModifiers: NSEvent.ModifierFlags = [.control, .option]
```

### Config Persistence — `ConfigStore.swift`（新規）

`ExclusionStore` と同パターン。`~/.config/niri-mac/config.json` に JSON で保存。

```json
{ "metaModifiers": ["control", "option"] }
```

- 起動時に `NiriMacApp` が `ConfigStore.load()` → `LayoutConfig.metaModifiers` にセット
- メニュー変更時に `ConfigStore.save()` を呼ぶ
- ファイル不在・パース失敗時はデフォルト `[.control, .option]` を使用

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

### Status Bar Menu — UI

「Meta Key」サブメニューと「Restart to Apply...」メニュー項目を追加：

```
Meta Key ▶
  ✓ Control (⌃)
  ✓ Option  (⌥)
    Command (⌘)   ← ⚠️ チェック時「ワークスペース操作と競合します」を表示
    Shift   (⇧)
  ──────────────
  (再起動後に反映)

Restart to Apply...   ← Meta Key 変更後に enabled になる
```

バリデーション：
- チェック数 < 2 → 変更を拒否し「最低2つ選択してください」を表示
- `.command` 追加時 → 「⚠️ ワークスペース操作と競合します」を表示（拒否はしない）

「Restart to Apply...」の動作：
- Meta Key 未変更時は grayed out
- クリック → 確認アラート「再起動してメタキーの変更を適用しますか？」→ OK で再起動
- 再起動実装: `Process` で `open 'NiriMac.app'` をスリープ後に起動し、`NSApplication.shared.terminate(nil)` で終了

## Data Flow

```
起動時:
ConfigStore.load() → LayoutConfig.metaModifiers
LayoutConfig.metaModifiers → KeyboardShortcutManager.buildBindings()

メニュー変更時:
ユーザーがトグル → バリデーション → ConfigStore.save() → "Restart to Apply..." が enabled に

再起動時:
"Restart to Apply..." クリック → 確認アラート → NSApplication 再起動
```

## Files Changed

| ファイル | 変更種別 | 内容 |
|----------|----------|------|
| `Engine/LayoutConfig.swift` | 変更 | `metaModifiers: NSEvent.ModifierFlags` 追加 |
| `Bridge/ConfigStore.swift` | **新規** | JSON 永続化（load/save） |
| `Bridge/KeyboardShortcutManager.swift` | 変更 | bindings を動的生成に変更 |
| `App/NiriMacApp.swift` | 変更 | ConfigStore 読み込み・Meta Key メニュー・Restart メニュー追加 |

## Out of Scope

- マウススクロールの修飾キー変更（Ctrl スクロール・Option スクロールはハードコードのまま）
- 即時反映（再起動が必要）
- アクションごとの個別キーバインド設定
