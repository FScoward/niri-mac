import Testing
import Foundation
import AppKit
@testable import NiriMac

@Suite("ConfigStore Tests")
struct ConfigStoreTests {

    private func makeTempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("config.json")
    }

    @Test func loadReturnsDefaultsWhenFileNotFound() {
        let url = makeTempURL()
        let result = ConfigStore.load(from: url)
        #expect(result.meta == [.control, .option])
        #expect(result.scrollLayout == [.control])
        #expect(result.scrollFocus == [.control, .option])
    }

    @Test func saveAndLoad() {
        let url = makeTempURL()
        ConfigStore.save(
            meta: [.command, .option],
            scrollLayout: [.control],
            scrollFocus: [.command, .shift],
            to: url
        )
        let result = ConfigStore.load(from: url)
        #expect(result.meta == [.command, .option])
        #expect(result.scrollLayout == [.control])
        #expect(result.scrollFocus == [.command, .shift])
    }

    @Test func loadReturnsDefaultsWhenFileCorrupted() throws {
        let url = makeTempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        let result = ConfigStore.load(from: url)
        #expect(result.meta == [.control, .option])
    }

    @Test func stringsFromFlagsRoundTrip() {
        let flags: NSEvent.ModifierFlags = [.control, .option, .command]
        let strings = ConfigStore.strings(from: flags)
        let restored = ConfigStore.flags(from: strings)
        #expect(restored == flags)
    }
}
