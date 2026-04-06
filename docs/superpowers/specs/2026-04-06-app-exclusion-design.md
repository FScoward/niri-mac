# 設計ドキュメント: タイリング除外アプリ機能

**日付:** 2026-04-06  
**ステータス:** 承認済み

---

## 概要

特定のアプリケーションをタイリング管理から完全除外する機能を追加する。除外されたアプリのウィンドウは niri-mac に一切管理されず、ユーザーが自由に配置できる。設定はステータスバーメニューのサブメニューから行い、`~/.config/niri-mac/excluded-apps.json` に永続化する。

---

## セクション1: データモデルと永続化

### `LayoutConfig` への追加

```swift
var excludedBundleIDs: Set<String> = []
```

### 永続化ファイル

パス: `~/.config/niri-mac/excluded-apps.json`

```json
{
  "excludedBundleIDs": ["com.apple.finder", "com.docker.docker"]
}
```

### 新規ファイル: `Sources/NiriMac/Bridge/ExclusionStore.swift`

責務: 設定ファイルの読み書きのみ。

- `static func load() -> Set<String>` — 起動時に読み込み。ファイル不在・パース失敗時は空セットを返し、ログに警告を出力。
- `static func save(_ ids: Set<String>)` — 変更時に書き込み。ディレクトリが存在しない場合は自動作成。

---

## セクション2: ウィンドウ除外ロジック

### `WindowManager` の変更箇所

**`discoverExistingWindows()`:**
```swift
for window in windows {
    guard !isExcluded(window) else { continue }
    windowRegistry[window.id] = window
    assignWindowToScreen(window)
}
```

**`handleWindowCreated()`:**
```swift
guard !isExcluded(window) else { return }
```

**判定ヘルパー（private）:**
```swift
private func isExcluded(_ window: WindowInfo) -> Bool {
    guard let bundleID = window.ownerBundleID else { return false }
    return config.excludedBundleIDs.contains(bundleID)
}
```

### 除外追加時の即時反映

除外アプリをメニューから追加した瞬間、既にタイリングに入っているウィンドウを `windowRegistry` と全カラムから削除し、`applyLayout` を呼ぶ。

### 除外解除後の復帰

次回起動時に `discoverExistingWindows` で自動取り込み（即時復帰は実装しない）。

---

## セクション3: ステータスバーメニューUI

### メニュー構成

```
N  ← ステータスバーアイコン
├─ niri-mac
├─ ──────────────
├─ Pin Column
├─ ──────────────
├─ Excluded Apps ▶
│   ├─ Exclude Current App   ← フォーカス中アプリを追加（bundleID不明時はdisabled）
│   ├─ ──────────────
│   ├─ ✓ Finder              ← クリックで除外解除
│   └─ ✓ Docker Desktop      ← クリックで除外解除
├─ Focus Border
├─ Focus Dim
├─ ──────────────
└─ Quit
```

### 動作詳細

- **Exclude Current App:** `WindowManager.focusedAppBundleID` を取得 → `config.excludedBundleIDs` に追加 → `ExclusionStore.save()` → 既存ウィンドウを即座にレイアウトから削除 → `applyLayout`
- **各除外アプリ（クリック）:** リストから削除 → `ExclusionStore.save()` → `applyLayout`
- **メニューオープン時:** `menuWillOpen` でサブメニューを動的生成（アプリ名は `NSRunningApplication` から取得、不明時は bundleID をそのまま表示）

### `WindowManager` に追加するパブリックAPI

```swift
var focusedAppBundleID: String? { get }
func excludeApp(bundleID: String)
func includeApp(bundleID: String)
var excludedApps: [(bundleID: String, name: String)] { get }
```

---

## セクション4: エラーハンドリング・エッジケース

| ケース | 対応 |
|--------|------|
| JSONファイルが壊れている | 空セットで起動、ログに警告出力 |
| `~/.config/niri-mac/` が存在しない | 保存時に自動作成 (`FileManager.createDirectory`) |
| bundleIDが取得できないウィンドウ | `isExcluded` が `false` を返す（除外チェックをスキップ） |
| フォーカス中アプリのbundleIDが不明 | 「Exclude Current App」をグレーアウト（disabled） |
| 除外解除後の即時復帰 | 実装しない（次回起動時に自動取り込み） |

---

## 変更ファイルまとめ

| ファイル | 変更種別 |
|----------|----------|
| `Sources/NiriMac/Bridge/ExclusionStore.swift` | **新規作成** |
| `Sources/NiriMac/Engine/LayoutConfig.swift` | `excludedBundleIDs` フィールド追加 |
| `Sources/NiriMac/Orchestrator/WindowManager.swift` | `isExcluded` / `excludeApp` / `includeApp` / `focusedAppBundleID` 追加、登録ロジックにガード追加 |
| `Sources/NiriMac/App/NiriMacApp.swift` | 「Excluded Apps」サブメニュー追加 |
