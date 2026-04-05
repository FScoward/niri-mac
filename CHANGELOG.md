# Changelog

## [v0.1.0-beta] - 2026-04-05

### Features

- **Improved height maximization for new windows** / **新規ウィンドウ開封時の高さ最大化を改善**: Improved auto-expand logic when opening new windows
- **Pin/Unpin Column in menu bar** / **メニューバーに Pin/Unpin Column を追加**: Column pin operations now available from the menu bar
- **Column pin feature** / **カラムpin機能を追加**: Pin a column to fix its scroll position with `Ctrl+Opt+P`
- **Column width change via AX window resize detection** / **AXウィンドウリサイズ検知によるカラム幅変更**: Column width automatically adjusts when resizing a window
- **Inter-column window swap via native drag** / **ネイティブドラッグによるカラム間ウィンドウスワップ**: Drag windows between columns to swap them

### Bug Fixes

- **Fixed window close handling** / **ウィンドウ閉じ時の処理を修正**: Focus priority (prefer right), gap cleanup, AXObserver improvements
- **Scroll design aligned with upstream niri** / **スクロール設計を本家niriに準拠した方式に変更**: Redesigned scroll behavior to match upstream niri spec
- **Fixed scroll animation stuttering** / **スクロールアニメーションのカクつきを修正**: Smoother scroll animations
- **Fixed scroll direction** / **スクロール方向を修正**: Corrected scroll direction
- **Fixed menu bar pin target column offset** / **メニューバーpinのターゲットカラムズレを修正**: Fixed column selection logic for pin operations
- **Added cooldown to prevent reverse-swap false detection** / **スワップ後の逆スワップ誤検知を防ぐクールダウンを追加**: Prevents accidental reverse swap after drag

### Documentation

- Updated README: added English version and reflected latest features / README更新: 英語版追加・最新機能を反映

---

On first launch, grant **Accessibility** and **Input Monitoring** permissions in System Settings.  
初回起動時は **アクセシビリティ** と **入力監視** の権限を付与してください。  
See README for details / 詳細は README をご覧ください。
