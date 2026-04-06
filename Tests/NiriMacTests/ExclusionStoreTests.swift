import Testing
import Foundation
@testable import NiriMac

@Suite("ExclusionStore Tests")
struct ExclusionStoreTests {

    private func makeTempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("excluded-apps.json")
    }

    @Test func loadReturnsEmptyWhenFileNotFound() {
        let url = makeTempURL()
        let result = ExclusionStore.load(from: url)
        #expect(result.isEmpty)
    }

    @Test func saveAndLoad() throws {
        let url = makeTempURL()
        let ids: Set<String> = ["com.apple.finder", "com.docker.docker"]
        ExclusionStore.save(ids, to: url)
        let loaded = ExclusionStore.load(from: url)
        #expect(loaded == ids)
    }

    @Test func loadReturnsEmptyWhenFileCorrupted() throws {
        let url = makeTempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        let result = ExclusionStore.load(from: url)
        #expect(result.isEmpty)
    }

    @Test func saveCreatesDirectoryIfNeeded() {
        let url = makeTempURL()
        ExclusionStore.save(["com.test.app"], to: url)
        let loaded = ExclusionStore.load(from: url)
        #expect(loaded == ["com.test.app"])
    }
}
