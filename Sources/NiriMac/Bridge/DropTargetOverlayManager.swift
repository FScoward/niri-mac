import AppKit
import CoreGraphics

/// ドロップゾーンの種類。色と動作を決定する。
enum DropZone {
    case stackAbove   // 青破線: ターゲットの上にスタック
    case swap         // 黄破線: スワップ（現状維持）
    case stackBelow   // 青破線: ターゲットの下にスタック
    case expel        // 赤破線: 解除モード
}

/// ドラッグ中のドロップターゲットウィンドウに破線の色枠を重ねて表示する NSPanel オーバーレイ。
/// WindowManager から show(frame:zone:) / hide() を呼ぶことでリアルタイム更新される。
final class DropTargetOverlayManager {

    private var panel: NSPanel?
    private var borderLayer: CAShapeLayer?

    // MARK: - Public API

    /// 指定フレーム（Quartz座標系）にゾーン対応の破線枠を表示する
    func show(frame: CGRect, zone: DropZone = .swap) {
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let cocoaFrame = quartzToCocoa(frame, screenHeight: screenHeight)

        let p = panel ?? makePanel()
        panel = p
        p.setFrame(cocoaFrame, display: true)

        let (strokeColor, bgColor) = zoneColors(zone)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        borderLayer?.strokeColor = strokeColor
        if let contentView = p.contentView {
            contentView.layer?.backgroundColor = bgColor
            let bounds = contentView.bounds
            let path = CGPath(
                roundedRect: bounds.insetBy(dx: 2, dy: 2),
                cornerWidth: 6, cornerHeight: 6, transform: nil
            )
            borderLayer?.path = path
        }
        CATransaction.commit()
        p.orderFrontRegardless()
    }

    /// オーバーレイを非表示にする
    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - ゾーン別スタイル

    private func zoneColors(_ zone: DropZone) -> (CGColor, CGColor) {
        switch zone {
        case .stackAbove, .stackBelow:
            return (
                NSColor(red: 0.42, green: 0.48, blue: 1.0, alpha: 1.0).cgColor,
                NSColor(red: 0.42, green: 0.48, blue: 1.0, alpha: 0.08).cgColor
            )
        case .swap:
            return (
                NSColor(red: 1.0, green: 0.78, blue: 0.0, alpha: 1.0).cgColor,
                NSColor(red: 1.0, green: 0.78, blue: 0.0, alpha: 0.05).cgColor
            )
        case .expel:
            return (
                NSColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1.0).cgColor,
                NSColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 0.08).cgColor
            )
        }
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
        view.layer?.backgroundColor = NSColor(red: 0.42, green: 0.48, blue: 1.0, alpha: 0.08).cgColor
        p.contentView = view

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
