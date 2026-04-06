import AppKit
import CoreGraphics

/// フォーカスウィンドウの枠線・ディム効果を NSPanel オーバーレイで表示する。
///
/// - borderPanel: フォーカス中ウィンドウ周囲の枠線パネル（1枚）
/// - dimPanel: 画面全体を覆う半透明パネル（1枚）。フォーカス中＋ピン中ウィンドウに穴を開けたマスクで制御。
///
/// WindowManager.applyLayout() の末尾から update(focusedID:allFrames:pinnedWindowIDs:config:) を呼ぶこと。
/// parkedWindowIDs（画面外退避中）のウィンドウはオーバーレイ対象外とする。
final class FocusOverlayManager {

    private var borderPanel: NSPanel?
    private var borderTrackLayer: CAShapeLayer?
    private var borderSpotLayer: CAShapeLayer?

    private var dimPanel: NSPanel?
    private var dimMaskLayer: CAShapeLayer?

    // MARK: - Public API

    func update(
        focusedID: WindowID?,
        allFrames: [(WindowID, CGRect)],
        pinnedWindowIDs: Set<WindowID>,
        config: LayoutConfig
    ) {
        updateBorder(focusedID: focusedID, allFrames: allFrames, config: config)
        updateDim(focusedID: focusedID, allFrames: allFrames, pinnedWindowIDs: pinnedWindowIDs, config: config)
    }

    func removeAll() {
        borderPanel?.orderOut(nil)
        borderPanel = nil
        borderTrackLayer = nil
        borderSpotLayer = nil
        dimPanel?.orderOut(nil)
        dimPanel = nil
        dimMaskLayer = nil
    }

    // MARK: - Quartz → Cocoa 座標変換（static でテスト可能）

    static func quartzToCocoa(_ frame: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.origin.x,
            y: screenHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    // MARK: - Private

    private func updateBorder(
        focusedID: WindowID?,
        allFrames: [(WindowID, CGRect)],
        config: LayoutConfig
    ) {
        guard config.focusBorderEnabled, let fid = focusedID,
              let quartzFrame = allFrames.first(where: { $0.0 == fid })?.1
        else {
            borderPanel?.orderOut(nil)
            return
        }

        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let expanded = quartzFrame.insetBy(dx: -config.focusBorderWidth, dy: -config.focusBorderWidth)
        let cocoaFrame = Self.quartzToCocoa(expanded, screenHeight: screenHeight)

        let panel = borderPanel ?? makeBorderPanel()
        borderPanel = panel
        panel.setFrame(cocoaFrame, display: true)

        if let contentView = panel.contentView {
            let bounds = contentView.bounds
            let inset = config.focusBorderWidth / 2
            let path = CGPath(
                roundedRect: bounds.insetBy(dx: inset, dy: inset),
                cornerWidth: 6, cornerHeight: 6, transform: nil
            )
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            borderTrackLayer?.path = path
            borderTrackLayer?.lineWidth = config.focusBorderWidth
            borderSpotLayer?.path = path
            borderSpotLayer?.lineWidth = config.focusBorderWidth * 3
            CATransaction.commit()
        }

        panel.orderFrontRegardless()
    }

    private func updateDim(
        focusedID: WindowID?,
        allFrames: [(WindowID, CGRect)],
        pinnedWindowIDs: Set<WindowID>,
        config: LayoutConfig
    ) {
        guard config.focusDimEnabled else {
            dimPanel?.orderOut(nil)
            return
        }

        guard let screen = NSScreen.screens.first else { return }
        let screenHeight = screen.frame.height

        let panel = dimPanel ?? makeDimPanel(opacity: config.focusDimOpacity)
        dimPanel = panel
        panel.contentView?.layer?.backgroundColor = NSColor(white: 0, alpha: config.focusDimOpacity).cgColor
        panel.setFrame(screen.frame, display: true)

        // 全画面パス + フォーカス中・ピン中ウィンドウの穴（evenOdd）
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: screen.frame.size))

        if let fid = focusedID,
           let quartzFrame = allFrames.first(where: { $0.0 == fid })?.1 {
            path.addRect(Self.quartzToCocoa(quartzFrame, screenHeight: screenHeight))
        }

        for (wid, quartzFrame) in allFrames where pinnedWindowIDs.contains(wid) {
            path.addRect(Self.quartzToCocoa(quartzFrame, screenHeight: screenHeight))
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dimMaskLayer?.path = path
        CATransaction.commit()

        panel.orderFrontRegardless()
    }

    // MARK: - NSPanel ファクトリ

    private func makeBasePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let view = NSView()
        view.wantsLayer = true
        panel.contentView = view
        return panel
    }

    private func makeBorderPanel() -> NSPanel {
        let panel = makeBasePanel()
        guard let contentView = panel.contentView, let rootLayer = contentView.layer else {
            return panel
        }

        let track = CAShapeLayer()
        track.fillColor = NSColor.clear.cgColor
        track.strokeColor = NSColor.systemOrange.withAlphaComponent(0.3).cgColor
        track.lineWidth = 4.0
        track.lineCap = .round
        rootLayer.addSublayer(track)
        borderTrackLayer = track

        let spot = CAShapeLayer()
        spot.fillColor = NSColor.clear.cgColor
        spot.strokeColor = NSColor.systemOrange.cgColor
        spot.lineWidth = 12.0
        spot.lineCap = .round
        spot.lineDashPattern = [NSNumber(value: 0), NSNumber(value: 1)]
        spot.strokeStart = 0
        spot.strokeEnd = 0.08
        rootLayer.addSublayer(spot)
        borderSpotLayer = spot

        let anim = CABasicAnimation(keyPath: "strokeStart")
        anim.fromValue = 0.0
        anim.toValue = 1.0
        anim.duration = 2.0
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        spot.add(anim, forKey: "travel")

        let anim2 = CABasicAnimation(keyPath: "strokeEnd")
        anim2.fromValue = 0.08
        anim2.toValue = 1.08
        anim2.duration = 2.0
        anim2.repeatCount = .infinity
        anim2.timingFunction = CAMediaTimingFunction(name: .linear)
        spot.add(anim2, forKey: "travelEnd")

        return panel
    }

    private func makeDimPanel(opacity: CGFloat) -> NSPanel {
        let panel = makeBasePanel()

        // マスクレイヤー: evenOdd で穴あき dim を実現
        let mask = CAShapeLayer()
        mask.fillColor = NSColor.white.cgColor
        mask.fillRule = .evenOdd
        panel.contentView?.layer?.mask = mask
        panel.contentView?.layer?.backgroundColor = NSColor(white: 0, alpha: opacity).cgColor
        dimMaskLayer = mask

        return panel
    }
}
