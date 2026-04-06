import AppKit
import CoreGraphics

/// フォーカスウィンドウの枠線・ディム効果を NSPanel オーバーレイで表示する。
///
/// - borderPanel: フォーカス中ウィンドウ周囲の枠線パネル（1枚）
/// - dimPanels: 非フォーカスウィンドウごとの半透明オーバーレイ（WindowID → NSPanel）
///
/// WindowManager.applyLayout() の末尾から update(focusedID:allFrames:config:) を呼ぶこと。
/// parkedWindowIDs（画面外退避中）のウィンドウはオーバーレイ対象外とする。
final class FocusOverlayManager {

    private var borderPanel: NSPanel?
    private var borderTrackLayer: CAShapeLayer?  // 枠線ベース（薄いオレンジ）
    private var borderSpotLayer: CAShapeLayer?   // 走る光
    private var dimPanels: [WindowID: NSPanel] = [:]

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
        dimPanels.values.forEach { $0.orderOut(nil) }
        dimPanels.removeAll()
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

        // 枠線パスを新しい bounds に更新（アニメーションなし）
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
        let currentIDs = Set(allFrames.map { $0.0 })
        let obsolete = dimPanels.keys.filter { !currentIDs.contains($0) }
        obsolete.forEach {
            dimPanels[$0]?.orderOut(nil)
            dimPanels.removeValue(forKey: $0)
        }

        guard config.focusDimEnabled else {
            dimPanels.values.forEach { $0.orderOut(nil) }
            return
        }

        let screenHeight = NSScreen.screens.first?.frame.height ?? 0

        for (wid, quartzFrame) in allFrames {
            if wid == focusedID { continue }
            if pinnedWindowIDs.contains(wid) {
                dimPanels[wid]?.orderOut(nil)
                continue
            }

            let cocoaFrame = Self.quartzToCocoa(quartzFrame, screenHeight: screenHeight)
            let panel = dimPanels[wid] ?? makeDimPanel(opacity: config.focusDimOpacity)
            dimPanels[wid] = panel

            panel.backgroundColor = NSColor(white: 0, alpha: config.focusDimOpacity)
            panel.setFrame(cocoaFrame, display: true)
            panel.orderFrontRegardless()
        }

        if let fid = focusedID {
            dimPanels[fid]?.orderOut(nil)
        }
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

        // ベース枠線: 薄いオレンジで常時表示
        let track = CAShapeLayer()
        track.fillColor = NSColor.clear.cgColor
        track.strokeColor = NSColor.systemOrange.withAlphaComponent(0.3).cgColor
        track.lineWidth = 4.0
        track.lineCap = .round
        rootLayer.addSublayer(track)
        borderTrackLayer = track

        // 走る光: 短いダッシュが枠線を周回する
        let spot = CAShapeLayer()
        spot.fillColor = NSColor.clear.cgColor
        spot.strokeColor = NSColor.systemOrange.cgColor
        spot.lineWidth = 12.0
        spot.lineCap = .round
        // 全体の 8% だけ表示し残りは透明にすることで「光の粒」を表現
        spot.lineDashPattern = [NSNumber(value: 0), NSNumber(value: 1)]
        spot.strokeStart = 0
        spot.strokeEnd = 0.08
        rootLayer.addSublayer(spot)
        borderSpotLayer = spot

        // strokeStart/End を 0→1 に繰り返すことで枠線を一周させる
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
        panel.backgroundColor = NSColor(white: 0, alpha: opacity)
        return panel
    }
}
