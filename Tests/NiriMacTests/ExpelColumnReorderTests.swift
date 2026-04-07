import Testing
import CoreGraphics

@Suite("ExpelColumnReorder Tests")
struct ExpelColumnReorderTests {

    // workingArea: x=0, y=0, w=1800, h=1000
    // gap=16, col幅=580 (≈1/3), columns=[A, B, C]
    // col[0]: screenX = 0+16+0 = 16, right = 596
    // col[1]: screenX = 16+580+16 = 612, right = 1192
    // col[2]: screenX = 1192+16 = 1208, right = 1788
    // gapPositions: [8, 604, 1200, 1796]
    //   index 0 = 8   (先頭)
    //   index 1 = 604 (col[0]の後ろ)
    //   index 2 = 1200(col[1]の後ろ)
    //   index 3 = 1796(col[2]の後ろ = 末尾)

    private func makeWorkspace() -> Workspace {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1800, height: 1000))
        ws.columns = [
            Column(windows: [1], width: 580),
            Column(windows: [2], width: 580),
            Column(windows: [3], width: 580),
        ]
        ws.viewOffset = .static(offset: 0)
        return ws
    }

    private var config: LayoutConfig { LayoutConfig(gapWidth: 16, gapHeight: 16) }

    @Test func nearestGapIndex_beforeFirstColumn() {
        let ws = makeWorkspace()
        // cursorX=0 → nearest gap index 0 (先頭)
        let idx = LayoutEngine.nearestGapIndex(cursorX: 0, workspace: ws, config: config)
        #expect(idx == 0)
    }

    @Test func nearestGapIndex_afterFirstColumn() {
        let ws = makeWorkspace()
        // cursorX=700 → nearest is gap[1]=604, index 1
        let idx = LayoutEngine.nearestGapIndex(cursorX: 700, workspace: ws, config: config)
        #expect(idx == 1)
    }

    @Test func nearestGapIndex_middleOfScreen() {
        let ws = makeWorkspace()
        // cursorX=900 → |900-604|=296, |900-1200|=300 → index 1
        let idx = LayoutEngine.nearestGapIndex(cursorX: 900, workspace: ws, config: config)
        #expect(idx == 1)
    }

    @Test func nearestGapIndex_afterLastColumn() {
        let ws = makeWorkspace()
        // cursorX=1790 → nearest is gap[3]=1796, index 3
        let idx = LayoutEngine.nearestGapIndex(cursorX: 1790, workspace: ws, config: config)
        #expect(idx == 3)
    }

    @Test func nearestGapIndex_withScrollOffset() {
        var ws = makeWorkspace()
        ws.viewOffset = .static(offset: -200)  // 200px 左にスクロール
        // col[0]: screenX=16-200=-184, right=396
        // gap[0]=8, gap[1]=404, gap[2]=1000, gap[3]=1596
        // cursorX=500 → |500-404|=96, |500-1000|=500 → index 1
        let idx = LayoutEngine.nearestGapIndex(cursorX: 500, workspace: ws, config: config)
        #expect(idx == 1)
    }
}
