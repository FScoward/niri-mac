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
        case moveWindowUpInColumn, moveWindowDownInColumn
        case growWindowHeight, shrinkWindowHeight
        case toggleAutoFit
        case quit
        case reLayout
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

    private let bindings: [Binding]

    init(metaModifiers: NSEvent.ModifierFlags = [.control, .option]) {
        self.bindings = KeyboardShortcutManager.buildBindings(meta: metaModifiers)
    }

    static func buildBindings(meta: NSEvent.ModifierFlags) -> [Binding] {
        let metaShift    = meta.union([.shift])
        let metaCmd      = meta.union([.command])
        let metaCmdShift = meta.union([.command, .shift])
        return [
            // カラム間フォーカス
            Binding(modifiers: meta,         keyCode: 123, action: .focusLeft),
            Binding(modifiers: meta,         keyCode: 124, action: .focusRight),
            // カラム内ウィンドウ
            Binding(modifiers: meta,         keyCode: 126, action: .focusUp),
            Binding(modifiers: meta,         keyCode: 125, action: .focusDown),
            // カラム並べ替え
            Binding(modifiers: metaShift,    keyCode: 123, action: .moveColumnLeft),
            Binding(modifiers: metaShift,    keyCode: 124, action: .moveColumnRight),
            // ワークスペース切り替え
            Binding(modifiers: metaCmd,      keyCode: 126, action: .switchWorkspaceUp),
            Binding(modifiers: metaCmd,      keyCode: 125, action: .switchWorkspaceDown),
            // ウィンドウをワークスペース移動
            Binding(modifiers: metaCmdShift, keyCode: 126, action: .moveWindowToWorkspaceUp),
            Binding(modifiers: metaCmdShift, keyCode: 125, action: .moveWindowToWorkspaceDown),
            // カラム操作
            Binding(modifiers: meta,         keyCode: 36,  action: .consumeIntoColumnLeft),
            Binding(modifiers: metaShift,    keyCode: 36,  action: .expelFromColumn),
            // カラム幅・pin
            Binding(modifiers: meta,         keyCode: 15,  action: .cycleColumnWidth),
            Binding(modifiers: meta,         keyCode: 35,  action: .togglePin),
            // カラム内ウィンドウ並び替え
            Binding(modifiers: metaShift,    keyCode: 126, action: .moveWindowUpInColumn),
            Binding(modifiers: metaShift,    keyCode: 125, action: .moveWindowDownInColumn),
            // ウィンドウ高さリサイズ
            Binding(modifiers: meta,         keyCode: 27,  action: .shrinkWindowHeight),
            Binding(modifiers: meta,         keyCode: 24,  action: .growWindowHeight),
            // Auto-Fit
            Binding(modifiers: meta,         keyCode: 0,   action: .toggleAutoFit),
            // 終了
            Binding(modifiers: meta,         keyCode: 12,  action: .quit),
            // Re-layout
            Binding(modifiers: metaShift,    keyCode: 3,   action: .reLayout),
        ]
    }

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
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }
                let manager = Unmanaged<KeyboardShortcutManager>.fromOpaque(refcon).takeUnretainedValue()
                // システムがタップを無効化した時は即再有効化する（放置するとキーショートカットが永続的に効かなくなる）
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    let reason = type == .tapDisabledByTimeout ? "timeout" : "userInput"
                    kbLog("[tap] ⚠️ keyboard tap disabled by \(reason) — re-enabling")
                    if let tap = manager.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }
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
