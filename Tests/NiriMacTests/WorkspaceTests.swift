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

    // MARK: - consumeWindowIntoColumn

    @Test func consumeWindowIntoColumn_above_insertsBefore() {
        // Win 1 (col 0) を Win 2 (col 1) の上にスタック
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            Column(windows: [1], width: 400),
            Column(windows: [2, 3], width: 400),
        ]
        ws.activeColumnIndex = 0

        ws.consumeWindowIntoColumn(1, target: 2, position: .above)

        // col 0 が消えて col 0（元col1）が [1, 2, 3] になる
        #expect(ws.columns.count == 1)
        #expect(ws.columns[0].windows == [1, 2, 3])
    }

    @Test func consumeWindowIntoColumn_below_insertsAfter() {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            Column(windows: [1], width: 400),
            Column(windows: [2, 3], width: 400),
        ]

        ws.consumeWindowIntoColumn(1, target: 2, position: .below)

        // [2, 1, 3] になる
        #expect(ws.columns.count == 1)
        #expect(ws.columns[0].windows == [2, 1, 3])
    }

    @Test func consumeWindowIntoColumn_removesEmptySourceColumn() {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            Column(windows: [1], width: 400),   // col 0: 1個だけ
            Column(windows: [2], width: 400),   // col 1
        ]

        ws.consumeWindowIntoColumn(1, target: 2, position: .above)

        #expect(ws.columns.count == 1)
        #expect(ws.columns[0].windows.contains(1))
        #expect(ws.columns[0].windows.contains(2))
    }

    @Test func consumeWindowIntoColumn_sourceHasMultipleWindows_columnRemains() {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            Column(windows: [1, 2], width: 400),  // col 0: 2個
            Column(windows: [3], width: 400),      // col 1
        ]

        ws.consumeWindowIntoColumn(1, target: 3, position: .below)

        // col 0 は [2] のまま残る
        #expect(ws.columns.count == 2)
        #expect(ws.columns[0].windows == [2])
        #expect(ws.columns[1].windows == [3, 1])
    }

    @Test func consumeWindowIntoColumn_sameColumn_isNoop() {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [Column(windows: [1, 2], width: 400)]

        ws.consumeWindowIntoColumn(1, target: 2, position: .above)

        // 変化なし
        #expect(ws.columns.count == 1)
        #expect(ws.columns[0].windows == [1, 2])
    }

    @Test func consumeWindowIntoColumn_setsFocusToDraggedWindow() {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            Column(windows: [1], width: 400),
            Column(windows: [2], width: 400),
        ]

        ws.consumeWindowIntoColumn(1, target: 2, position: .below)

        // 挿入後、activeWindowIndex が draggedID（Win 1）を指す
        #expect(ws.columns[0].activeWindowID == 1)
    }

    // MARK: - expelWindow

    @Test func expelWindow_right_insertsAfterSourceColumn() {
        // Win 2 を col 0 [1,2,3] から抜き出し、col 0 の右（= col 1）に新カラムとして挿入
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            Column(windows: [1, 2, 3], width: 400),
            Column(windows: [4], width: 400),
        ]
        ws.activeColumnIndex = 0

        let result = ws.expelWindow(2, newColumnWidth: 400, insertSide: .right)

        #expect(result == true)
        #expect(ws.columns.count == 3)
        #expect(ws.columns[0].windows == [1, 3])
        #expect(ws.columns[1].windows == [2])
        #expect(ws.columns[2].windows == [4])
    }

    @Test func expelWindow_left_insertsBeforeSourceColumn() {
        // Win 2 を col 0 [1,2,3] から抜き出し、col 0 の左（= col 0）に新カラムとして挿入
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            Column(windows: [1, 2, 3], width: 400),
            Column(windows: [4], width: 400),
        ]
        ws.activeColumnIndex = 0

        let result = ws.expelWindow(2, newColumnWidth: 400, insertSide: .left)

        #expect(result == true)
        #expect(ws.columns.count == 3)
        #expect(ws.columns[0].windows == [2])
        #expect(ws.columns[1].windows == [1, 3])
        #expect(ws.columns[2].windows == [4])
    }

    @Test func expelWindow_singleWindowColumn_returnsFalseAndIsNoop() {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [Column(windows: [1], width: 400)]

        let result = ws.expelWindow(1, newColumnWidth: 400, insertSide: .right)

        #expect(result == false)
        #expect(ws.columns.count == 1)
        #expect(ws.columns[0].windows == [1])
    }

    @Test func expelWindow_windowNotFound_returnsFalseAndIsNoop() {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [Column(windows: [1, 2], width: 400)]

        let result = ws.expelWindow(99, newColumnWidth: 400, insertSide: .right)

        #expect(result == false)
        #expect(ws.columns.count == 1)
        #expect(ws.columns[0].windows == [1, 2])
    }

    @Test func expelWindow_setsFocusToNewColumn() {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            Column(windows: [1, 2], width: 400),
            Column(windows: [3], width: 400),
        ]
        ws.activeColumnIndex = 0

        ws.expelWindow(2, newColumnWidth: 400, insertSide: .right)

        // 新カラムが activeColumnIndex で参照できる
        #expect(ws.activeColumnIndex == 1)
        #expect(ws.columns[ws.activeColumnIndex].windows == [2])
    }

    @Test func expelWindow_usesSpecifiedWidth() {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [Column(windows: [1, 2], width: 400)]

        ws.expelWindow(2, newColumnWidth: 600, insertSide: .right)

        #expect(ws.columns[1].width == 600)
    }
}
