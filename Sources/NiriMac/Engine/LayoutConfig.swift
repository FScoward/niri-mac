import AppKit
import CoreGraphics

struct LayoutConfig {
    /// カラム間のギャップ
    var gapWidth: CGFloat = 16

    /// カラム内ウィンドウ間のギャップ
    var gapHeight: CGFloat = 16

    /// 新規ウィンドウのデフォルトカラム幅
    var defaultColumnWidthFraction: CGFloat = 1.0 / 3.0

    /// ウィンドウアニメーション時間（秒）
    var animationDuration: CFTimeInterval = 0.25

    /// メニューバーの高さ（デフォルト）
    var menuBarHeight: CGFloat = 24

    /// キーボードフォーカス移動時にマウスカーソルをウィンドウ中央にワープするか
    var warpMouseToFocus: Bool = true

    /// トラックパッド水平スクロールの感度（1.0=等倍）
    var scrollSensitivity: CGFloat = 0.5

    /// マウスホイール（非トラックパッド）のスクロール感度
    var mouseWheelScrollSensitivity: CGFloat = 20.0

    /// Option + スクロールによるレイアウトスクロールの感度
    var optionScrollSensitivity: CGFloat = 0.3

    func defaultColumnWidth(for screenWidth: CGFloat) -> CGFloat {
        return screenWidth * defaultColumnWidthFraction
    }

    // MARK: - Focus Highlight

    /// フォーカス枠線の表示有無
    var focusBorderEnabled: Bool = false

    /// 枠線の色（デフォルト: システムブルー）
    var focusBorderColor: CGColor = NSColor.systemBlue.cgColor

    /// 枠線の幅（px）
    var focusBorderWidth: CGFloat = 4.0

    /// 非フォーカスウィンドウのディム表示有無
    var focusDimEnabled: Bool = false

    /// ディムの不透明度（0.0〜1.0）
    var focusDimOpacity: CGFloat = 0.4

    // MARK: - App Exclusion

    /// タイリングから除外するアプリの bundleID セット
    var excludedBundleIDs: Set<String> = []

    // MARK: - Auto-Fit

    /// Auto-Fit レイアウトを有効にするか。
    /// 非pinnedカラム数が 1〜3 のとき、スクロールせず画面を等分/中央配置する。
    var autoFitEnabled: Bool = true

    /// Auto-Fit で 1 カラム時のセンタリング幅（作業領域実効幅に対する比率）
    var autoFitCenterWidthFraction: CGFloat = 2.0 / 3.0
}
