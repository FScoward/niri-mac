import CoreGraphics

struct LayoutConfig {
    /// カラム間のギャップ
    var gapWidth: CGFloat = 16

    /// カラム内ウィンドウ間のギャップ
    var gapHeight: CGFloat = 8

    /// 新規ウィンドウのデフォルトカラム幅
    var defaultColumnWidthFraction: CGFloat = 0.5

    /// ウィンドウアニメーション時間（秒）
    var animationDuration: CFTimeInterval = 0.2

    /// メニューバーの高さ（デフォルト）
    var menuBarHeight: CGFloat = 24

    /// キーボードフォーカス移動時にマウスカーソルをウィンドウ中央にワープするか
    var warpMouseToFocus: Bool = true

    /// トラックパッド水平スクロールの感度（1.0=等倍）
    var scrollSensitivity: CGFloat = 0.5

    /// マウスホイール（非トラックパッド）のスクロール感度
    var mouseWheelScrollSensitivity: CGFloat = 20.0

    func defaultColumnWidth(for screenWidth: CGFloat) -> CGFloat {
        return screenWidth * defaultColumnWidthFraction
    }
}
