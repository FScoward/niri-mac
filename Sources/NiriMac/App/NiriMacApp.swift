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
    private var autoFitMenuItem: NSMenuItem?
    private var excludedAppsMenuItem: NSMenuItem?
    func applicationDidFinishLaunching(_ notification: Notification) {
        printDiagnostics()
        setupStatusBar()

        let stored = ConfigStore.load()
        var config = LayoutConfig()
        config.metaModifiers = stored.meta
        config.scrollLayoutModifiers = stored.scrollLayout
        config.scrollFocusModifiers = stored.scrollFocus
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

        let excludedAppsItem = NSMenuItem(title: "Excluded Apps", action: nil, keyEquivalent: "")
        excludedAppsItem.submenu = NSMenu()
        self.excludedAppsMenuItem = excludedAppsItem
        menu.addItem(excludedAppsItem)
        menu.addItem(NSMenuItem.separator())

        let autoFitItem = NSMenuItem(title: "Auto-Fit Layout", action: #selector(toggleAutoFit), keyEquivalent: "")
        autoFitItem.target = self
        self.autoFitMenuItem = autoFitItem
        menu.addItem(autoFitItem)

        let borderItem = NSMenuItem(title: "Focus Border", action: #selector(toggleFocusBorder), keyEquivalent: "")
        borderItem.target = self
        self.focusBorderMenuItem = borderItem
        menu.addItem(borderItem)

        let dimItem = NSMenuItem(title: "Focus Dim", action: #selector(toggleFocusDim), keyEquivalent: "")
        dimItem.target = self
        self.focusDimMenuItem = dimItem
        menu.addItem(dimItem)

        let reLayoutItem = NSMenuItem(title: "Re-layout (Ctrl+Opt+Shift+F)", action: #selector(reLayout), keyEquivalent: "")
        reLayoutItem.target = self
        menu.addItem(reLayoutItem)

        menu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: "Modifier Settings...", action: #selector(showModifierSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    @objc private func showModifierSettings() {
        ModifierSettingsWindowController.show()
    }

    /// メニューが開く直前にアクティブカラムの pin 状態を記録してタイトルを更新する
    func menuWillOpen(_ menu: NSMenu) {
        // この時点のインデックスを保持（選択実行時にフォーカスが変わっても正しいカラムをpinできる）
        pinnedTargetColumnIndex = windowManager?.activeColumnIndex
        let isPinned = windowManager?.activeColumnIsPinned ?? false
        pinMenuItem?.title = isPinned ? "Unpin Column" : "Pin Column"
        autoFitMenuItem?.state = windowManager?.autoFitEnabled == true ? .on : .off
        focusBorderMenuItem?.state = windowManager?.focusBorderEnabled == true ? .on : .off
        focusDimMenuItem?.state = windowManager?.focusDimEnabled == true ? .on : .off

        // Excluded Apps サブメニューを動的生成
        if let submenu = excludedAppsMenuItem?.submenu {
            submenu.removeAllItems()

            // 「現在のアプリを除外」
            let excludeCurrentItem = NSMenuItem(
                title: "Exclude Current App",
                action: #selector(excludeCurrentApp),
                keyEquivalent: ""
            )
            excludeCurrentItem.target = self
            if windowManager?.focusedAppBundleID == nil {
                excludeCurrentItem.isEnabled = false
            }
            submenu.addItem(excludeCurrentItem)

            // 除外済みアプリがあればセパレータ＋リスト
            if let apps = windowManager?.excludedApps, !apps.isEmpty {
                submenu.addItem(NSMenuItem.separator())
                for app in apps {
                    let item = NSMenuItem(
                        title: app.name,
                        action: #selector(includeApp(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.representedObject = app.bundleID
                    item.state = .on
                    submenu.addItem(item)
                }
            }
        }
    }

    @objc private func togglePin() {
        windowManager?.handleAction(.togglePin, forColumnIndex: pinnedTargetColumnIndex)
    }

    @objc private func toggleAutoFit() {
        windowManager?.toggleAutoFit()
    }

    @objc private func toggleFocusBorder() {
        windowManager?.toggleFocusBorder()
    }

    @objc private func toggleFocusDim() {
        windowManager?.toggleFocusDim()
    }

    @objc private func reLayout() {
        windowManager?.handleAction(.reLayout)
    }

    @objc private func excludeCurrentApp() {
        guard let bundleID = windowManager?.focusedAppBundleID else { return }
        windowManager?.excludeApp(bundleID: bundleID)
    }

    @objc private func includeApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        windowManager?.includeApp(bundleID: bundleID)
    }

    @objc private func quit() {
        windowManager?.stop()
        NSApplication.shared.terminate(self)
    }
}
