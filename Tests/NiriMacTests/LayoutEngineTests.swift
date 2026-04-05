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
}
