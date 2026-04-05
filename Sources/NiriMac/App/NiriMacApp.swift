import AppKit
import Foundation

final class NiriMacApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var windowManager: WindowManager?
    private var statusItem: NSStatusItem?
    private var pinMenuItem: NSMenuItem?
    /// menuWillOpen 時点のカラムインデックスを保持（クリック後のフォーカス変化対策）
    private var pinnedTargetColumnIndex: Int?
    private var focusBorderMenuItem: NSMenuItem?
    private var focusDimMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        printDiagnostics()
        setupStatusBar()

        let config = LayoutConfig()
        windowManager = WindowManager(config: config)
        windowManager?.start()
    }

    private func printDiagnostics() {
        // 実行バイナリのパスを表示（アクセシビリティ許可に登録すべきパス）
        let binaryPath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments.first ?? "不明"
        print("[niri-mac] 実行バイナリ: \(binaryPath)")

        // アクセシビリティ権限（AX API 用）
        let trusted = AXIsProcessTrusted()
        print("[niri-mac] アクセシビリティ権限: \(trusted ? "✅ 許可済み" : "❌ 未許可")")

        if !trusted {
            print("[niri-mac] ⚠️ アクセシビリティ未許可: システム設定 > プライバシーとセキュリティ > アクセシビリティ で追加してください。")
        }

        // 入力監視権限をチェック＆リクエスト（NSEvent.addGlobalMonitorForEvents に必要）
        let inputMonitoring = KeyboardShortcutManager.checkInputMonitoringPermission()
        print("[niri-mac] 入力監視権限: \(inputMonitoring ? "✅ 許可済み" : "❌ 未許可")")
        if !inputMonitoring {
            print("[niri-mac] ⚠️ 入力監視未許可: システム設定 > プライバシーとセキュリティ > 入力監視 で追加してください。")
            KeyboardShortcutManager.requestInputMonitoringPermission()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowManager?.stop()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.title = "N"
            button.toolTip = "niri-mac"
        }

        let pinItem = NSMenuItem(title: "Pin Column", action: #selector(togglePin), keyEquivalent: "")
        pinItem.target = self
        self.pinMenuItem = pinItem

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "niri-mac", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(pinItem)
        menu.addItem(NSMenuItem.separator())

        let borderItem = NSMenuItem(title: "Focus Border", action: #selector(toggleFocusBorder), keyEquivalent: "")
        borderItem.target = self
        self.focusBorderMenuItem = borderItem
        menu.addItem(borderItem)

        let dimItem = NSMenuItem(title: "Focus Dim", action: #selector(toggleFocusDim), keyEquivalent: "")
        dimItem.target = self
        self.focusDimMenuItem = dimItem
        menu.addItem(dimItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    /// メニューが開く直前にアクティブカラムの pin 状態を記録してタイトルを更新する
    func menuWillOpen(_ menu: NSMenu) {
        // この時点のインデックスを保持（選択実行時にフォーカスが変わっても正しいカラムをpinできる）
        pinnedTargetColumnIndex = windowManager?.activeColumnIndex
        let isPinned = windowManager?.activeColumnIsPinned ?? false
        pinMenuItem?.title = isPinned ? "Unpin Column" : "Pin Column"
        focusBorderMenuItem?.state = windowManager?.focusBorderEnabled == true ? .on : .off
        focusDimMenuItem?.state = windowManager?.focusDimEnabled == true ? .on : .off
    }

    @objc private func togglePin() {
        windowManager?.handleAction(.togglePin, forColumnIndex: pinnedTargetColumnIndex)
    }

    @objc private func toggleFocusBorder() {
        windowManager?.toggleFocusBorder()
    }

    @objc private func toggleFocusDim() {
        windowManager?.toggleFocusDim()
    }

    @objc private func quit() {
        windowManager?.stop()
        NSApplication.shared.terminate(self)
    }
}
