import Testing
import AppKit
@testable import NiriMac

@Suite("KeyboardShortcutManager Binding Tests")
struct KeyboardShortcutManagerTests {

    @Test func defaultMetaGenerates21Bindings() {
        let bindings = KeyboardShortcutManager.buildBindings(meta: [.control, .option])
        #expect(bindings.count == 21)
    }

    @Test func focusLeftUsesMetaModifiers() {
        let bindings = KeyboardShortcutManager.buildBindings(meta: [.command, .option])
        let b = bindings.first { $0.action == .focusLeft }
        #expect(b?.modifiers == [.command, .option])
    }

    @Test func moveColumnLeftUsesMetaPlusShift() {
        let bindings = KeyboardShortcutManager.buildBindings(meta: [.command, .option])
        let b = bindings.first { $0.action == .moveColumnLeft }
        #expect(b?.modifiers == [.command, .option, .shift])
    }

    @Test func switchWorkspaceUpUsesMetaPlusCommand() {
        let bindings = KeyboardShortcutManager.buildBindings(meta: [.control, .option])
        let b = bindings.first { $0.action == .switchWorkspaceUp }
        #expect(b?.modifiers == [.control, .option, .command])
    }

    @Test func moveWindowToWorkspaceUsesMetaPlusCommandShift() {
        let bindings = KeyboardShortcutManager.buildBindings(meta: [.control, .option])
        let b = bindings.first { $0.action == .moveWindowToWorkspaceUp }
        #expect(b?.modifiers == [.control, .option, .command, .shift])
    }
}
