import AppKit
import CoreGraphics
import Foundation

private let mouseLogURL = URL(fileURLWithPath: "/tmp/niri-mac.log")
private func mouseLog(_ message: String) {
    let line = message + "\n"
    print(line, terminator: "")
    if let data = line.data(using: .utf8),
       let fh = try? FileHandle(forWritingTo: mouseLogURL) {
        fh.seekToEndOfFile()
        fh.write(data)
        try? fh.close()
    }
}

/// マウス・トラックパッドイベントの管理。
/// CGEventTap でクリック・スクロールを捕捉し、コールバックで上位に通知する。
final class MouseEventManager {

    /// 左クリック時のスクリーン座標（Quartz座標系）
    var onMouseDown: ((CGPoint) -> Void)?

    /// 左ボタンリリース時のスクリーン座標（Quartz座標系）
    var onMouseUp: ((CGPoint) -> Void)?

    /// スクロール時: 水平デルタ（正=右方向）、垂直デルタ（正=下方向）、isContinuous、修飾キー
    var onScroll: ((CGFloat, CGFloat, Bool, NSEvent.ModifierFlags) -> Void)?

    /// ドラッグ中のカーソル位置（Quartz座標系）。~60fps でスロットリングされる
    var onMouseDragged: ((CGPoint) -> Void)?

    /// スロットリング: 前回 onMouseDragged を呼んだ時刻
    private var lastDragDispatch: CFAbsoluteTime = 0
    private let dragDispatchInterval: CFAbsoluteTime = 1.0 / 60.0  // ~16ms

    /// Cmd+Tab 等でアプリが切り替わった時
    var onAppActivated: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var appSwitchObserver: Any?

    func start() {
        startCGEventTap()
        observeAppSwitch()
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil

        if let obs = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        appSwitchObserver = nil
    }

    // MARK: - CGEventTap

    private func startCGEventTap() {
        let mask = CGEventMask(
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let mgr = Unmanaged<MouseEventManager>.fromOpaque(refcon).takeUnretainedValue()
                mgr.handleCGEvent(type: type, event: event)
                return Unmanaged.passRetained(event)
            },
            userInfo: selfPtr
        ) else {
            print("[niri-mac] ⚠️ MouseEventManager: CGEventTap 作成失敗（Accessibility権限を確認）")
            return
        }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = src
        print("[niri-mac] ✅ MouseEventManager: CGEventTap 有効")
    }

    private func handleCGEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .leftMouseDown:
            let loc = event.location
            // CGEvent.location は Quartz座標（左上原点）なのでそのまま渡す
            DispatchQueue.main.async { [weak self] in
                self?.onMouseDown?(loc)
            }

        case .leftMouseUp:
            let loc = event.location
            DispatchQueue.main.async { [weak self] in
                self?.onMouseUp?(loc)
            }

        case .leftMouseDragged:
            let now = CFAbsoluteTimeGetCurrent()
            guard now - lastDragDispatch >= dragDispatchInterval else { return }
            lastDragDispatch = now
            let loc = event.location
            DispatchQueue.main.async { [weak self] in
                self?.onMouseDragged?(loc)
            }

        case .scrollWheel:
            let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            // トラックパッド(continuous)はPointDelta、物理ホイール(non-continuous)はDeltaを使う
            let deltaX: Double
            let deltaY: Double
            if isContinuous {
                deltaX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
                deltaY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            } else {
                deltaX = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
                deltaY = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            }
            mouseLog("[scroll] isContinuous=\(isContinuous) deltaX=\(String(format: "%.3f", deltaX)) deltaY=\(String(format: "%.3f", deltaY))")
            guard abs(deltaX) > 0.01 || abs(deltaY) > 0.01 else { return }

            // 修飾キーを取得
            let cgFlags = event.flags
            var flags: NSEvent.ModifierFlags = []
            if cgFlags.contains(.maskCommand)   { flags.insert(.command) }
            if cgFlags.contains(.maskAlternate) { flags.insert(.option) }
            if cgFlags.contains(.maskShift)     { flags.insert(.shift) }
            if cgFlags.contains(.maskControl)   { flags.insert(.control) }

            DispatchQueue.main.async { [weak self] in
                self?.onScroll?(CGFloat(deltaX), CGFloat(deltaY), isContinuous, flags)
            }

        default:
            break
        }
    }

    // MARK: - アプリ切り替え監視

    private func observeAppSwitch() {
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onAppActivated?()
        }
    }
}
