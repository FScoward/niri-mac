# niri-mac — macOS に「スクロールするタイリング」を持ち込む新感覚WM

## はじめに

Macでウィンドウ管理に悩んだことはないだろうか。

デスクトップに散らばるウィンドウ、重なり合うアプリ、Command+Tab を連打し続ける日々——。そんな人に今すぐ試してほしいのが **niri-mac** だ。

Linux の高評価ウィンドウマネージャー [niri](https://github.com/niri-wm/niri) にインスパイアされ、macOS の Accessibility API を使って Swift で一から実装されたスクロール型タイリングWMである。

---

## niri-mac とは？

**「カラム（列）」単位でウィンドウを並べ、フォーカスが動いたら画面がスクロールして追いかける**——それが niri-mac のコアコンセプトだ。

従来のタイリングWMはすべてのウィンドウを画面に収めようとするため、ウィンドウが増えるたびに既存のものが縮んでいく。niri-mac は発想を逆転させた。

> **新しいウィンドウを開いても、既存のウィンドウは一切リサイズされない。**

代わりに、無限に続く横長の仮想キャンバスにカラムが追加されていく。ユーザーは Ctrl+スクロールやキーボードショートカットでカラム間を移動し、フォーカスしたカラムが常に画面中央に来るようにビューポートがスムーズにスクロールする。まるで **IDE のコードエディタをウィンドウ管理に応用した**ような体験だ。

---

## ここが魅力

### 1. ウィンドウが「押しつぶされない」

既存のWMで 4 枚目のウィンドウを開いたとき、全部が細切れになる悲劇を経験した人は多いはずだ。niri-mac ではそれが起きない。各カラムは独立した幅（画面幅の 1/3・1/2・2/3 を `Ctrl+Opt+R` でサイクル）を保ち、新しいウィンドウは右端に追加されるだけ。

### 2. トラックパッドと相性抜群

Ctrl を押しながら水平スワイプするだけでレイアウト全体がスルスルとスクロールする。MacBook のトラックパッドでこれをやると、慣性スクロールも効いて非常に気持ちいい。また Option+スクロールでも同様に操作できる。

### 3. カラムのピン固定

「ターミナルだけは常に左に置いておきたい」という要望に応えるのが **Pin 機能**だ。`Ctrl+Opt+P` でアクティブカラムをピン固定すると、他のカラムがスクロールしても左端に張り付いたまま動かない。参照ドキュメントやチャットを固定しておく使い方にも最適。

### 4. ドラッグ＆スワップ

ウィンドウを 20px 以上ドラッグして別カラムにドロップするだけで、二つのウィンドウの位置がスワップされる。直感的でキーボードを使わない操作も完結できる。

### 5. 動的ワークスペース

`Ctrl+Opt+Cmd+↓` で次のワークスペースへ移動でき、末尾に達すると自動で新規ワークスペースが生成される。無限に増やせるワークスペースでプロジェクトやコンテキストを分離できる。

### 6. 複数ウィンドウのカラム集約

同一アプリの複数ウィンドウを一つのカラムにスタックしたいときは `Ctrl+Opt+Return` で左カラムに吸収でき、逆に `Ctrl+Opt+Shift+Return` でカラムから独立させることもできる。

---

## キーボードショートカット早見表

| キー | 動作 |
|------|------|
| `Ctrl+Opt+← →` | カラム間フォーカス移動 |
| `Ctrl+Opt+↑ ↓` | カラム内でウィンドウ上下移動 |
| `Ctrl+Opt+Shift+← →` | カラムを左右に並び替え |
| `Ctrl+Opt+R` | カラム幅サイクル（1/3 → 1/2 → 2/3） |
| `Ctrl+Opt+P` | カラムをピン固定／解除 |
| `Ctrl+Opt+Return` | 左カラムに吸収 |
| `Ctrl+Opt+Shift+Return` | カラムから独立 |
| `Ctrl+Opt+Cmd+↑ ↓` | ワークスペース切り替え |
| `Ctrl+Opt+Cmd+Shift+↑ ↓` | ウィンドウをワークスペース移動 |
| `Ctrl+Opt+- / =` | ウィンドウ高さを縮小／拡大 |
| `Ctrl+Opt+A` | Auto-Fit モード ON/OFF |

---

## インストール方法

### 必要なもの

- macOS 13 (Ventura) 以降
- Swift 5.9 以降
- アクセシビリティ権限・入力監視権限

### 手順

```bash
git clone https://github.com/FScoward/niri-mac.git
cd niri-mac

# .app バンドルを作成
bash make-app.sh

# 起動
open NiriMac.app
```

初回起動後、**システム設定 → プライバシーとセキュリティ** で「アクセシビリティ」と「入力監視」の両方に NiriMac.app を追加する。

---

## こんな人に特にお勧め

- **エンジニア・開発者**: エディタ・ターミナル・ブラウザ・Slack を常時並べて作業したい人
- **マルチモニター派**: サブモニターのウィンドウ整理が雑になりがちな人
- **Linux の i3/Sway/niri 経験者**: Mac に移行してもタイリングWMが手放せない人
- **キーボード中心主義者**: マウスを使わず高速にウィンドウを操りたい人

---

## 制限事項

- macOS の Accessibility API はベストエフォートなので、一部のウィンドウ（SIP 保護下のシステムアプリなど）は位置変更を拒否することがある
- フルスクリーンウィンドウは管理対象外
- iTerm2 などの文字グリッド型ターミナルは、高さがセル単位にスナップされるため、ピクセル完全には高さが合わないことがある

---

## まとめ

niri-mac は「macOS の流儀」をなるべく崩さずに、タイリングWMの生産性を持ち込む稀有なツールだ。インストールは数分、設定ファイルも不要、Swift 製なのでパフォーマンスも申し分ない。

一度「ウィンドウが押しつぶされない世界」を体験すると、もう元には戻れない。

---

---

# niri-mac — Bringing "Scrollable Tiling" to macOS

## Introduction

Have you ever felt overwhelmed managing windows on your Mac?

Windows scattered across your desktop, apps stacking on top of each other, endlessly pressing Command+Tab — if that sounds familiar, **niri-mac** is exactly what you need.

Inspired by the acclaimed Linux window manager [niri](https://github.com/niri-wm/niri), niri-mac is a scrollable tiling window manager built entirely in Swift on top of the macOS Accessibility API.

---

## What is niri-mac?

The core concept is simple: **windows are arranged in horizontal columns, and the viewport smoothly scrolls to follow focus.**

Traditional tiling window managers try to fit everything on screen at once, which means every new window shrinks everything else. niri-mac flips that idea on its head.

> **Opening a new window never resizes existing ones.**

Instead, columns are added to an infinitely wide virtual canvas. You navigate between them with keyboard shortcuts or trackpad gestures, and the focused column always slides into view — much like **applying a code editor's tab metaphor to window management itself.**

---

## Key Features

### 1. Windows Never Get Crushed

Anyone who has opened a fourth window in a traditional tiling WM knows the pain of everything becoming a thin sliver. That never happens in niri-mac. Each column keeps its own independent width (cycle between 1/3, 1/2, and 2/3 of the screen with `Ctrl+Opt+R`), and new windows simply append to the right.

### 2. Trackpad-Native Scrolling

Hold Ctrl and swipe horizontally to scroll the entire layout. On a MacBook trackpad, the natural momentum scrolling makes this feel silky smooth. You can also use Option+scroll for the same effect.

### 3. Column Pinning

Want your terminal glued to the left side no matter where you scroll? **Pin it.** Press `Ctrl+Opt+P` on any column to lock it to the left edge of the screen. It stays put while everything else scrolls freely — perfect for a terminal, reference doc, or chat window.

### 4. Drag-and-Swap

Drag any window more than 20px and drop it onto another column to instantly swap their positions. No keyboard required.

### 5. Dynamic Workspaces

Switch workspaces with `Ctrl+Opt+Cmd+↓`. Reach the last one and a brand-new workspace is created automatically. Separate projects, contexts, and tasks across as many workspaces as you need.

### 6. Column Stacking and Splitting

Stack multiple windows into one column with `Ctrl+Opt+Return` (merge into left column), or pop a window out of a stack with `Ctrl+Opt+Shift+Return`.

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Ctrl+Opt+← →` | Focus left/right column |
| `Ctrl+Opt+↑ ↓` | Focus window above/below in column |
| `Ctrl+Opt+Shift+← →` | Reorder column left/right |
| `Ctrl+Opt+R` | Cycle column width (1/3 → 1/2 → 2/3) |
| `Ctrl+Opt+P` | Pin/unpin active column |
| `Ctrl+Opt+Return` | Merge window into left column |
| `Ctrl+Opt+Shift+Return` | Expel window from column |
| `Ctrl+Opt+Cmd+↑ ↓` | Switch workspace |
| `Ctrl+Opt+Cmd+Shift+↑ ↓` | Move window to workspace above/below |
| `Ctrl+Opt+- / =` | Shrink/expand active window height |
| `Ctrl+Opt+A` | Toggle Auto-Fit mode |

---

## Installation

### Requirements

- macOS 13 (Ventura) or later
- Swift 5.9 or later
- Accessibility permission
- Input Monitoring permission

### Steps

```bash
git clone https://github.com/FScoward/niri-mac.git
cd niri-mac

# Build the .app bundle
bash make-app.sh

# Launch
open NiriMac.app
```

After first launch, go to **System Settings → Privacy & Security** and grant both **Accessibility** and **Input Monitoring** permissions to NiriMac.app.

---

## Who Should Try This?

- **Developers**: Want your editor, terminal, browser, and Slack always side-by-side without juggling windows
- **Multi-monitor users**: Tired of messy window arrangements on secondary displays
- **Linux migrants**: Used i3, Sway, or niri on Linux and miss tiling on macOS
- **Keyboard power users**: Want to navigate windows at full speed without touching the mouse

---

## Known Limitations

- The macOS Accessibility API is best-effort; some windows (system apps under SIP protection) may refuse repositioning
- Full-screen windows are not managed
- Character-grid terminals like iTerm2 snap their height to row boundaries, so pixel-perfect height alignment is not always possible

---

## Closing Thoughts

niri-mac brings tiling WM productivity to macOS without fighting the platform. Setup takes minutes, no config files needed, and being written in Swift means it runs lean and fast.

Once you experience a world where windows never get crushed, you won't want to go back.

> Give it a try today.
