# niri-mac

A scrolling tiling window manager for macOS, inspired by [niri](https://github.com/niri-wm/niri) on Linux. Built on top of the macOS Accessibility API.

## Overview

- Windows are arranged in horizontal columns; the viewport scrolls to follow focus
- **Opening new windows never resizes existing ones**
- Multiple workspaces with dynamic creation
- Pin columns to keep them always visible while scrolling
- Drag windows between columns to swap them
- Menu bar status icon for quick access

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.9 or later
- **Accessibility permission** (System Settings → Privacy & Security → Accessibility)
- **Input Monitoring permission** (System Settings → Privacy & Security → Input Monitoring)

## Build & Run

```bash
# Debug build
swift build

# Create .app bundle and sign for Accessibility permissions
bash make-app.sh

# Launch
open NiriMac.app

# View logs (real-time)
tail -f /tmp/niri-mac.log
```

After first launch, add **NiriMac.app** to both **Accessibility** and **Input Monitoring** in System Settings → Privacy & Security.

## Key Bindings

| Key | Action |
|-----|--------|
| `Ctrl+Opt+←` | Focus left column |
| `Ctrl+Opt+→` | Focus right column |
| `Ctrl+Opt+↑` | Focus window above in column |
| `Ctrl+Opt+↓` | Focus window below in column |
| `Ctrl+Opt+Shift+←` | Move column left |
| `Ctrl+Opt+Shift+→` | Move column right |
| `Ctrl+Opt+Return` | Merge window into left column |
| `Ctrl+Opt+Shift+Return` | Expel window from column |
| `Ctrl+Opt+R` | Cycle column width (1/3 → 1/2 → 2/3) |
| `Ctrl+Opt+P` | Toggle pin on active column |
| `Ctrl+Opt+Cmd+↑` | Switch to previous workspace |
| `Ctrl+Opt+Cmd+↓` | Switch to next workspace (creates new if at end) |
| `Ctrl+Opt+Cmd+Shift+↑` | Move window to workspace above |
| `Ctrl+Opt+Cmd+Shift+↓` | Move window to workspace below |
| `Ctrl+Opt+Q` | Quit |

## Trackpad & Mouse

| Gesture | Action |
|---------|--------|
| `Ctrl` + horizontal swipe | Scroll layout left/right |
| `Ctrl+Opt` + scroll | Move column focus |
| Drag window | Swap columns |

## Column Pinning

Pinned columns are fixed to the left edge of the screen and remain visible regardless of scroll position — useful for keeping a terminal or reference window always in view.

- **Keyboard**: `Ctrl+Opt+P` on the active column
- **Menu bar**: Click the `N` icon → Pin Column / Unpin Column

## Architecture

```
Sources/NiriMac/
├── Core/          # Domain models (WindowInfo, Column, Workspace, Screen, ViewOffset)
├── Engine/        # Pure layout calculation (LayoutEngine, LayoutConfig)
├── Bridge/        # macOS API boundary (AccessibilityBridge, AXObserverBridge,
│                  #   KeyboardShortcutManager, MouseEventManager)
├── Orchestrator/  # Event handling & state (WindowManager)
└── App/           # Entry point (NiriMacApp, main.swift)
```

### Data Flow

```
Events (key / mouse / AX notification)
    ↓
WindowManager (Orchestrator)
    ↓ needsLayout = true
CVDisplayLink tick (60 fps)
    ↓
LayoutEngine.computeWindowFrames()  ← pure function, no side effects
    ↓
applyWindowVisibility()
    ↓
AccessibilityBridge.setWindowFrame()  ← moves windows via AX API
```

## Limitations

- The macOS Accessibility API is best-effort; some windows may refuse to be repositioned
- Full-screen windows are not managed
- Some system windows cannot be manipulated when SIP (System Integrity Protection) is enabled

---

# niri-mac（日本語）

macOS 向けスクロールタイリングウィンドウマネージャー。
Linux の [niri](https://github.com/niri-wm/niri) に着想を得て、macOS Accessibility API で実装。

## 概要

- ウィンドウをカラム（列）単位で水平に並べ、フォーカスに追従してスクロール
- **新規ウィンドウを開いても既存ウィンドウはリサイズされない**
- 複数ワークスペース対応（動的生成）
- カラムをピン固定して常時表示できる
- ドラッグでカラム間のウィンドウをスワップ
- メニューバーアイコンからクイック操作可能

## 必要条件

- macOS 13 (Ventura) 以降
- Swift 5.9 以降
- **アクセシビリティ権限**（システム設定 → プライバシーとセキュリティ → アクセシビリティ）
- **入力監視権限**（システム設定 → プライバシーとセキュリティ → 入力監視）

## ビルド & 実行

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

初回起動後、システム設定 → プライバシーとセキュリティ で **アクセシビリティ** と **入力監視** の両方に NiriMac.app を追加する。

## キーバインド

| キー | 動作 |
|------|------|
| `Ctrl+Opt+←` | 左のカラムへフォーカス移動 |
| `Ctrl+Opt+→` | 右のカラムへフォーカス移動 |
| `Ctrl+Opt+↑` | カラム内で上のウィンドウへ |
| `Ctrl+Opt+↓` | カラム内で下のウィンドウへ |
| `Ctrl+Opt+Shift+←` | カラムを左へ移動 |
| `Ctrl+Opt+Shift+→` | カラムを右へ移動 |
| `Ctrl+Opt+Return` | 左カラムにウィンドウを吸収 |
| `Ctrl+Opt+Shift+Return` | ウィンドウをカラムから独立 |
| `Ctrl+Opt+R` | カラム幅サイクル（1/3 → 1/2 → 2/3） |
| `Ctrl+Opt+P` | アクティブカラムのピン切り替え |
| `Ctrl+Opt+Cmd+↑` | 前のワークスペースへ切り替え |
| `Ctrl+Opt+Cmd+↓` | 次のワークスペースへ切り替え（末尾なら新規作成） |
| `Ctrl+Opt+Cmd+Shift+↑` | ウィンドウを上のワークスペースへ移動 |
| `Ctrl+Opt+Cmd+Shift+↓` | ウィンドウを下のワークスペースへ移動 |
| `Ctrl+Opt+Q` | 終了 |

## トラックパッド・マウス

| 操作 | 動作 |
|------|------|
| `Ctrl` + 水平スワイプ | レイアウトを左右スクロール |
| `Ctrl+Opt` + スクロール | カラムフォーカス移動 |
| ウィンドウをドラッグ | カラム間スワップ |

## カラムピン機能

ピンされたカラムは画面左端に固定され、スクロール位置に関わらず常に表示される。ターミナルや参照用ウィンドウを常時表示したい場合に便利。

- **キーボード**: アクティブカラムで `Ctrl+Opt+P`
- **メニューバー**: `N` アイコンをクリック → Pin Column / Unpin Column

## アーキテクチャ

```
Sources/NiriMac/
├── Core/          # ドメインモデル（WindowInfo, Column, Workspace, Screen, ViewOffset）
├── Engine/        # 純粋関数レイアウト計算（LayoutEngine, LayoutConfig）
├── Bridge/        # macOS API 境界（AccessibilityBridge, AXObserverBridge,
│                  #   KeyboardShortcutManager, MouseEventManager）
├── Orchestrator/  # イベント処理・状態管理（WindowManager）
└── App/           # エントリポイント（NiriMacApp, main.swift）
```

## 制限事項

- macOS の Accessibility API はベストエフォートのためウィンドウによっては位置変更を拒否する場合がある
- フルスクリーンウィンドウは管理対象外
- SIP (System Integrity Protection) が有効な環境では一部のシステムウィンドウを操作できない
