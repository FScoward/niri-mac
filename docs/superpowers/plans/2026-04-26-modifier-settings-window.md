# Modifier Settings Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ステータスバーの入れ子メニューを廃止し、SwiftUI + NSPanel による設定ウィンドウで modifier キーを設定できるようにする。

**Architecture:** `ModifierSettingsModel`（ObservableObject）で状態管理、`ModifierSettingsView`（SwiftUI Form）で UI、`ModifierSettingsWindowController`（NSWindowController）がシングルトンで NSPanel を管理。`NiriMacApp` はサブメニュー群を削除し「Modifier Settings...」の 1 項目に置き換える。

**Tech Stack:** Swift 5.9, AppKit, SwiftUI（NSHostingController 経由で埋め込み）, swift-testing

---

## File Map

| ファイル | 変更種別 |
|----------|----------|
| `Sources/NiriMac/App/ModifierSettingsView.swift` | **新規** — SwiftUI View + ObservableObject Model |
| `Sources/NiriMac/App/ModifierSettingsWindowController.swift` | **新規** — NSWindowController（シングルトン NSPanel）|
| `Sources/NiriMac/App/NiriMacApp.swift` | 変更 — サブメニュー削除、"Modifier Settings..." 追加 |
| `Tests/NiriMacTests/ModifierSettingsModelTests.swift` | **新規** — Model のユニットテスト |

---

### Task 1: ModifierSettingsModel + ModifierSettingsView (TDD)

**Files:**
- Create: `Sources/NiriMac/App/ModifierSettingsView.swift`
- Create: `Tests/NiriMacTests/ModifierSettingsModelTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/NiriMacTests/ModifierSettingsModelTests.swift` を新規作成:

```swift
import Testing
import AppKit
@testable import NiriMac

@Suite("ModifierSettingsModel Tests")
struct ModifierSettingsModelTests {

    @Test func currentMetaReflectsToggles() {
        let model = ModifierSettingsModel(
            meta: [.control, .option],
            scrollLayout: [.control],
            scrollFocus: [.control, .option]
        )
        #expect(model.currentMeta == [.control, .option])
        model.metaCommand = true
        #expect(model.currentMeta == [.control, .option, .command])
    }

    @Test func hasChangesWhenMetaDiffers() {
        let model = ModifierSettingsModel(
            meta: [.control, .option],
            scrollLayout: [.control],
            scrollFocus: [.control, .option]
        )
        #expect(model.hasChanges == false)
        model.metaShift = true
        #expect(model.hasChanges == true)
    }

    @Test func hasChangesWhenScrollLayoutDiffers() {
        let model = ModifierSettingsModel(
            meta: [.control, .option],
            scrollLayout: [.control],
            scrollFocus: [.control, .option]
        )
        model.layoutOption = true
        #expect(model.hasChanges == true)
    }

    @Test func anyEmptyWhenMetaAllUnchecked() {
        let model = ModifierSettingsModel(
            meta: [.control],
            scrollLayout: [.control],
            scrollFocus: [.control, .option]
        )
        model.metaControl = false
        #expect(model.anyEmpty == true)
    }

    @Test func metaHasCommandReflectsState() {
        let model = ModifierSettingsModel(
            meta: [.control, .option],
            scrollLayout: [.control],
            scrollFocus: [.control, .option]
        )
        #expect(model.metaHasCommand == false)
        model.metaCommand = true
        #expect(model.metaHasCommand == true)
    }
}
```

- [ ] **Step 2: テストがコンパイルエラーで失敗することを確認**

```bash
swift test --filter ModifierSettingsModelTests 2>&1 | tail -5
```

Expected: `error: cannot find type 'ModifierSettingsModel'`

- [ ] **Step 3: ModifierSettingsView.swift を作成**

`Sources/NiriMac/App/ModifierSettingsView.swift` を新規作成:

```swift
import SwiftUI
import AppKit

final class ModifierSettingsModel: ObservableObject {
    @Published var metaControl: Bool
    @Published var metaOption: Bool
    @Published var metaCommand: Bool
    @Published var metaShift: Bool

    @Published var layoutControl: Bool
    @Published var layoutOption: Bool
    @Published var layoutCommand: Bool
    @Published var layoutShift: Bool

    @Published var focusControl: Bool
    @Published var focusOption: Bool
    @Published var focusCommand: Bool
    @Published var focusShift: Bool

    private let originalMeta: NSEvent.ModifierFlags
    private let originalScrollLayout: NSEvent.ModifierFlags
    private let originalScrollFocus: NSEvent.ModifierFlags

    init(meta: NSEvent.ModifierFlags, scrollLayout: NSEvent.ModifierFlags, scrollFocus: NSEvent.ModifierFlags) {
        self.originalMeta = meta
        self.originalScrollLayout = scrollLayout
        self.originalScrollFocus = scrollFocus

        metaControl = meta.contains(.control)
        metaOption  = meta.contains(.option)
        metaCommand = meta.contains(.command)
        metaShift   = meta.contains(.shift)

        layoutControl = scrollLayout.contains(.control)
        layoutOption  = scrollLayout.contains(.option)
        layoutCommand = scrollLayout.contains(.command)
        layoutShift   = scrollLayout.contains(.shift)

        focusControl = scrollFocus.contains(.control)
        focusOption  = scrollFocus.contains(.option)
        focusCommand = scrollFocus.contains(.command)
        focusShift   = scrollFocus.contains(.shift)
    }

    var currentMeta: NSEvent.ModifierFlags {
        flags(metaControl, metaOption, metaCommand, metaShift)
    }

    var currentScrollLayout: NSEvent.ModifierFlags {
        flags(layoutControl, layoutOption, layoutCommand, layoutShift)
    }

    var currentScrollFocus: NSEvent.ModifierFlags {
        flags(focusControl, focusOption, focusCommand, focusShift)
    }

    var hasChanges: Bool {
        currentMeta != originalMeta ||
        currentScrollLayout != originalScrollLayout ||
        currentScrollFocus != originalScrollFocus
    }

    var anyEmpty: Bool {
        currentMeta.isEmpty || currentScrollLayout.isEmpty || currentScrollFocus.isEmpty
    }

    var metaHasCommand: Bool { metaCommand }

    private func flags(_ c: Bool, _ o: Bool, _ cmd: Bool, _ s: Bool) -> NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if c   { f.insert(.control) }
        if o   { f.insert(.option) }
        if cmd { f.insert(.command) }
        if s   { f.insert(.shift) }
        return f
    }
}

struct ModifierSettingsView: View {
    @ObservedObject var model: ModifierSettingsModel
    var onCancel: () -> Void
    var onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Keyboard Meta") {
                modifierGrid(
                    control: $model.metaControl,
                    option:  $model.metaOption,
                    command: $model.metaCommand,
                    shift:   $model.metaShift,
                    isEmpty: model.currentMeta.isEmpty
                )
                if model.metaHasCommand {
                    Label("Command はワークスペース操作と競合します", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            GroupBox("Scroll: Layout") {
                modifierGrid(
                    control: $model.layoutControl,
                    option:  $model.layoutOption,
                    command: $model.layoutCommand,
                    shift:   $model.layoutShift,
                    isEmpty: model.currentScrollLayout.isEmpty
                )
            }

            GroupBox("Scroll: Focus") {
                modifierGrid(
                    control: $model.focusControl,
                    option:  $model.focusOption,
                    command: $model.focusCommand,
                    shift:   $model.focusShift,
                    isEmpty: model.currentScrollFocus.isEmpty
                )
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Restart to Apply") {
                    ConfigStore.save(
                        meta: model.currentMeta,
                        scrollLayout: model.currentScrollLayout,
                        scrollFocus: model.currentScrollFocus
                    )
                    onApply()
                }
                .disabled(!model.hasChanges || model.anyEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    @ViewBuilder
    private func modifierGrid(
        control: Binding<Bool>,
        option:  Binding<Bool>,
        command: Binding<Bool>,
        shift:   Binding<Bool>,
        isEmpty: Bool
    ) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                Toggle("Control (⌃)", isOn: control)
                Toggle("Option (⌥)",  isOn: option)
            }
            GridRow {
                Toggle("Command (⌘)", isOn: command)
                Toggle("Shift (⇧)",   isOn: shift)
            }
        }
        .padding(.vertical, 4)
        if isEmpty {
            Text("最低1つ選択してください")
                .font(.caption)
                .foregroundColor(.red)
        }
    }
}
```

- [ ] **Step 4: テストがパスすることを確認**

```bash
swift test --filter ModifierSettingsModelTests 2>&1 | tail -5
```

Expected: `Test run with 5 tests passed.`

- [ ] **Step 5: 全テストが通ることを確認**

```bash
swift test 2>&1 | tail -3
```

Expected: 全テスト pass（93 + 5 = 98 tests）

- [ ] **Step 6: コミット**

```bash
git add Sources/NiriMac/App/ModifierSettingsView.swift Tests/NiriMacTests/ModifierSettingsModelTests.swift
git commit -m "feat: add ModifierSettingsModel and ModifierSettingsView (SwiftUI)"
```

---

### Task 2: ModifierSettingsWindowController

**Files:**
- Create: `Sources/NiriMac/App/ModifierSettingsWindowController.swift`

- [ ] **Step 1: ModifierSettingsWindowController.swift を作成**

`Sources/NiriMac/App/ModifierSettingsWindowController.swift` を新規作成:

```swift
import AppKit
import SwiftUI

final class ModifierSettingsWindowController: NSWindowController {

    private static var shared: ModifierSettingsWindowController?

    static func show() {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = ModifierSettingsWindowController()
        shared = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init() {
        let stored = ConfigStore.load()
        let model = ModifierSettingsModel(
            meta: stored.meta,
            scrollLayout: stored.scrollLayout,
            scrollFocus: stored.scrollFocus
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 100),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Modifier Key Settings"
        panel.isReleasedWhenClosed = false
        panel.center()

        super.init(window: panel)

        let view = ModifierSettingsView(
            model: model,
            onCancel: { [weak self] in self?.close() },
            onApply:  { [weak self] in
                self?.close()
                ModifierSettingsWindowController.relaunch()
            }
        )
        panel.contentViewController = NSHostingController(rootView: view)
    }

    required init?(coder: NSCoder) { nil }

    override func close() {
        super.close()
        Self.shared = nil
    }

    private static func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; exec /usr/bin/open \"$1\"", "sh", bundlePath]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }
}
```

- [ ] **Step 2: ビルドと全テスト確認**

```bash
swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3
```

Expected: `Build complete!` → 全テスト pass

- [ ] **Step 3: コミット**

```bash
git add Sources/NiriMac/App/ModifierSettingsWindowController.swift
git commit -m "feat: add ModifierSettingsWindowController (NSPanel singleton)"
```

---

### Task 3: NiriMacApp — サブメニューを設定ウィンドウに置き換え

**Files:**
- Modify: `Sources/NiriMac/App/NiriMacApp.swift`

- [ ] **Step 1: 不要なプロパティを削除**

`NiriMacApp` クラスから以下のプロパティを削除する:

```swift
// 削除対象
private var pendingMeta: NSEvent.ModifierFlags = [.control, .option]
private var pendingScrollLayout: NSEvent.ModifierFlags = [.option]
private var pendingScrollFocus: NSEvent.ModifierFlags = [.control, .option]
private var restartMenuItem: NSMenuItem?
```

- [ ] **Step 2: 不要なメソッドを削除**

以下のメソッドを全て削除する:
- `makeModifierSubmenu(title:current:tag:)` — サブメニュー生成
- `toggleModifier(_:)` — チェックボックストグル
- `restartToApply()` — 再起動

- [ ] **Step 3: applicationDidFinishLaunching を簡略化**

`applicationDidFinishLaunching` から pending 値の設定を削除:

```swift
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
```

- [ ] **Step 4: setupStatusBar の modifier 関連を置き換える**

`setupStatusBar()` 内の以下の既存ブロックを削除する:

```swift
// 削除対象（separator + 3つのサブメニュー + restartItem）
menu.addItem(NSMenuItem.separator())
menu.addItem(makeModifierSubmenu(title: "Keyboard Meta", current: pendingMeta, tag: 1))
menu.addItem(makeModifierSubmenu(title: "Scroll: Layout", current: pendingScrollLayout, tag: 2))
menu.addItem(makeModifierSubmenu(title: "Scroll: Focus", current: pendingScrollFocus, tag: 3))

let restartItem = NSMenuItem(title: "Restart to Apply...", action: #selector(restartToApply), keyEquivalent: "")
restartItem.target = self
restartItem.isEnabled = false
self.restartMenuItem = restartItem
menu.addItem(restartItem)
```

代わりに以下を追加（`reLayoutItem` の `menu.addItem(reLayoutItem)` の直後）:

```swift
menu.addItem(NSMenuItem.separator())
let settingsItem = NSMenuItem(title: "Modifier Settings...", action: #selector(showModifierSettings), keyEquivalent: "")
settingsItem.target = self
menu.addItem(settingsItem)
```

- [ ] **Step 5: showModifierSettings アクションを追加**

`NiriMacApp` に追加:

```swift
@objc private func showModifierSettings() {
    ModifierSettingsWindowController.show()
}
```

- [ ] **Step 6: ビルドと全テスト確認**

```bash
swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3
```

Expected: `Build complete!` → 全テスト pass

- [ ] **Step 7: コミット**

```bash
git add Sources/NiriMac/App/NiriMacApp.swift
git commit -m "feat: replace modifier submenus with Modifier Settings... window"
```

---

### Task 4: 手動動作確認

- [ ] **Step 1: アプリビルド**

```bash
bash make-app.sh && open NiriMac.app
```

- [ ] **Step 2: 設定ウィンドウを開く**

ステータスバー → 「Modifier Settings...」クリック → ウィンドウが開くことを確認

- [ ] **Step 3: 初期状態の確認**

- Keyboard Meta: Control ✓, Option ✓
- Scroll: Layout: Control ✓
- Scroll: Focus: Control ✓, Option ✓
- 「Restart to Apply」はグレーアウト

- [ ] **Step 4: 変更と再起動フロー**

1. Keyboard Meta の Control チェックを外す
2. 「Restart to Apply」が有効になることを確認
3. クリック → アプリが再起動する
4. 再起動後に「Modifier Settings...」を開いて変更が保持されていることを確認

- [ ] **Step 5: シングルトン確認**

「Modifier Settings...」を2回クリック → ウィンドウが2つ開かないことを確認

- [ ] **Step 6: Cancel 確認**

変更後「Cancel」→ 設定が変わっていないことを確認（ConfigStore を読んで元の値のまま）
