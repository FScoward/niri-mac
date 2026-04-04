# niri-mac

macOS 向けスクロールタイリングウィンドウマネージャー。
Linux の [niri](https://github.com/niri-wm/niri) に着想を得て、macOS Accessibility API で実装。

## 概要

- ウィンドウをカラム（列）単位で水平に並べ、フォーカスに追従してスクロール
- **新規ウィンドウを開いても既存ウィンドウはリサイズされない**
- 複数ワークスペース対応（動的生成）
- メニューバーのステータスアイテムで動作確認可能

## 必要条件

- macOS 13 (Ventura) 以降
- Swift 5.9 以降
- **アクセシビリティ権限**（システム設定 > プライバシーとセキュリティ > アクセシビリティ）

## ビルド & 実行

```bash
swift build
.build/debug/NiriMac
```

## キーバインド

| キー | 動作 |
|------|------|
| `Cmd+Opt+←` | 左のカラムへフォーカス移動 |
| `Cmd+Opt+→` | 右のカラムへフォーカス移動 |
| `Cmd+Opt+↑` | カラム内で上のウィンドウへ |
| `Cmd+Opt+↓` | カラム内で下のウィンドウへ |
| `Cmd+Opt+Shift+←` | カラムを左へ移動 |
| `Cmd+Opt+Shift+→` | カラムを右へ移動 |
| `Cmd+Opt+Return` | 左カラムにウィンドウを吸収 |
| `Cmd+Opt+Shift+Return` | ウィンドウをカラムから独立 |
| `Cmd+Opt+Q` | 終了 |

## アーキテクチャ

```
Sources/NiriMac/
├── Core/          # ドメインモデル (WindowInfo, Column, Workspace, Screen, ViewOffset)
├── Engine/        # 純粋関数レイアウト計算 (LayoutEngine, LayoutConfig)
├── Bridge/        # macOS API 境界 (AccessibilityBridge, AXObserverBridge, KeyboardShortcutManager)
├── Orchestrator/  # イベント処理・状態管理 (WindowManager)
└── App/           # エントリポイント (NiriMacApp, main.swift)
```

## 制限事項

- macOS の Accessibility API はベストエフォートのためウィンドウによっては位置変更を拒否する場合がある
- フルスクリーンウィンドウは管理対象外
- SIP (System Integrity Protection) が有効な環境では一部のシステムウィンドウを操作できない
