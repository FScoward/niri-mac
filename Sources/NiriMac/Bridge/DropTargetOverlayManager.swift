import AppKit
import CoreGraphics

/// ドロップゾーンの種類。形状・破線パターン・色を決定する。
enum DropZone {
    case stackAbove   // 短点線・上帯: ターゲットの上にスタック
    case swap         // 短点線・中帯: スワップ（現状維持）
    case stackBelow   // 短点線・下帯: ターゲットの下にスタック
    case expel        // 長破線・全高: 解除モード
    case ghostColumn  // 長破線・全高縦帯: 横ドラッグ挿入プレビュー
}

/// ドラッグ中のドロップターゲットウィンドウに形状と破線パターンで区別したオーバーレイを表示する NSPanel。
/// WindowManager から show(frame:zone:) / hide() を呼ぶことでリアルタイム更新される。
final class DropTargetOverlayManager {

    private var panel: NSPanel?
    private var borderLayer: CAShapeLayer?

    // MARK: - Public API

    /// 指定フレーム（Quartz座標系）にゾーン対応のオーバーレイを表示する。
    /// スタックゾーンは帯に、ゴースト/expel は全高表示になる。
    func show(frame: CGRect, zone: DropZone = .swap) {
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let displayFrame = zoneFrame(frame, zone: zone)
        let cocoaFrame = quartzToCocoa(displayFrame, screenHeight: screenHeight)

        let p = panel ?? makePanel()
        panel = p
        p.setFrame(cocoaFrame, display: true)

        let (strokeColor, bgColor) = zoneColors(zone)
        let dashPattern = zoneDashPattern(zone)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        borderLayer?.strokeColor = strokeColor
        borderLayer?.lineDashPattern = dashPattern
        if let contentView = p.contentView {
            contentView.layer?.backgroundColor = bgColor
            let bounds = contentView.bounds
            let path = CGPath(
                roundedRect: bounds.insetBy(dx: 2, dy: 2),
                cornerWidth: 4, cornerHeight: 4, transform: nil
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

    /// 横ドラッグ中のゴーストカラム挿入位置を長破線で表示する（Quartz座標系）
    func showGhost(frame: CGRect) {
        show(frame: frame, zone: .ghostColumn)
    }

    // MARK: - ゾーン別表示フレーム計算

    /// ゾーンに応じた表示フレームを返す（Quartz座標系）。
    /// stackAbove/swap/stackBelow は帯として表示し、ghost/expel は元フレームのまま。
    private func zoneFrame(_ frame: CGRect, zone: DropZone) -> CGRect {
        let bandHeight: CGFloat = max(min(frame.height * 0.18, 44), 20)
        switch zone {
        case .stackAbove:
            // Quartz: minY = 視覚上端 → 上帯は minY 側
            return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: bandHeight)
        case .stackBelow:
            // 下帯は maxY 側
            return CGRect(x: frame.minX, y: frame.maxY - bandHeight, width: frame.width, height: bandHeight)
        case .swap:
            // 中央帯
            let midY = frame.midY - bandHeight / 2
            return CGRect(x: frame.minX, y: midY, width: frame.width, height: bandHeight)
        case .ghostColumn, .expel:
            return frame
        }
    }

    // MARK: - ゾーン別破線パターン

    /// ゴースト/expel: 長破線 [--- ---]、スタック/スワップ: 短点線 [. . . .]
    private func zoneDashPattern(_ zone: DropZone) -> [NSNumber] {
        switch zone {
        case .ghostColumn, .expel:
            return [NSNumber(value: 12), NSNumber(value: 5)]
        case .stackAbove, .stackBelow, .swap:
            return [NSNumber(value: 4), NSNumber(value: 4)]
        }
    }

    // MARK: - ゾーン別カラー

    private func zoneColors(_ zone: DropZone) -> (CGColor, CGColor) {
        switch zone {
        case .stackAbove, .stackBelow:
            return (
                NSColor(red: 0.42, green: 0.48, blue: 1.0, alpha: 1.0).cgColor,
                NSColor(red: 0.42, green: 0.48, blue: 1.0, alpha: 0.15).cgColor
            )
        case .swap:
            return (
                NSColor(red: 1.0, green: 0.78, blue: 0.0, alpha: 1.0).cgColor,
                NSColor(red: 1.0, green: 0.78, blue: 0.0, alpha: 0.12).cgColor
            )
        case .expel:
            return (
                NSColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1.0).cgColor,
                NSColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 0.08).cgColor
            )
        case .ghostColumn:
            return (
                NSColor(red: 1.0, green: 0.62, blue: 0.25, alpha: 1.0).cgColor,
                NSColor(red: 1.0, green: 0.62, blue: 0.25, alpha: 0.12).cgColor
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
        view.layer?.backgroundColor = NSColor.clear.cgColor
        p.contentView = view

        let border = CAShapeLayer()
        border.fillColor = NSColor.clear.cgColor
        border.strokeColor = NSColor(red: 0.42, green: 0.48, blue: 1.0, alpha: 1.0).cgColor
        border.lineWidth = 2.5
        border.lineDashPattern = [NSNumber(value: 4), NSNumber(value: 4)]
        view.layer?.addSublayer(border)
        borderLayer = border

        return p
    }
}
