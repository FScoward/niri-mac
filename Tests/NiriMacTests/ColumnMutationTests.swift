import Testing
import CoreGraphics

@Suite("Column Mutation Tests")
struct ColumnMutationTests {

    // MARK: - moveActiveWindowUp

    @Test func moveActiveWindowUp_swapsAdjacentWindows() {
        var col = Column(windows: [1, 2, 3], width: 400)
        col.activeWindowIndex = 1  // window 2 がアクティブ
        col.moveActiveWindowUp()
        #expect(col.windows == [2, 1, 3])
        #expect(col.activeWindowIndex == 0)
    }

    @Test func moveActiveWindowUp_atFirstIndex_isNoop() {
        var col = Column(windows: [1, 2, 3], width: 400)
        col.activeWindowIndex = 0
        col.moveActiveWindowUp()
        #expect(col.windows == [1, 2, 3])
        #expect(col.activeWindowIndex == 0)
    }

    @Test func moveActiveWindowUp_lastToMiddle() {
        var col = Column(windows: [1, 2, 3], width: 400)
        col.activeWindowIndex = 2
        col.moveActiveWindowUp()
        #expect(col.windows == [1, 3, 2])
        #expect(col.activeWindowIndex == 1)
    }

    // MARK: - moveActiveWindowDown

    @Test func moveActiveWindowDown_swapsAdjacentWindows() {
        var col = Column(windows: [1, 2, 3], width: 400)
        col.activeWindowIndex = 1
        col.moveActiveWindowDown()
        #expect(col.windows == [1, 3, 2])
        #expect(col.activeWindowIndex == 2)
    }

    @Test func moveActiveWindowDown_atLastIndex_isNoop() {
        var col = Column(windows: [1, 2, 3], width: 400)
        col.activeWindowIndex = 2
        col.moveActiveWindowDown()
        #expect(col.windows == [1, 2, 3])
        #expect(col.activeWindowIndex == 2)
    }

    @Test func moveActiveWindowDown_firstToMiddle() {
        var col = Column(windows: [1, 2, 3], width: 400)
        col.activeWindowIndex = 0
        col.moveActiveWindowDown()
        #expect(col.windows == [2, 1, 3])
        #expect(col.activeWindowIndex == 1)
    }

    // MARK: - moveActiveWindow with proportional distribution

    @Test func moveActiveWindowUp_withProportionalDistribution_swapsRatiosInParallel() {
        var col = Column(windows: [1, 2, 3], width: 400)
        col.heightDistribution = .proportional([0.5, 0.3, 0.2])
        col.activeWindowIndex = 1  // window 2 (ratio 0.3) がアクティブ
        col.moveActiveWindowUp()
        #expect(col.windows == [2, 1, 3])
        #expect(col.activeWindowIndex == 0)
        if case .proportional(let ratios) = col.heightDistribution {
            #expect(abs(ratios[0] - 0.3) < 0.001)  // window 2 の比率
            #expect(abs(ratios[1] - 0.5) < 0.001)  // window 1 の比率
            #expect(abs(ratios[2] - 0.2) < 0.001)  // window 3 の比率（変わらず）
        } else {
            Issue.record("heightDistribution should be .proportional")
        }
    }

    @Test func moveActiveWindowDown_withProportionalDistribution_swapsRatiosInParallel() {
        var col = Column(windows: [1, 2, 3], width: 400)
        col.heightDistribution = .proportional([0.5, 0.3, 0.2])
        col.activeWindowIndex = 0  // window 1 (ratio 0.5) がアクティブ
        col.moveActiveWindowDown()
        #expect(col.windows == [2, 1, 3])
        #expect(col.activeWindowIndex == 1)
        if case .proportional(let ratios) = col.heightDistribution {
            #expect(abs(ratios[0] - 0.3) < 0.001)
            #expect(abs(ratios[1] - 0.5) < 0.001)
            #expect(abs(ratios[2] - 0.2) < 0.001)
        } else {
            Issue.record("heightDistribution should be .proportional")
        }
    }

    // MARK: - resizeActiveWindowHeight

    @Test func resizeActiveWindowHeight_withSingleWindow_isNoop() {
        var col = Column(windows: [1], width: 400)
        col.resizeActiveWindowHeight(delta: 0.10)
        if case .equal = col.heightDistribution {
            // 変化なし
        } else {
            Issue.record("single window column should remain .equal")
        }
    }

    @Test func resizeActiveWindowHeight_fromEqual_convertsToProportional() {
        var col = Column(windows: [1, 2], width: 400)
        col.activeWindowIndex = 0
        col.resizeActiveWindowHeight(delta: 0.10)
        if case .proportional(let ratios) = col.heightDistribution {
            #expect(ratios.count == 2)
            #expect(ratios[0] > ratios[1])  // アクティブが大きい
            // 合計は 1.0
            #expect(abs(ratios.reduce(0, +) - 1.0) < 0.001)
        } else {
            Issue.record("should convert to .proportional")
        }
    }

    @Test func resizeActiveWindowHeight_shrinksOthersProportionally() {
        var col = Column(windows: [1, 2, 3], width: 400)
        col.activeWindowIndex = 0
        col.resizeActiveWindowHeight(delta: 0.10)  // active に +10% 追加
        if case .proportional(let ratios) = col.heightDistribution {
            // active window の比率が最大
            #expect(ratios[0] > ratios[1])
            #expect(ratios[0] > ratios[2])
            // 合計は 1.0
            #expect(abs(ratios.reduce(0, +) - 1.0) < 0.001)
        } else {
            Issue.record("should be .proportional")
        }
    }

    @Test func resizeActiveWindowHeight_clampsAtMinimum() {
        var col = Column(windows: [1, 2], width: 400)
        col.activeWindowIndex = 0
        // 10回 +10% → 他のウィンドウが最小値 0.05 に達してもクラッシュしない
        for _ in 0..<10 {
            col.resizeActiveWindowHeight(delta: 0.10)
        }
        if case .proportional(let ratios) = col.heightDistribution {
            for r in ratios {
                #expect(r >= 0.05 - 0.001)
            }
            #expect(abs(ratios.reduce(0, +) - 1.0) < 0.001)
        } else {
            Issue.record("should be .proportional")
        }
    }

    @Test func resizeActiveWindowHeight_shrinkReducesActiveWindow() {
        var col = Column(windows: [1, 2], width: 400)
        col.activeWindowIndex = 0
        col.resizeActiveWindowHeight(delta: -0.10)
        if case .proportional(let ratios) = col.heightDistribution {
            // active が縮小されたので ratio[0] < ratio[1]
            #expect(ratios[0] < ratios[1])
            #expect(abs(ratios.reduce(0, +) - 1.0) < 0.001)
        } else {
            Issue.record("should be .proportional")
        }
    }
}
