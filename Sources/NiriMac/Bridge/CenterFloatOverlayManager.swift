import AppKit
import CoreGraphics

/// センターフロート中のウィンドウに backdrop dim + glow border を重ねて表示する NSPanel ペア。
/// WindowManager.applyLayout() から show(centeredFrame:) / hide() を呼ぶこと。
final class CenterFloatOverlayManager {

    private var dimPanel: NSPanel?
    private var dimMaskLayer: CAShapeLayer?

    private var borderPanel: NSPanel?
    private var borderLayer: CAShapeLayer?

    private var isVisible = false

    // MARK: - Public API

    func show(centeredFrame: CGRect) {
        guard let screen = NSScreen.screens.first else { return }
        let screenH = screen.frame.height
        let cocoaFrame = quartzToCocoa(centeredFrame, screenHeight: screenH)

        updateDim(screen: screen, cocoaFrame: cocoaFrame)
        updateBorder(centeredFrame: centeredFrame, screenH: screenH)
        isVisible = true
    }

    func hide() {
        guard isVisible else { return }
        dimPanel?.orderOut(nil)
        borderPanel?.orderOut(nil)
        isVisible = false
    }

    func removeAll() {
        dimPanel?.orderOut(nil);   dimPanel = nil;   dimMaskLayer = nil
        borderPanel?.orderOut(nil); borderPanel = nil; borderLayer = nil
        isVisible = false
    }

    // MARK: - Private

    private func updateDim(screen: NSScreen, cocoaFrame: CGRect) {
        let dim = dimPanel ?? makeDimPanel()
        dimPanel = dim
        dim.setFrame(screen.frame, display: true)

        // evenOdd マスク: 全画面を暗くしつつフロートウィンドウ部分に穴を開ける
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: screen.frame.size))
        let hole = cocoaFrame.insetBy(dx: -8, dy: -8)
        path.addRoundedRect(in: hole, cornerWidth: 14, cornerHeight: 14)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dimMaskLayer?.path = path
        CATransaction.commit()

        dim.orderFrontRegardless()
    }

    private func updateBorder(centeredFrame: CGRect, screenH: CGFloat) {
        let expand: CGFloat = 6
        let expandedQuartz = centeredFrame.insetBy(dx: -expand, dy: -expand)
        let expandedCocoa = quartzToCocoa(expandedQuartz, screenHeight: screenH)

        let border = borderPanel ?? makeBorderPanel()
        borderPanel = border
        border.setFrame(expandedCocoa, display: true)

        if let cv = border.contentView {
            let path = CGPath(
                roundedRect: cv.bounds.insetBy(dx: 2, dy: 2),
                cornerWidth: 14, cornerHeight: 14, transform: nil
            )
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            borderLayer?.path = path
            CATransaction.commit()
        }

        border.orderFrontRegardless()
    }

    // MARK: - Quartz → Cocoa

    private func quartzToCocoa(_ frame: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.origin.x,
            y: screenHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    // MARK: - NSPanel ファクトリ

    private func makeBasePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        p.ignoresMouseEvents = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let view = NSView()
        view.wantsLayer = true
        p.contentView = view
        return p
    }

    private func makeDimPanel() -> NSPanel {
        let p = makeBasePanel()
        p.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        let mask = CAShapeLayer()
        mask.fillColor = NSColor.white.cgColor
        mask.fillRule = .evenOdd
        p.contentView?.layer?.mask = mask
        p.contentView?.layer?.backgroundColor = NSColor(white: 0, alpha: 0.55).cgColor
        dimMaskLayer = mask
        return p
    }

    private func makeBorderPanel() -> NSPanel {
        let p = makeBasePanel()
        p.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3)
        guard let cv = p.contentView, let root = cv.layer else { return p }

        let b = CAShapeLayer()
        b.fillColor = NSColor.clear.cgColor
        b.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
        b.lineWidth = 1.5
        b.shadowColor = NSColor.white.cgColor
        b.shadowOpacity = 1.0
        b.shadowRadius = 12.0
        b.shadowOffset = .zero
        root.addSublayer(b)
        borderLayer = b
        return p
    }
}
