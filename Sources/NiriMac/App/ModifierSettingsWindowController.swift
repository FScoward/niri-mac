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
