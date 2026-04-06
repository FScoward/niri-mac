import AppKit
import CoreGraphics

/// ドラッグ中のドロップターゲットウィンドウに破線の青枠を重ねて表示する NSPanel オーバーレイ。
/// WindowManager から show(frame:) / hide() を呼ぶことでリアルタイム更新される。
final class DropTargetOverlayManager {

    private var panel: NSPanel?
    private var borderLayer: CAShapeLayer?

    // MARK: - Public API

    /// 指定フレーム（Quartz座標系）に破線枠を表示する
    func show(frame: CGRect) {
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let cocoaFrame = quartzToCocoa(frame, screenHeight: screenHeight)

        let p = panel ?? makePanel()
        panel = p
        p.setFrame(cocoaFrame, display: true)

        if let contentView = p.contentView {
            let bounds = contentView.bounds
            let path = CGPath(
                roundedRect: bounds.insetBy(dx: 2, dy: 2),
                cornerWidth: 6, cornerHeight: 6, transform: nil
            )
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            borderLayer?.path = path
            CATransaction.commit()
        }
        p.orderFrontRegardless()
    }

    /// オーバーレイを非表示にする
    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Quartz → Cocoa 座標変換

    private func quartzToCocoa(_ frame: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.origin.x,
            y: screenHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    // MARK: - NSPanel ファクトリ

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        p.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        p.ignoresMouseEvents = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let view = NSView()
        view.wantsLayer = true
        // 薄い青背景
        view.layer?.backgroundColor = NSColor(red: 0.42, green: 0.48, blue: 1.0, alpha: 0.08).cgColor
        p.contentView = view

        // 破線ボーダー
        let border = CAShapeLayer()
        border.fillColor = NSColor.clear.cgColor
        border.strokeColor = NSColor(red: 0.42, green: 0.48, blue: 1.0, alpha: 1.0).cgColor
        border.lineWidth = 2.0
        border.lineDashPattern = [NSNumber(value: 6), NSNumber(value: 4)]
        view.layer?.addSublayer(border)
        borderLayer = border

        return p
    }
}
