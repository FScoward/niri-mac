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
    private var pendingMeta: NSEvent.ModifierFlags = [.control, .option]
    private var pendingScrollLayout: NSEvent.ModifierFlags = [.option]
    private var pendingScrollFocus: NSEvent.ModifierFlags = [.control, .option]
    private var modifierChangePending = false
    private var restartMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        printDiagnostics()

        let stored = ConfigStore.load()
        pendingMeta = stored.meta
        pendingScrollLayout = stored.scrollLayout
        pendingScrollFocus = stored.scrollFocus

        setupStatusBar()

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
        menu.addItem(makeModifierSubmenu(title: "Keyboard Meta", current: pendingMeta, tag: 1))
        menu.addItem(makeModifierSubmenu(title: "Scroll: Layout", current: pendingScrollLayout, tag: 2))
        menu.addItem(makeModifierSubmenu(title: "Scroll: Focus", current: pendingScrollFocus, tag: 3))

        let restartItem = NSMenuItem(title: "Restart to Apply...", action: #selector(restartToApply), keyEquivalent: "")
        restartItem.target = self
        restartItem.isEnabled = false
        self.restartMenuItem = restartItem
        menu.addItem(restartItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    private func makeModifierSubmenu(title: String, current: NSEvent.ModifierFlags, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let pairs: [(String, NSEvent.ModifierFlags)] = [
            ("Control (⌃)", .control),
            ("Option (⌥)",  .option),
            ("Command (⌘)", .command),
            ("Shift (⇧)",   .shift),
        ]
        for (i, (label, flag)) in pairs.enumerated() {
            let mi = NSMenuItem(title: label, action: #selector(toggleModifier(_:)), keyEquivalent: "")
            mi.target = self
            mi.state = current.contains(flag) ? .on : .off
            mi.tag = tag * 10 + i
            submenu.addItem(mi)
        }
        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(NSMenuItem(title: "(再起動後に反映)", action: nil, keyEquivalent: ""))
        item.submenu = submenu
        return item
    }

    private static let modifierFlagList: [NSEvent.ModifierFlags] = [.control, .option, .command, .shift]

    @objc private func toggleModifier(_ sender: NSMenuItem) {
        let group = sender.tag / 10
        let flagIndex = sender.tag % 10
        guard flagIndex < NiriMacApp.modifierFlagList.count else { return }
        let flag = NiriMacApp.modifierFlagList[flagIndex]

        switch group {
        case 1:
            if pendingMeta.contains(flag) { pendingMeta.remove(flag) } else { pendingMeta.insert(flag) }
            if pendingMeta.isEmpty { pendingMeta.insert(flag); return }
            sender.state = pendingMeta.contains(flag) ? .on : .off
            if pendingMeta.contains(.command) {
                let alert = NSAlert()
                alert.messageText = "⚠️ Command をメタキーに含めると\nワークスペース操作が機能しなくなります"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        case 2:
            if pendingScrollLayout.contains(flag) { pendingScrollLayout.remove(flag) } else { pendingScrollLayout.insert(flag) }
            if pendingScrollLayout.isEmpty { pendingScrollLayout.insert(flag); return }
            sender.state = pendingScrollLayout.contains(flag) ? .on : .off
        case 3:
            if pendingScrollFocus.contains(flag) { pendingScrollFocus.remove(flag) } else { pendingScrollFocus.insert(flag) }
            if pendingScrollFocus.isEmpty { pendingScrollFocus.insert(flag); return }
            sender.state = pendingScrollFocus.contains(flag) ? .on : .off
        default:
            return
        }

        ConfigStore.save(meta: pendingMeta, scrollLayout: pendingScrollLayout, scrollFocus: pendingScrollFocus)
        modifierChangePending = true
        restartMenuItem?.isEnabled = true
    }

    @objc private func restartToApply() {
        let alert = NSAlert()
        alert.messageText = "再起動して設定変更を適用しますか？"
        alert.addButton(withTitle: "再起動")
        alert.addButton(withTitle: "キャンセル")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 0.5; open '\(bundlePath)'"]
        try? task.run()
        NSApplication.shared.terminate(nil)
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
