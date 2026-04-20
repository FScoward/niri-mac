import Testing
import CoreGraphics
@testable import NiriMac

@Suite("Screen Change Tests")
struct ScreenChangeTests {

    @Test func reLayoutActionExists() {
        let action = KeyboardShortcutManager.Action.reLayout
        _ = action
    }
}
