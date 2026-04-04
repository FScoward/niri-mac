import AppKit
import Foundation

final class NiriMacApp: NSObject, NSApplicationDelegate {
    private var windowManager: WindowManager?
    private var statusItem: NSStatusItem?

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

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "niri-mac", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    @objc private func quit() {
        windowManager?.stop()
        NSApplication.shared.terminate(self)
    }
}
