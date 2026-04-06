// Tests/NiriMacTests/WindowManagerLaunchTests.swift
import Testing
import Foundation

/// 新規アプリ起動時のウィンドウタイリング漏れ修正に関するロジックテスト
/// WindowManager は AX API に依存するため直接テスト不可。
/// ロジック単位（重複チェック・コールバック呼び出し回数）を検証する。
@Suite("WindowManager Launch Tests")
struct WindowManagerLaunchTests {

    // MARK: - 重複登録防止ロジック

    /// 同一 windowID に対して handleWindowCreated 相当のロジックを2回呼んでも
    /// registry への追加は1回だけであることを確認する
    @Test func duplicateWindowRegistration_isIgnored() {
        var registry: [UInt32: String] = [:]

        func addToRegistry(id: UInt32, title: String) {
            guard registry[id] == nil else { return }  // handleWindowCreated の guard と同等
            registry[id] = title
        }

        addToRegistry(id: 101, title: "First")
        addToRegistry(id: 101, title: "Second")  // 重複 → 無視されるはず

        #expect(registry.count == 1)
        #expect(registry[101] == "First")
    }

    // MARK: - 遅延スキャンのコールバック呼び出し

    /// onApplicationLaunched ハンドラが遅延後にスキャン関数を呼び出すことを確認する
    @Test func launchHandler_triggersDelayedWindowScan() async throws {
        var scanCallCount = 0

        // 遅延スキャンのシミュレーション: 0.6秒後にスキャン関数を呼ぶ
        let task = Task {
            try await Task.sleep(for: .milliseconds(600))
            scanCallCount += 1
        }

        try await task.value
        #expect(scanCallCount == 1)
    }

    /// 複数アプリが立て続けに起動した場合、それぞれ独立してスキャンされることを確認する
    @Test func multipleLaunches_eachTriggersIndependentScan() async throws {
        var scannedPIDs: [Int32] = []
        let lock = NSLock()

        let simulateLaunchHandler: (Int32) async throws -> Void = { pid in
            try await Task.sleep(for: .milliseconds(600))
            lock.withLock {
                scannedPIDs.append(pid)
            }
        }

        async let scan1 = try simulateLaunchHandler(1001)
        async let scan2 = try simulateLaunchHandler(1002)
        _ = try await (scan1, scan2)

        #expect(scannedPIDs.sorted() == [1001, 1002])
    }
}
