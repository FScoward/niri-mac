import AppKit
import CoreGraphics

/// ドロップゾーンの種類。形状・破線パターン・色を決定する。
enum DropZone {
    case stackAbove   // ターゲット上部にスタック
    case swap         // スワップ（差し込む）
    case stackBelow   // ターゲット下部にスタック
}

/// ドラッグ中のドロップターゲットウィンドウに 3 分割ゾーン可視化オーバーレイを表示する NSPanel。
/// WindowManager から show(frame:zone:) / hide() / showGhost(frame:) を呼ぶことでリアルタイム更新される。
final class DropTargetOverlayManager {

    private var panel: NSPanel?

    // ゾーン背景レイヤー
    private var topZoneLayer: CALayer?
    private var midZoneLayer: CALayer?
    private var botZoneLayer: CALayer?

    // 区切り線レイヤー
    private var topDivider: CALayer?
    private var botDivider: CALayer?

    // ゾーンラベルレイヤー
    private var topLabel: CATextLayer?
    private var midLabel: CATextLayer?
    private var botLabel: CATextLayer?

    // 外周枠線
    private var borderLayer: CAShapeLayer?

    // MARK: - カラーパレット

    private static let colorStackBlue = NSColor(red: 107/255, green: 123/255, blue: 1.0, alpha: 1.0).cgColor
    private static let colorStackBlueFill = NSColor(red: 107/255, green: 123/255, blue: 1.0, alpha: 0.30).cgColor
    private static let colorSwapYellow = NSColor(red: 1.0, green: 200/255, blue: 0.0, alpha: 1.0).cgColor
    private static let colorSwapYellowFill = NSColor(red: 1.0, green: 200/255, blue: 0.0, alpha: 0.28).cgColor
    private static let colorDimFill = NSColor(white: 1.0, alpha: 0.04).cgColor
    private static let colorDivider = NSColor(white: 1.0, alpha: 0.18).cgColor

    // MARK: - Public API

    /// 指定フレーム（Quartz座標系）にゾーン対応の 3 分割オーバーレイを表示する。
    func show(frame: CGRect, zone: DropZone = .swap) {
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let cocoaFrame = quartzToCocoa(frame, screenHeight: screenHeight)

        let p = panel ?? makePanel()
        panel = p
        p.setFrame(cocoaFrame, display: false)

        guard let contentView = p.contentView else {
            p.orderFrontRegardless()
            return
        }

        let bounds = contentView.bounds
        let h = bounds.height
        let w = bounds.width
        let zoneH = h / 3

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // ゾーンレイヤーを表示
        topZoneLayer?.isHidden = false
        midZoneLayer?.isHidden = false
        botZoneLayer?.isHidden = false
        topDivider?.isHidden = false
        botDivider?.isHidden = false
        topLabel?.isHidden = false
        midLabel?.isHidden = false
        botLabel?.isHidden = false

        // 各ゾーンの高さと位置（CALayer は下が origin）
        let topFrame = CGRect(x: 0, y: h - zoneH, width: w, height: zoneH)
        let midFrame = CGRect(x: 0, y: zoneH, width: w, height: zoneH)
        let botFrame = CGRect(x: 0, y: 0, width: w, height: zoneH)

        topZoneLayer?.frame = topFrame
        midZoneLayer?.frame = midFrame
        botZoneLayer?.frame = botFrame

        // 区切り線（高さ1px）
        topDivider?.frame = CGRect(x: 0, y: h - zoneH, width: w, height: 1)
        botDivider?.frame = CGRect(x: 0, y: zoneH, width: w, height: 1)

        // ゾーン色設定
        let (activeStroke, activeFill) = zoneHighlightColors(zone)
        let dimFill = Self.colorDimFill

        switch zone {
        case .stackAbove:
            topZoneLayer?.backgroundColor = activeFill
            midZoneLayer?.backgroundColor = dimFill
            botZoneLayer?.backgroundColor = dimFill
        case .swap:
            topZoneLayer?.backgroundColor = dimFill
            midZoneLayer?.backgroundColor = activeFill
            botZoneLayer?.backgroundColor = dimFill
        case .stackBelow:
            topZoneLayer?.backgroundColor = dimFill
            midZoneLayer?.backgroundColor = dimFill
            botZoneLayer?.backgroundColor = activeFill
        }

        // ラベル配置（各ゾーン中央）
        let labelH: CGFloat = 22
        let labelW = w - 32
        topLabel?.frame = CGRect(x: 16, y: topFrame.midY - labelH / 2, width: labelW, height: labelH)
        midLabel?.frame = CGRect(x: 16, y: midFrame.midY - labelH / 2, width: labelW, height: labelH)
        botLabel?.frame = CGRect(x: 16, y: botFrame.midY - labelH / 2, width: labelW, height: labelH)

        // ラベル色
        let activeTextColor = activeStroke
        let dimTextColor = NSColor(white: 0.65, alpha: 0.9).cgColor
        switch zone {
        case .stackAbove:
            topLabel?.foregroundColor = activeTextColor
            midLabel?.foregroundColor = dimTextColor
            botLabel?.foregroundColor = dimTextColor
        case .swap:
            topLabel?.foregroundColor = dimTextColor
            midLabel?.foregroundColor = activeTextColor
            botLabel?.foregroundColor = dimTextColor
        case .stackBelow:
            topLabel?.foregroundColor = dimTextColor
            midLabel?.foregroundColor = dimTextColor
            botLabel?.foregroundColor = activeTextColor
        }

        // 外周枠線（細め）
        let path = CGPath(
            roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5),
            cornerWidth: 5, cornerHeight: 5, transform: nil
        )
        borderLayer?.path = path
        borderLayer?.strokeColor = activeStroke
        borderLayer?.lineWidth = 1.5
        borderLayer?.lineDashPattern = [NSNumber(value: 6), NSNumber(value: 4)]

        CATransaction.commit()
        p.orderFrontRegardless()
    }

    /// オーバーレイを非表示にする
    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - ゾーン別ハイライトカラー

    private func zoneHighlightColors(_ zone: DropZone) -> (CGColor, CGColor) {
        switch zone {
        case .stackAbove, .stackBelow:
            return (Self.colorStackBlue, Self.colorStackBlueFill)
        case .swap:
            return (Self.colorSwapYellow, Self.colorSwapYellowFill)
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

        guard let rootLayer = view.layer else { return p }

        // ---- ゾーン背景レイヤー ----
        let makeZone: () -> CALayer = {
            let l = CALayer()
            l.backgroundColor = NSColor.clear.cgColor
            rootLayer.addSublayer(l)
            return l
        }
        topZoneLayer = makeZone()
        midZoneLayer = makeZone()
        botZoneLayer = makeZone()

        // ---- 区切り線 ----
        let makeDivider: () -> CALayer = {
            let l = CALayer()
            l.backgroundColor = Self.colorDivider
            rootLayer.addSublayer(l)
            return l
        }
        topDivider = makeDivider()
        botDivider = makeDivider()

        // ---- ゾーンラベル ----
        let makeLabel: (String) -> CATextLayer = { text in
            let t = CATextLayer()
            t.string = text
            t.fontSize = 13
            t.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            t.foregroundColor = NSColor.white.cgColor
            t.alignmentMode = .center
            t.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            t.isWrapped = false
            rootLayer.addSublayer(t)
            return t
        }
        topLabel = makeLabel("▲  上にスタック")
        midLabel = makeLabel("⇄  差し込む")
        botLabel = makeLabel("▼  下にスタック")

        // ---- 外周枠線 ----
        let border = CAShapeLayer()
        border.fillColor = NSColor.clear.cgColor
        border.strokeColor = Self.colorStackBlue
        border.lineWidth = 1.5
        border.lineDashPattern = [NSNumber(value: 6), NSNumber(value: 4)]
        rootLayer.addSublayer(border)
        borderLayer = border

        return p
    }
}
