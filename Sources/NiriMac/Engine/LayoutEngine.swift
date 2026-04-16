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
    ///
    /// isPinned なカラムは viewOffset を無視して画面左端に固定される。
    /// 非pinnedカラムはpinned領域の右側からスクロール可能に配置される。
    static func computeWindowFrames(
        workspace: Workspace,
        screenFrame: CGRect,
        config: LayoutConfig
    ) -> [(WindowID, CGRect)] {
        var results: [(WindowID, CGRect)] = []

        let columns = workspace.columns
        guard !columns.isEmpty else { return results }

        // Auto-Fit: 非pinnedカラム 1〜3 のときスクロール無しで画面を等分/中央配置
        if config.autoFitEnabled && workspace.isAutoFitEligible {
            return computeAutoFitFrames(workspace: workspace, config: config)
        }

        let scrollOffset = workspace.viewOffset.current
        let workingArea = workspace.workingArea
        let gap = config.gapWidth

        // pinned カラムが占める幅（leading gap + 各カラム幅 + gap）
        let pinnedAreaWidth: CGFloat = columns.reduce(0) { acc, col in
            col.isPinned ? acc + col.width + gap : acc
        }

        var pinnedXCursor: CGFloat = gap          // workingArea.minX からの相対位置
        var nonPinnedXCursor: CGFloat = 0         // pinnedAreaWidth の右側からの相対位置

        for column in columns {
            let screenX: CGFloat
            if column.isPinned {
                // スクロールに関わらず左端固定
                screenX = workingArea.minX + pinnedXCursor
                pinnedXCursor += column.width + gap
            } else {
                // pinned 領域の右側から scrollOffset を加算
                screenX = workingArea.minX + gap + pinnedAreaWidth + nonPinnedXCursor + scrollOffset
                nonPinnedXCursor += column.width + gap
            }

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

    /// Auto-Fit レイアウト: 非pinnedカラム 1〜3 のときスクロール無しで画面を等分/中央配置。
    /// `workspace.isAutoFitEligible` が true の場合に呼ばれる前提。
    /// - 1 カラム: `config.autoFitCenterWidthFraction` の幅で中央配置
    /// - 2 カラム: 左右等分（`(effectiveWidth - gap) / 2`）
    /// - 3 カラム: 3等分（`(effectiveWidth - 2*gap) / 3`）
    /// viewOffset は無視される。Column.width は変更しない（復帰時に元幅へ戻る）。
    static func computeAutoFitFrames(
        workspace: Workspace,
        config: LayoutConfig
    ) -> [(WindowID, CGRect)] {
        var results: [(WindowID, CGRect)] = []

        let columns = workspace.columns
        let n = columns.count
        guard (1...3).contains(n) else { return results }

        let workingArea = workspace.workingArea
        let gap = config.gapWidth
        // 両端ギャップを除いた実効幅
        let effectiveWidth = workingArea.width - 2 * gap

        // カラムごとの幅と左端X座標を決定
        let colWidth: CGFloat
        var xs: [CGFloat] = []
        switch n {
        case 1:
            colWidth = effectiveWidth * config.autoFitCenterWidthFraction
            xs = [workingArea.midX - colWidth / 2]
        case 2:
            colWidth = (effectiveWidth - gap) / 2
            let leftX = workingArea.minX + gap
            xs = [leftX, leftX + colWidth + gap]
        case 3:
            colWidth = (effectiveWidth - 2 * gap) / 3
            let leftX = workingArea.minX + gap
            xs = [
                leftX,
                leftX + colWidth + gap,
                leftX + (colWidth + gap) * 2
            ]
        default:
            return results
        }

        for (colIdx, column) in columns.enumerated() {
            let heights = distributeColumnHeight(
                column: column,
                availableHeight: workingArea.height,
                gap: config.gapHeight,
                focusedIndex: column.activeWindowIndex
            )
            for (winIdx, windowID) in column.windows.enumerated() {
                let (winY, winHeight) = heights[winIdx]
                let screenY = workingArea.minY + winY
                let frame = CGRect(
                    x: xs[colIdx],
                    y: screenY,
                    width: colWidth,
                    height: winHeight
                )
                results.append((windowID, frame))
            }
        }

        return results
    }

    /// カーソルX（Quartz スクリーン座標）から最も近いカラム間ギャップのインデックスを返す。
    /// - 返り値: 新カラムを挿入するインデックス（0=先頭, columns.count=末尾）
    static func nearestGapIndex(
        cursorX: CGFloat,
        workspace: Workspace,
        config: LayoutConfig
    ) -> Int {
        let gap = config.gapWidth
        let xs = workspace.columnXPositions(gap: gap)
        let offset = workspace.viewOffset.current
        let workingMinX = workspace.workingArea.minX

        // ギャップ中点 X を収集: 先頭 + 各カラム右端+gap/2
        var gapPositions: [CGFloat] = []
        gapPositions.append(workingMinX + gap / 2)  // 先頭（index 0）

        for (i, col) in workspace.columns.enumerated() {
            let colScreenX = workingMinX + gap + xs[i] + offset
            let colRightX = colScreenX + col.width
            gapPositions.append(colRightX + gap / 2)  // col[i]の後ろ（index i+1）
        }

        var nearestIdx = 0
        var minDist = CGFloat.greatestFiniteMagnitude
        for (i, gapX) in gapPositions.enumerated() {
            let dist = abs(cursorX - gapX)
            if dist < minDist { minDist = dist; nearestIdx = i }
        }
        return nearestIdx
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
