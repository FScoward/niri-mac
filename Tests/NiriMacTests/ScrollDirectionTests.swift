import Testing
import CoreGraphics
@testable import NiriMac

@Suite("Scroll Direction Tests")
struct ScrollDirectionTests {

    // 右スワイプ（deltaX > 0）で右のコンテンツが見える（viewOffset が負方向）
    @Test func rightSwipe_movesViewOffsetNegative() {
        var ws = NiriMac.Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            NiriMac.Column(windows: [1], width: 480),
            NiriMac.Column(windows: [2], width: 480),
            NiriMac.Column(windows: [3], width: 480),
        ]
        ws.viewOffset = .static(offset: 0)

        ws.applyScrollDelta(deltaX: 10.0, sensitivity: 1.0, isContinuous: true)

        #expect(ws.viewOffset.current < 0)
    }

    // 左スワイプ（deltaX < 0）でオフセットが 0 方向（左コンテンツ方向）
    @Test func leftSwipe_doesNotGoPositive() {
        var ws = NiriMac.Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            NiriMac.Column(windows: [1], width: 480),
            NiriMac.Column(windows: [2], width: 480),
            NiriMac.Column(windows: [3], width: 480),
        ]
        ws.viewOffset = .static(offset: -200)

        ws.applyScrollDelta(deltaX: -10.0, sensitivity: 1.0, isContinuous: true)

        #expect(ws.viewOffset.current <= 0)
        #expect(ws.viewOffset.current > -200)
    }

    // minOffset クランプ: コンテンツ端を超えてスクロールしない
    @Test func rightSwipe_clampedAtMinOffset() {
        var ws = NiriMac.Workspace(workingArea: CGRect(x: 0, y: 0, width: 800, height: 900))
        ws.columns = [
            NiriMac.Column(windows: [1], width: 480),
            NiriMac.Column(windows: [2], width: 480),
            NiriMac.Column(windows: [3], width: 480),
        ]
        ws.viewOffset = .static(offset: -700)

        ws.applyScrollDelta(deltaX: 1000.0, sensitivity: 1.0, isContinuous: true)

        #expect(ws.viewOffset.current >= -728)
    }

    // deltaX=0 はオフセットを変えない
    @Test func zeroDelta_noChange() {
        // workingArea=800, 3カラム×480+gap → minOffset = 800-16-(480*3+16*2) = 800-16-1472 = -688
        // -100 は minOffset より大きいのでクランプされない
        var ws = NiriMac.Workspace(workingArea: CGRect(x: 0, y: 0, width: 800, height: 900))
        ws.columns = [
            NiriMac.Column(windows: [1], width: 480),
            NiriMac.Column(windows: [2], width: 480),
            NiriMac.Column(windows: [3], width: 480),
        ]
        ws.viewOffset = .static(offset: -100)

        ws.applyScrollDelta(deltaX: 0, sensitivity: 1.0, isContinuous: true)

        #expect(abs(ws.viewOffset.current - (-100)) < 0.001)
    }
}
