import CoreGraphics

/// 純粋関数群。副作用なし、テスト容易。
/// niri の column_xs() + compute_new_view_offset に相当。
enum LayoutEngine {

    /// カラム群の左端X座標を累積計算（niri の column_xs() 相当）
    static func columnXPositions(
        columns: [Column],
        gap: CGFloat,
        startX: CGFloat = 0
    ) -> [CGFloat] {
        var xs: [CGFloat] = []
        var x = startX
        for col in columns {
            xs.append(x)
            x += col.width + gap
        }
        return xs
    }

    /// アクティブカラムが画面内に収まるようビューオフセットを計算
    static func computeViewOffset(
        columnXs: [CGFloat],
        columns: [Column],
        activeIndex: Int,
        viewportWidth: CGFloat,
        currentOffset: CGFloat
    ) -> CGFloat {
        guard activeIndex < columnXs.count else { return currentOffset }

        let activeX = columnXs[activeIndex]
        let activeWidth = columns[activeIndex].width

        // アクティブカラムを中央付近に
        let target = -(activeX + activeWidth / 2 - viewportWidth / 2)

        // 左端を超えないよう制限
        return min(0, target)
    }

    /// 各ウィンドウの最終スクリーン座標を算出（Quartz座標系で返す）
    ///
    /// Quartz座標系: 原点=メインスクリーン左上、Y軸下向き
    /// workingArea は setupScreens() で Cocoa → Quartz 変換済み
    /// distributeColumnHeight の winY は「作業領域上端からの視覚的オフセット（下向き増加）」
    /// → Quartz Y = workingArea.minY + winY  （自然に一致）
    static func computeWindowFrames(
        workspace: Workspace,
        screenFrame: CGRect,
        config: LayoutConfig
    ) -> [(WindowID, CGRect)] {
        var results: [(WindowID, CGRect)] = []

        let columns = workspace.columns
        guard !columns.isEmpty else { return results }

        let xs = columnXPositions(columns: columns, gap: config.gapWidth)
        let scrollOffset = workspace.viewOffset.current
        let workingArea = workspace.workingArea

        for (colIdx, column) in columns.enumerated() {
            let colX = xs[colIdx] + scrollOffset
            let screenX = workingArea.minX + config.gapWidth + colX

            let heights = distributeColumnHeight(
                column: column,
                availableHeight: workingArea.height,
                gap: config.gapHeight,
                focusedIndex: column.activeWindowIndex
            )

            for (winIdx, windowID) in column.windows.enumerated() {
                let (winY, winHeight) = heights[winIdx]
                // Quartz: Y軸は下向きなので上端 = workingArea.minY + winY
                let screenY = workingArea.minY + winY

                let frame = CGRect(
                    x: screenX,
                    y: screenY,
                    width: column.width,
                    height: winHeight
                )
                results.append((windowID, frame))
            }
        }

        return results
    }

    /// カラム内ウィンドウの縦分割を計算
    static func distributeColumnHeight(
        column: Column,
        availableHeight: CGFloat,
        gap: CGFloat,
        focusedIndex: Int
    ) -> [(y: CGFloat, height: CGFloat)] {
        let count = column.windows.count
        guard count > 0 else { return [] }

        let totalGap = gap * CGFloat(count - 1)
        let totalHeight = availableHeight - totalGap

        switch column.heightDistribution {
        case .equal:
            guard count > 0 else { return [] }
            // 全ウィンドウを等分配
            let normalizedRatios = Array(repeating: CGFloat(1.0) / CGFloat(count), count: count)

            var results: [(y: CGFloat, height: CGFloat)] = []
            var currentY: CGFloat = 0
            for (i, ratio) in normalizedRatios.enumerated() {
                let height = max(totalHeight * ratio, 50)
                results.append((currentY, height))
                currentY += height + (i < count - 1 ? gap : 0)
            }
            return results

        case .proportional(let ratios):
            let normalizedRatios: [CGFloat]
            if ratios.count == count {
                let sum = ratios.reduce(0, +)
                normalizedRatios = sum > 0 ? ratios.map { $0 / sum } : Array(repeating: 1.0 / CGFloat(count), count: count)
            } else {
                normalizedRatios = Array(repeating: 1.0 / CGFloat(count), count: count)
            }

            var results: [(y: CGFloat, height: CGFloat)] = []
            var currentY: CGFloat = 0
            for (i, ratio) in normalizedRatios.enumerated() {
                let height = max(totalHeight * ratio, 50)
                results.append((currentY, height))
                currentY += height + (i < count - 1 ? gap : 0)
            }
            return results
        }
    }
}
