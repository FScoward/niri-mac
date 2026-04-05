import Testing
import CoreGraphics

@Suite("Workspace Tests")
struct WorkspaceTests {

    // MARK: - recenterViewOffset (R-02)

    @Test func recenterViewOffset_alreadyVisible_noChange() {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [Column(windows: [1], width: 400)]
        ws.activeColumnIndex = 0
        ws.viewOffset = .static(offset: 0)

        ws.recenterViewOffset(gap: 16, animated: false)

        if case .static(let offset) = ws.viewOffset {
            #expect(abs(offset - 0) < 0.001)
        } else {
            Issue.record("Expected viewOffset to remain static(0)")
        }
    }

    @Test func recenterViewOffset_rightOvershoot_noChangeNeeded() {
        // 3カラムが全て workingArea 内に収まる場合
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            Column(windows: [1], width: 400),
            Column(windows: [2], width: 400),
            Column(windows: [3], width: 400),
        ]
        ws.activeColumnIndex = 2  // xs[2]=832, screenRight=1232 < 1440
        ws.viewOffset = .static(offset: 0)

        ws.recenterViewOffset(gap: 16, animated: false)

        if case .static(let offset) = ws.viewOffset {
            #expect(abs(offset - 0) < 0.001)
        } else {
            Issue.record("Expected no change")
        }
    }

    @Test func recenterViewOffset_rightOvershoot_scrollNeeded() {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 800, height: 900))
        // xs = [0, 516, 1032]
        ws.columns = [
            Column(windows: [1], width: 500),
            Column(windows: [2], width: 500),
            Column(windows: [3], width: 500),
        ]
        ws.activeColumnIndex = 2  // xs[2]=1032
        ws.viewOffset = .static(offset: 0)

        // screenLeft=1032, screenRight=1532 > 800
        // newOffset = -(1032 + 500 - 800 + 16) = -748
        ws.recenterViewOffset(gap: 16, animated: false)

        if case .static(let offset) = ws.viewOffset {
            #expect(offset < 0)
            #expect(abs(offset - (-748)) < 1.0)
        } else {
            Issue.record("Expected static offset after non-animated recenter")
        }
    }

    @Test func recenterViewOffset_leftOvershoot() {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 800, height: 900))
        ws.columns = [
            Column(windows: [1], width: 500),
            Column(windows: [2], width: 500),
        ]
        ws.activeColumnIndex = 0
        ws.viewOffset = .static(offset: -300)

        // screenLeft = 0 + (-300) = -300 < 0 → 左にはみ出し
        // newOffset = -0 + 16 = 16 → クランプ: min(0, 16) = 0
        ws.recenterViewOffset(gap: 16, animated: false)

        if case .static(let offset) = ws.viewOffset {
            #expect(offset >= -1)
        } else {
            Issue.record("Expected static offset")
        }
    }

    @Test func recenterViewOffset_clamping() {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 800, height: 900))
        ws.columns = [Column(windows: [1], width: 200)]
        ws.activeColumnIndex = 0
        ws.viewOffset = .static(offset: -200)

        // newOffset = 16 → clamped to 0
        ws.recenterViewOffset(gap: 16, animated: false)

        if case .static(let offset) = ws.viewOffset {
            #expect(abs(offset - 0) < 0.001)
        } else {
            Issue.record("Expected static(0) after clamping")
        }
    }

    @Test func recenterViewOffset_emptyColumns() {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = []
        ws.viewOffset = .static(offset: -100)

        ws.recenterViewOffset(gap: 16, animated: false)

        if case .static(let offset) = ws.viewOffset {
            #expect(abs(offset - 0) < 0.001)
        } else {
            Issue.record("Expected static(0) for empty workspace")
        }
    }
}
