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

### 主要クラス・型

| 型 | 役割 |
|----|------|
| `WindowManager` | 全イベントのハブ。スクリーン/ワークスペース/ウィンドウ状態を保持 |
| `Workspace` | カラムの水平ストリップ + `ViewOffset`（スクロール位置）+ `workingArea` |
| `Column` | ウィンドウIDの配列 + 幅 + アクティブインデックス + 高さ分布 |
| `ViewOffset` | スクロールアニメーション状態機械（easeOutCubic） |
| `LayoutEngine` | 純粋関数群。フレーム計算のみ、副作用なし |
| `LayoutConfig` | gap/幅/アニメーション時間等の設定値 |
| `AccessibilityBridge` | AX API ラッパー（`setWindowFrame`/`windowFrame`/`focusWindow`） |
| `AXObserverBridge` | ウィンドウ作成・破棄・移動の AX 通知監視 |
| `SpaceBridge` | CGS Space API ラッパー（現在は `currentSpaceID()` のみ実用） |

## ログ

全ログは `/tmp/niri-mac.log` に出力される。起動時にバージョンバナーが出るので、正しいビルドが動いているか確認できる。

主なログプレフィックス:
- `[layout]` — フレーム計算・適用（`🅿️ hide` = 画面外退避、`↩️ show` = 復帰）
- `[space]` — CGS Space API 呼び出し
- `[niri-mac]` — 起動・バージョン情報
