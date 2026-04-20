import Testing
import CoreGraphics

@Suite("LayoutEngine Tests")
struct LayoutEngineTests {

    // MARK: - columnXPositions

    @Test func columnXPositions() {
        let columns = [
            Column(windows: [1], width: 400),
            Column(windows: [2], width: 500),
            Column(windows: [3], width: 300),
        ]
        let xs = LayoutEngine.columnXPositions(columns: columns, gap: 16)
        #expect(abs(xs[0] - 0) < 0.001)
        #expect(abs(xs[1] - 416) < 0.001)   // 400 + 16
        #expect(abs(xs[2] - 932) < 0.001)   // 416 + 500 + 16
    }

    @Test func columnXPositionsEmpty() {
        let xs = LayoutEngine.columnXPositions(columns: [], gap: 16)
        #expect(xs.isEmpty)
    }

    // MARK: - distributeColumnHeight

    @Test func distributeColumnHeightEqual() {
        let col = Column(windows: [1, 2], width: 400)
        let results = LayoutEngine.distributeColumnHeight(
            column: col,
            availableHeight: 800,
            gap: 16,
            focusedIndex: 0
        )
        #expect(results.count == 2)
        // 全体800、gap=16 → totalHeight=784、各ウィンドウ=392
        #expect(abs(results[0].height - 392) < 0.1)
        #expect(abs(results[1].height - 392) < 0.1)
        #expect(abs(results[0].y - 0) < 0.001)
        #expect(abs(results[1].y - 408) < 0.1)   // 392 + 16
    }

    @Test func distributeColumnHeightProportional() {
        var col = Column(windows: [1, 2], width: 400)
        col.heightDistribution = .proportional([3.0, 1.0])
        let results = LayoutEngine.distributeColumnHeight(
            column: col,
            availableHeight: 800,
            gap: 16,
            focusedIndex: 0
        )
        #expect(results.count == 2)
        // totalHeight=784、ratios=[0.75, 0.25] → [588, 196]
        #expect(abs(results[0].height - 588) < 0.5)
        #expect(abs(results[1].height - 196) < 0.5)
    }

    // MARK: - computeWindowFrames

    @Test func computeWindowFrames() {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let col = Column(windows: [1], width: 400)
        ws.columns = [col]
        ws.activeColumnIndex = 0
        ws.viewOffset = .static(offset: 0)
        // 通常スクロールパスを検証するため Auto-Fit を解除
        ws.autoFitOverridden = true

        let config = LayoutConfig()
        let frames = LayoutEngine.computeWindowFrames(
            workspace: ws,
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            config: config
        )

        #expect(frames.count == 1)
        let (id, frame) = frames[0]
        #expect(id == 1)
        // screenX = workingArea.minX + gapWidth + colX = 0 + 16 + 0 = 16
        #expect(abs(frame.origin.x - 16) < 0.001)
        #expect(abs(frame.width - 400) < 0.001)
    }

    // MARK: - Auto-Fit

    @Test func autoFitCenter1Column() {
        // 1 カラム: 2/3 幅で中央配置
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [Column(windows: [1], width: 400)]
        ws.activeColumnIndex = 0

        #expect(ws.isAutoFitEligible)

        let config = LayoutConfig()
        let frames = LayoutEngine.computeWindowFrames(
            workspace: ws,
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            config: config
        )

        #expect(frames.count == 1)
        // effectiveWidth = 1440 - 32 = 1408, colWidth = 1408 * 2/3 ≈ 938.67
        let expectedWidth: CGFloat = 1408.0 * (2.0 / 3.0)
        let expectedX: CGFloat = 720 - expectedWidth / 2  // midX - width/2
        #expect(abs(frames[0].1.width - expectedWidth) < 0.5)
        #expect(abs(frames[0].1.origin.x - expectedX) < 0.5)
    }

    @Test func autoFitSplit2Columns() {
        // 2 カラム: 左右等分
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            Column(windows: [1], width: 400),
            Column(windows: [2], width: 600),
        ]
        ws.activeColumnIndex = 0

        let config = LayoutConfig()
        let frames = LayoutEngine.computeWindowFrames(
            workspace: ws,
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            config: config
        )

        #expect(frames.count == 2)
        // effectiveWidth = 1408, colWidth = (1408 - 16) / 2 = 696
        let expectedWidth: CGFloat = (1408 - 16) / 2
        #expect(abs(frames[0].1.width - expectedWidth) < 0.5)
        #expect(abs(frames[1].1.width - expectedWidth) < 0.5)
        #expect(abs(frames[0].1.origin.x - 16) < 0.5)  // minX + gap
        #expect(abs(frames[1].1.origin.x - (16 + expectedWidth + 16)) < 0.5)
    }

    @Test func autoFitSplit3Columns() {
        // 3 カラム: 3 等分
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            Column(windows: [1], width: 400),
            Column(windows: [2], width: 400),
            Column(windows: [3], width: 400),
        ]
        ws.activeColumnIndex = 0

        let config = LayoutConfig()
        let frames = LayoutEngine.computeWindowFrames(
            workspace: ws,
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            config: config
        )

        #expect(frames.count == 3)
        // effectiveWidth = 1408, colWidth = (1408 - 32) / 3 ≈ 458.67
        let expectedWidth: CGFloat = (1408 - 32) / 3
        for i in 0..<3 {
            #expect(abs(frames[i].1.width - expectedWidth) < 0.5)
        }
        #expect(abs(frames[0].1.origin.x - 16) < 0.5)
        #expect(abs(frames[1].1.origin.x - (16 + expectedWidth + 16)) < 0.5)
        #expect(abs(frames[2].1.origin.x - (16 + (expectedWidth + 16) * 2)) < 0.5)
    }

    @Test func autoFitDisabledWhen4Columns() {
        // 4 カラム: Auto-Fit 無効、通常スクロールに戻る
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            Column(windows: [1], width: 400),
            Column(windows: [2], width: 400),
            Column(windows: [3], width: 400),
            Column(windows: [4], width: 400),
        ]
        ws.activeColumnIndex = 0

        #expect(!ws.isAutoFitEligible)
    }

    @Test func autoFitDisabledWithPinned() {
        // pinned カラムがあれば Auto-Fit 無効
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        var pinnedCol = Column(windows: [1], width: 400)
        pinnedCol.isPinned = true
        ws.columns = [
            pinnedCol,
            Column(windows: [2], width: 400),
        ]
        ws.activeColumnIndex = 1

        #expect(!ws.isAutoFitEligible)
    }

    @Test func autoFitDisabledWhenOverridden() {
        // autoFitOverridden が true のとき無効
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [Column(windows: [1], width: 400)]
        ws.activeColumnIndex = 0
        ws.autoFitOverridden = true

        #expect(!ws.isAutoFitEligible)
    }

    @Test func autoFitOverridePreservedWithinThreshold() {
        // 1〜3 の範囲内でのカラム追加では override は維持される（手動幅を尊重）
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [Column(windows: [1], width: 400)]
        ws.activeColumnIndex = 0
        ws.autoFitOverridden = true

        ws.addColumn(Column(windows: [2], width: 400))
        #expect(ws.columns.count == 2)
        #expect(ws.autoFitOverridden == true)
        #expect(!ws.isAutoFitEligible)
    }

    @Test func autoFitOverrideResetOnCrossingThresholdDown() {
        // 4→3 で override リセットされ Auto-Fit 復帰
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            Column(windows: [1], width: 400),
            Column(windows: [2], width: 400),
            Column(windows: [3], width: 400),
            Column(windows: [4], width: 400),
        ]
        ws.activeColumnIndex = 0
        ws.autoFitOverridden = true

        ws.removeColumn(at: 3)
        #expect(ws.columns.count == 3)
        #expect(ws.autoFitOverridden == false)
        #expect(ws.isAutoFitEligible)
    }

    @Test func autoFitOverrideResetOnCrossingThresholdUp() {
        // 3→4 で override リセット（通常モードに移行するのでクリーンな状態に）
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            Column(windows: [1], width: 400),
            Column(windows: [2], width: 400),
            Column(windows: [3], width: 400),
        ]
        ws.activeColumnIndex = 0
        ws.autoFitOverridden = true

        ws.addColumn(Column(windows: [4], width: 400))
        #expect(ws.columns.count == 4)
        #expect(ws.autoFitOverridden == false)
        #expect(!ws.isAutoFitEligible)  // 4 カラムなので eligible には戻らない
    }

    @Test func autoFitDisabledByConfig() {
        // config.autoFitEnabled = false で無効化
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [Column(windows: [1], width: 400)]
        ws.activeColumnIndex = 0

        var config = LayoutConfig()
        config.autoFitEnabled = false
        let frames = LayoutEngine.computeWindowFrames(
            workspace: ws,
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            config: config
        )
        // 通常パス: colWidth=400（入力のまま）、x = minX+gap+0 = 16
        #expect(frames.count == 1)
        #expect(abs(frames[0].1.width - 400) < 0.5)
        #expect(abs(frames[0].1.origin.x - 16) < 0.5)
    }

    // MARK: - isWindowOffScreen (R-01)

    @Test func isWindowOffScreen_completelyLeft() {
        let workingArea = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: -500, y: 0, width: 400, height: 900)
        #expect(LayoutEngine.isWindowOffScreen(frame, workingArea: workingArea))
    }

    @Test func isWindowOffScreen_completelyRight() {
        let workingArea = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 1500, y: 0, width: 400, height: 900)
        #expect(LayoutEngine.isWindowOffScreen(frame, workingArea: workingArea))
    }

    @Test func isWindowOffScreen_partiallyLeft() {
        // 左にはみ出しているが右端は workingArea 内 → 表示（off-screen ではない）
        let workingArea = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: -100, y: 0, width: 400, height: 900)
        #expect(!LayoutEngine.isWindowOffScreen(frame, workingArea: workingArea))
    }

    @Test func isWindowOffScreen_partiallyRight() {
        // 右にはみ出しているが左端は workingArea 内 → 表示（off-screen ではない）
        let workingArea = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 1300, y: 0, width: 400, height: 900)
        #expect(!LayoutEngine.isWindowOffScreen(frame, workingArea: workingArea))
    }

    @Test func isWindowOffScreen_fullyInside() {
        let workingArea = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 100, y: 0, width: 400, height: 900)
        #expect(!LayoutEngine.isWindowOffScreen(frame, workingArea: workingArea))
    }

    @Test func isWindowOffScreen_exactLeftEdge() {
        // maxX == workingArea.minX → off-screen
        let workingArea = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: -400, y: 0, width: 400, height: 900)
        #expect(LayoutEngine.isWindowOffScreen(frame, workingArea: workingArea))
    }

    @Test func isWindowOffScreen_exactRightEdge() {
        // minX == workingArea.maxX → off-screen
        let workingArea = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 1440, y: 0, width: 400, height: 900)
        #expect(LayoutEngine.isWindowOffScreen(frame, workingArea: workingArea))
    }

    // MARK: - Vertical Padding

    @Test func verticalPaddingShiftsWindowY() {
        // Given: paddingVertical = 20 の config、高さ900の作業領域
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [Column(windows: [1], width: 400)]
        ws.activeColumnIndex = 0
        ws.autoFitOverridden = true

        var config = LayoutConfig()
        config.paddingVertical = 20

        let frames = LayoutEngine.computeWindowFrames(
            workspace: ws,
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            config: config
        )

        #expect(frames.count == 1)
        // Y は workingArea.minY + paddingVertical = 0 + 20 = 20 から始まる
        #expect(abs(frames[0].1.origin.y - 20) < 0.5)
        // 高さは availableHeight - 2*padding = 900 - 40 = 860
        #expect(abs(frames[0].1.height - 860) < 0.5)
    }

    @Test func verticalPaddingZeroIsUnchanged() {
        // paddingVertical = 0 (デフォルト) は従来動作と同一
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [Column(windows: [1], width: 400)]
        ws.activeColumnIndex = 0
        ws.autoFitOverridden = true

        var config = LayoutConfig()
        config.paddingVertical = 0

        let frames = LayoutEngine.computeWindowFrames(
            workspace: ws,
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            config: config
        )

        #expect(frames.count == 1)
        #expect(abs(frames[0].1.origin.y - 0) < 0.5)
        #expect(abs(frames[0].1.height - 900) < 0.5)
    }

    @Test func verticalPaddingAutoFit() {
        // Auto-Fit パスでも paddingVertical が効く
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [Column(windows: [1], width: 400)]
        ws.activeColumnIndex = 0
        // autoFitOverridden = false → Auto-Fit パス

        var config = LayoutConfig()
        config.paddingVertical = 30

        let frames = LayoutEngine.computeWindowFrames(
            workspace: ws,
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            config: config
        )

        #expect(frames.count == 1)
        #expect(abs(frames[0].1.origin.y - 30) < 0.5)
        #expect(abs(frames[0].1.height - 840) < 0.5)  // 900 - 60
    }

    @Test func verticalPaddingMultiWindowColumn() {
        // 複数ウィンドウのカラムでも Y オフセットが正しい
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [Column(windows: [1, 2], width: 400)]
        ws.activeColumnIndex = 0
        ws.autoFitOverridden = true

        var config = LayoutConfig()
        config.paddingVertical = 10
        config.gapHeight = 16

        let frames = LayoutEngine.computeWindowFrames(
            workspace: ws,
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            config: config
        )

        #expect(frames.count == 2)
        // 最初のウィンドウの Y = workingArea.minY + paddingVertical = 10
        #expect(abs(frames[0].1.origin.y - 10) < 0.5)
        // availableHeight = 900 - 20 = 880, gap=16 → totalHeight=864, 各=432
        #expect(abs(frames[0].1.height - 432) < 0.5)
        // 2つ目の Y = 10 + 432 + 16 = 458
        #expect(abs(frames[1].1.origin.y - 458) < 0.5)
    }
}
