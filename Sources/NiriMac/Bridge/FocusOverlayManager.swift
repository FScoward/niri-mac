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
    private var dimPanels: [WindowID: NSPanel] = [:]

    // MARK: - Public API

    func update(
        focusedID: WindowID?,
        allFrames: [(WindowID, CGRect)],
        config: LayoutConfig
    ) {
        updateBorder(focusedID: focusedID, allFrames: allFrames, config: config)
        updateDim(focusedID: focusedID, allFrames: allFrames, config: config)
    }

    func removeAll() {
        borderPanel?.orderOut(nil)
        borderPanel = nil
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

        if let layer = panel.contentView?.layer {
            layer.borderColor = config.focusBorderColor
            layer.borderWidth = config.focusBorderWidth
            layer.cornerRadius = 6
        }

        panel.setFrame(cocoaFrame, display: true)
        panel.orderFront(nil)
    }

    private func updateDim(
        focusedID: WindowID?,
        allFrames: [(WindowID, CGRect)],
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

            let cocoaFrame = Self.quartzToCocoa(quartzFrame, screenHeight: screenHeight)
            let panel = dimPanels[wid] ?? makeDimPanel(opacity: config.focusDimOpacity)
            dimPanels[wid] = panel

            panel.backgroundColor = NSColor(white: 0, alpha: config.focusDimOpacity)
            panel.setFrame(cocoaFrame, display: true)
            panel.orderFront(nil)
        }

        if let fid = focusedID {
            dimPanels[fid]?.orderOut(nil)
        }
    }

    // MARK: - NSPanel ファクトリ

    private func makeBasePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView?.wantsLayer = true
        return panel
    }

    private func makeBorderPanel() -> NSPanel {
        makeBasePanel()
    }

    private func makeDimPanel(opacity: CGFloat) -> NSPanel {
        let panel = makeBasePanel()
        panel.backgroundColor = NSColor(white: 0, alpha: opacity)
        return panel
    }
}
