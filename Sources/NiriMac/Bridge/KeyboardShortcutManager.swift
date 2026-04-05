import AppKit
import CoreGraphics
import IOKit.hid
import Foundation

private let kbLogURL = URL(fileURLWithPath: "/tmp/niri-mac.log")
private func kbLog(_ message: String) {
    let line = message + "\n"
    print(line, terminator: "")
    if let data = line.data(using: .utf8),
       let fh = try? FileHandle(forWritingTo: kbLogURL) {
        fh.seekToEndOfFile()
        fh.write(data)
        try? fh.close()
    }
}

/// グローバルキーボードショートカット。
/// CGEventTap (低レベル) を優先し、失敗時は NSEvent global monitor にフォールバック。
final class KeyboardShortcutManager {

    enum Action {
        case focusLeft, focusRight, focusUp, focusDown
        case moveColumnLeft, moveColumnRight
        case moveWindowToWorkspaceUp, moveWindowToWorkspaceDown
        case switchWorkspaceUp, switchWorkspaceDown
        case consumeIntoColumnLeft, consumeIntoColumnRight
        case expelFromColumn
        case cycleColumnWidth
        case togglePin
        case quit
    }

    struct Binding {
        let modifiers: NSEvent.ModifierFlags
        let keyCode: UInt16
        let action: Action
    }

    var onAction: ((Action) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    // キーコード定数
    private static let kLeft:   UInt16 = 123
    private static let kRight:  UInt16 = 124
    private static let kUp:     UInt16 = 126
    private static let kDown:   UInt16 = 125
    private static let kReturn: UInt16 = 36
    private static let kQ:      UInt16 = 12

    private let bindings: [Binding] = [
        // カラム間フォーカス (Ctrl+Opt+Arrow: iTerm2/macOS両方と競合しにくい)
        Binding(modifiers: [.control, .option], keyCode: 123, action: .focusLeft),
        Binding(modifiers: [.control, .option], keyCode: 124, action: .focusRight),
        // カラム内ウィンドウ
        Binding(modifiers: [.control, .option], keyCode: 126, action: .focusUp),
        Binding(modifiers: [.control, .option], keyCode: 125, action: .focusDown),
        // カラム並べ替え
        Binding(modifiers: [.control, .option, .shift], keyCode: 123, action: .moveColumnLeft),
        Binding(modifiers: [.control, .option, .shift], keyCode: 124, action: .moveColumnRight),
        // ワークスペース切り替え
        Binding(modifiers: [.control, .option, .command], keyCode: 126, action: .switchWorkspaceUp),
        Binding(modifiers: [.control, .option, .command], keyCode: 125, action: .switchWorkspaceDown),
        // ウィンドウをワークスペース移動
        Binding(modifiers: [.control, .option, .command, .shift], keyCode: 126, action: .moveWindowToWorkspaceUp),
        Binding(modifiers: [.control, .option, .command, .shift], keyCode: 125, action: .moveWindowToWorkspaceDown),
        // カラム操作
        Binding(modifiers: [.control, .option], keyCode: 36, action: .consumeIntoColumnLeft),
        Binding(modifiers: [.control, .option, .shift], keyCode: 36, action: .expelFromColumn),
        // カラム幅サイクル
        Binding(modifiers: [.control, .option], keyCode: 15, action: .cycleColumnWidth),
        // カラムpin切り替え (Ctrl+Opt+P)
        Binding(modifiers: [.control, .option], keyCode: 35, action: .togglePin),
        // 終了
        Binding(modifiers: [.control, .option], keyCode: 12, action: .quit),
    ]

    static func checkInputMonitoringPermission() -> Bool {
        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static func requestInputMonitoringPermission() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    func start() {
        guard globalMonitor == nil, eventTap == nil else { return }

        if !startCGEventTap() {
            // CGEventTap 失敗時は NSEvent にフォールバック
            startNSEventMonitor()
        }

        // ローカルモニター（このアプリにフォーカスがある時）
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event: event)
            return event
        }
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil

        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor  { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
    }

    // MARK: - CGEventTap

    private func startCGEventTap() -> Bool {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }
                let manager = Unmanaged<KeyboardShortcutManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handleCGEvent(event)
                return Unmanaged.passRetained(event)
            },
            userInfo: selfPtr
        ) else {
            kbLog("[niri-mac] ❌ CGEventTap 作成失敗、NSEvent monitor にフォールバック")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        kbLog("[niri-mac] ✅ CGEventTap 有効 (iTerm2 等でも動作)")
        return true
    }

    private func handleCGEvent(_ event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let cgFlags = event.flags

        var flags: NSEvent.ModifierFlags = []
        if cgFlags.contains(.maskCommand)   { flags.insert(.command) }
        if cgFlags.contains(.maskAlternate) { flags.insert(.option) }
        if cgFlags.contains(.maskShift)     { flags.insert(.shift) }
        if cgFlags.contains(.maskControl)   { flags.insert(.control) }

        kbLog("[niri-mac] 🔑 CGEvent keyDown: keyCode=\(keyCode) flags=\(flags.rawValue)")
        handleKey(keyCode: keyCode, flags: flags)
    }

    // MARK: - NSEvent フォールバック

    private func startNSEventMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event: event)
        }
        if globalMonitor != nil {
            kbLog("[niri-mac] ✅ NSEvent global monitor 有効")
        } else {
            kbLog("[niri-mac] ❌ NSEvent global monitor 作成失敗")
            kbLog("[niri-mac]   システム設定 → プライバシーとセキュリティ → 入力監視 でNiriMacを許可してください")
        }
    }

    private func handle(event: NSEvent) {
        kbLog("[niri-mac] 🔑 NSEvent keyDown: keyCode=\(event.keyCode) flags=\(event.modifierFlags.rawValue)")
        handleKey(keyCode: event.keyCode, flags: event.modifierFlags)
    }

    // MARK: - 共通ハンドラ

    private func handleKey(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        let filtered = flags.intersection([.command, .option, .shift, .control])
        for binding in bindings {
            let required = binding.modifiers.intersection([.command, .option, .shift, .control])
            if binding.keyCode == keyCode && filtered == required {
                kbLog("[niri-mac] 🎹 \(binding.action)")
                onAction?(binding.action)
                return
            }
        }
    }
}
