# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# デバッグビルド
swift build

# .app バンドルを作成してアクセシビリティ権限用に署名
bash make-app.sh

# アプリ起動
open NiriMac.app

# ログ確認（リアルタイム）
tail -f /tmp/niri-mac.log
```

初回起動後、システム設定 > プライバシーとセキュリティ で **アクセシビリティ** と **入力監視** の両方に NiriMac.app を追加する必要がある。

## アーキテクチャ

```
Sources/NiriMac/
├── Core/          # ドメインモデル（副作用なし）
├── Engine/        # 純粋関数レイアウト計算
├── Bridge/        # macOS API 境界
├── Orchestrator/  # イベント処理・状態管理
└── App/           # エントリポイント
```

### データフロー

```
イベント（キー/マウス/AX通知）
    ├─ KeyboardShortcutManager（CGEventTap: グローバルキー入力）
    ├─ MouseEventManager（CGEventTap: クリック・スクロール・AppSwitch）
    └─ AXObserverBridge（ウィンドウ作成・破棄・移動通知）
    ↓
WindowManager（Orchestrator）
    ↓ needsLayout = true
CVDisplayLink tick（60fps）
    ↓
LayoutEngine.computeWindowFrames()  ← 純粋関数、副作用なし
    ↓
applyWindowVisibility()
    ↓
AccessibilityBridge.setWindowFrame()  ← AX API で実際に移動
```

### 重要な設計判断

**画面外ウィンドウの非表示方式**: macOS の CGS Space API（`CGSAddWindowsToSpaces` 等）は実際にウィンドウを別スペースへ移動できないため使用しない。代わりに `setWindowFrame` で画面外座標（左: `screen.minX - width - 1`、右: `screen.maxX + 1`）に移動することで非表示化している。`parkedWindowIDs: Set<WindowID>` でキャッシュし、毎フレームの再適用を防ぐ。

**ViewOffset 状態機械**: `.static(offset:)` と `.animating(from:to:startTime:duration:)` の2状態。`current` プロパティが `CACurrentMediaTime()` を参照して補間値を返す。CVDisplayLink の tick で毎フレーム読み取られる。

**`applyLayout` の呼び出し規則**: 原則 `needsLayout = true` を立てて displayLinkTick 経由で処理。`start()` の初期化時のみ `applyLayout(animated: false)` を直接呼ぶ。

**`onAppActivated` debounce**: `setWindowFrame` がアプリアクティベーション通知を誤発火させるため、0.3秒 debounce で間引いている。

**座標系**: `LayoutEngine.computeWindowFrames` が返す座標は Quartz 座標系（原点=メインスクリーン左上、Y軸下向き）。`setupScreens()` で Cocoa → Quartz 変換済みの `workingArea` を使う。

**Pinned カラム**: `Column.isPinned = true` のカラムは `viewOffset` を無視して画面左端に固定表示される。非pinnedカラムはpinned領域の右側からスクロール可能に配置される。ステータスバーメニューと `Ctrl+Opt+P` キーで切替。

**ドラッグ＆スワップ**: `mouseDown` でウィンドウIDと元フレームを記録 → 移動距離 > 20px（`dragThreshold`）で drag確定 → `mouseUp` 時に drop先ウィンドウとスワップ（`Workspace.swapWindows`）。`swapCooldownEnd` で `applyLayout` 由来の `windowMoved` 誤検知を0.5秒防止する。

**動的ワークスペース**: `switchWorkspaceDown` で末尾ワークスペースに達すると新規ワークスペースを自動作成（`Screen.addWorkspace`）。

**スクロールフォーカス移動クールダウン**: マウス/トラックパッドスクロールによるフォーカス移動は 0.3秒（`scrollFocusCooldown`）の cooldown で連打を防止する。

**カラム幅サイクル**: `Ctrl+Opt+R` で 1/3 → 1/2 → 2/3 → 1.0（画面幅比率）をサイクル。

### 主要クラス・型

| 型 | 役割 |
|----|------|
| `WindowManager` | 全イベントのハブ。スクリーン/ワークスペース/ウィンドウ状態を保持 |
| `Workspace` | カラムの水平ストリップ + `ViewOffset`（スクロール位置）+ `workingArea` |
| `Column` | ウィンドウIDの配列 + 幅 + アクティブインデックス + 高さ分布 + `isPinned` |
| `ViewOffset` | スクロールアニメーション状態機械（easeOutCubic） |
| `HeightDistribution` | カラム内ウィンドウの高さ配分（`.equal` / `.proportional([CGFloat])`） |
| `LayoutEngine` | 純粋関数群。フレーム計算のみ、副作用なし |
| `LayoutConfig` | gap/幅/アニメーション時間/スクロール感度等の設定値 |
| `WindowInfo` | AXUIElement ラッパー。windowID/PID/frame/最小化・フルスクリーン状態を保持 |
| `AccessibilityBridge` | AX API ラッパー（`setWindowFrame`/`windowFrame`/`focusWindow`）、`AccessibilityBridgeProtocol` 準拠 |
| `AXObserverBridge` | ウィンドウ作成・破棄・移動の AX 通知監視 |
| `KeyboardShortcutManager` | グローバルキーショートカット（CGEventTap 優先、失敗時 NSEvent フォールバック） |
| `MouseEventManager` | CGEventTap でクリック・スクロール・AppSwitch を捕捉してコールバック通知 |
| `SpaceBridge` | CGS Space API ラッパー（現在は `currentSpaceID()` のみ実用） |
| `NiriMacApp` | NSApplicationDelegate。ステータスバーメニュー（Pin Column / Quit）を管理 |
| `WindowIDSet` / `Direction` | ユーティリティ型（Core/Types.swift） |
| `PrivateAPI` | プライベート AX/CGS API の宣言（`_AXUIElementGetWindow`、CGS Space 系） |

## キーボードショートカット

| 修飾キー | キー | アクション |
|---|---|---|
| Ctrl+Opt | ← → | カラム間フォーカス移動 |
| Ctrl+Opt | ↑ ↓ | カラム内ウィンドウ移動（上下） |
| Ctrl+Opt+Shift | ← → | カラム並べ替え（左右） |
| Ctrl+Opt+Cmd | ↑ ↓ | ワークスペース切り替え |
| Ctrl+Opt+Cmd+Shift | ↑ ↓ | アクティブウィンドウをワークスペース移動 |
| Ctrl+Opt | Return | 左カラムに吸収（consumeIntoColumnLeft） |
| Ctrl+Opt+Shift | Return | カラムから追い出し（expelFromColumn） |
| Ctrl+Opt | R | カラム幅サイクル（1/3 → 1/2 → 2/3 → 1.0） |
| Ctrl+Opt | P | Pin/Unpin カラム |
| Ctrl+Opt | Q | 終了 |

マウス操作: クリックでウィンドウフォーカス、水平スクロールでスクロール移動、ウィンドウをドラッグ（20px以上）でスワップ。

## LayoutConfig 主要パラメータ

| パラメータ | デフォルト | 説明 |
|---|---|---|
| `gapWidth` | 16 | カラム間のギャップ |
| `gapHeight` | 16 | カラム内ウィンドウ間のギャップ |
| `defaultColumnWidthFraction` | 1/3 | 新規ウィンドウのデフォルトカラム幅（画面幅比率） |
| `animationDuration` | 0.25s | ウィンドウアニメーション時間 |
| `warpMouseToFocus` | true | フォーカス移動時にマウスカーソルをウィンドウ中央にワープ |
| `scrollSensitivity` | 0.5 | トラックパッド水平スクロール感度 |
| `mouseWheelScrollSensitivity` | 20.0 | マウスホイールスクロール感度 |

## ログ

全ログは `/tmp/niri-mac.log` に出力される。起動時にバージョンバナーが出るので、正しいビルドが動いているか確認できる。

主なログプレフィックス:
- `[layout]` — フレーム計算・適用（`🅿️ hide` = 画面外退避、`↩️ show` = 復帰）
- `[action]` — キーボード/マウスアクション実行（`WindowManager.handleAction` 内）
- `[space]` — CGS Space API 呼び出し
- `[niri-mac]` — 起動・バージョン情報

## 受け入れ条件の記載ルール

→ `.claude/acceptance-criteria.md` 参照
