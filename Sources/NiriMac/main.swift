import AppKit

let app = NSApplication.shared
let delegate = NiriMacApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // Dock に表示しない
app.run()
