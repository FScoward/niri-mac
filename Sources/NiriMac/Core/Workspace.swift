import CoreGraphics
import Foundation

/// niri の ScrollingSpace に相当。カラムの水平ストリップ + スクロール位置。
struct Workspace {
    let id: UUID
    var columns: [Column]
    var activeColumnIndex: Int
    var viewOffset: ViewOffset
    var workingArea: CGRect
    /// true のとき Auto-Fit を解除し通常スクロールにフォールバックする。
    /// ユーザーが明示的にカラム幅を操作した時に立ち、カラム追加/削除でリセットされる。
    var autoFitOverridden: Bool

    init(workingArea: CGRect) {
        self.id = UUID()
        self.columns = []
        self.activeColumnIndex = 0
        self.viewOffset = .static(offset: 0)
        self.workingArea = workingArea
        self.autoFitOverridden = false
    }

    /// Auto-Fit レイアウトの適用可否（configの `autoFitEnabled` は呼び出し側で判定）。
    /// - pinned カラムが無い
    /// - カラム数が 1〜3
    /// - ユーザーが手動でカラム幅を変更していない（`autoFitOverridden == false`）
    var isAutoFitEligible: Bool {
        guard !autoFitOverridden else { return false }
        guard (1...3).contains(columns.count) else { return false }
        return !columns.contains(where: { $0.isPinned })
    }

    var activeColumn: Column? {
        guard !columns.isEmpty, activeColumnIndex < columns.count else { return nil }
        return columns[activeColumnIndex]
    }

    var activeWindowID: WindowID? {
        activeColumn?.activeWindowID
    }

    var isEmpty: Bool { columns.isEmpty }

    /// ビューポートの左端X座標（スクリーン座標ではなくワークスペース内相対座標）
    var viewPositionX: CGFloat {
        let xs = columnXPositions()
        guard activeColumnIndex < xs.count else { return viewOffset.current }
        return xs[activeColumnIndex] + viewOffset.current
    }

    /// 全カラムのX座標を返す（ワークスペース相対）
    func columnXPositions(gap: CGFloat = 16) -> [CGFloat] {
        var xs: [CGFloat] = []
        var x: CGFloat = 0
        for col in columns {
            xs.append(x)
            x += col.width + gap
        }
        return xs
    }

    /// アクティブカラムが画面内に収まるよう viewOffset を最小限更新（仕様書 §5）
    ///
    /// 既に完全に workingArea 内に収まっている場合は何もしない。
    /// はみ出している場合のみ、最小限のスクロールで画面内に収める。
    /// isPinned なカラムは常に画面内固定なので、アクティブカラムが pinned の場合は何もしない。
    mutating func recenterViewOffset(gap: CGFloat = 16, animated: Bool = true) {
        guard !columns.isEmpty, activeColumnIndex < columns.count else {
            if animated {
                viewOffset.animateTo(0)
            } else {
                viewOffset = .static(offset: 0)
            }
            return
        }

        // pinned カラムがアクティブの場合はスクロール不要
        if columns[activeColumnIndex].isPinned { return }

        // pinned 領域の幅（非pinnedカラムのスクロール基点オフセット）
        let pinnedAreaWidth: CGFloat = columns.reduce(0) { acc, col in
            col.isPinned ? acc + col.width + gap : acc
        }

        // 非pinnedカラムのみ取り出してXを計算
        let nonPinnedCols = columns.filter { !$0.isPinned }
        guard !nonPinnedCols.isEmpty else { return }

        // アクティブカラムが非pinned内で何番目か
        var nonPinnedActiveIdx = 0
        var found = false
        var ni = 0
        for (i, col) in columns.enumerated() {
            if !col.isPinned {
                if i == activeColumnIndex {
                    nonPinnedActiveIdx = ni
                    found = true
                    break
                }
                ni += 1
            }
        }
        guard found else { return }

        // 非pinned カラム群の相対X座標
        var xs: [CGFloat] = []
        var x: CGFloat = 0
        for col in nonPinnedCols {
            xs.append(x)
            x += col.width + gap
        }

        let activeX = xs[nonPinnedActiveIdx]
        let activeWidth = nonPinnedCols[nonPinnedActiveIdx].width
        // 非pinnedカラムが使える実効幅（pinned 領域と leading gap を除いた残り）
        let effectiveWidth = workingArea.width - gap - pinnedAreaWidth
        let currentOffset = viewOffset.current

        // 1. アクティブカラムの現在のスクリーン上の位置（非pinned基点からの相対）
        let screenLeft  = activeX + currentOffset
        let screenRight = screenLeft + activeWidth

        // 2. 既に完全に収まっている場合でも、コンテンツ縮小で右側に空白が生じていればクランプ
        if screenLeft >= 0 && screenRight <= effectiveWidth {
            let lastX = xs.last! + nonPinnedCols.last!.width
            let minOffset = min(0, effectiveWidth - gap * 2 - lastX)
            if currentOffset < minOffset {
                if animated {
                    viewOffset.animateTo(minOffset)
                } else {
                    viewOffset = .static(offset: minOffset)
                }
            }
            return
        }

        // 3 & 4. 最小限スクロール
        let newOffset: CGFloat
        if screenLeft < 0 {
            newOffset = -activeX + gap
        } else {
            newOffset = -(activeX + activeWidth - effectiveWidth + gap)
        }

        // 5. クランプ
        let lastX = xs.last! + nonPinnedCols.last!.width
        let minOffset = min(0, effectiveWidth - gap * 2 - lastX)
        let clampedOffset = max(minOffset, min(0, newOffset))

        if animated {
            viewOffset.animateTo(clampedOffset)
        } else {
            viewOffset = .static(offset: clampedOffset)
        }
    }

    // MARK: - Column Operations

    mutating func addColumn(_ column: Column, at index: Int? = nil) {
        let wasAboveThreshold = columns.count > 3
        let insertIndex = index ?? (activeColumnIndex + 1)
        let safeIndex = min(max(insertIndex, 0), columns.count)
        columns.insert(column, at: safeIndex)
        activeColumnIndex = safeIndex
        // カラム数が Auto-Fit 閾値（3↔4）をまたいだ時だけ override をリセット。
        // 1〜3 の範囲内での追加では手動設定を尊重する。
        if wasAboveThreshold != (columns.count > 3) {
            autoFitOverridden = false
        }
    }

    mutating func removeColumn(at index: Int) {
        guard index < columns.count else { return }
        let wasActive = index == activeColumnIndex
        let wasAboveThreshold = columns.count > 3
        columns.remove(at: index)
        if wasAboveThreshold != (columns.count > 3) {
            autoFitOverridden = false
        }
        guard !columns.isEmpty else {
            activeColumnIndex = 0
            return
        }
        if wasActive {
            // 右優先: 削除後の同インデックス（右隣）、末尾超えなら最後（左隣）
            activeColumnIndex = min(index, columns.count - 1)
        } else if index < activeColumnIndex {
            // アクティブより前を削除 → インデックスをずらしてフォーカスを維持
            activeColumnIndex -= 1
        }
        // アクティブより後を削除 → 何もしない
    }

    mutating func focusColumn(at index: Int) {
        guard index >= 0, index < columns.count else { return }
        activeColumnIndex = index
    }

    mutating func focusLeft() {
        guard activeColumnIndex > 0 else { return }
        activeColumnIndex -= 1
    }

    mutating func focusRight() {
        guard activeColumnIndex < columns.count - 1 else { return }
        activeColumnIndex += 1
    }

    mutating func moveColumnLeft() {
        guard activeColumnIndex > 0 else { return }
        columns.swapAt(activeColumnIndex, activeColumnIndex - 1)
        activeColumnIndex -= 1
    }

    mutating func moveColumnRight() {
        guard activeColumnIndex < columns.count - 1 else { return }
        columns.swapAt(activeColumnIndex, activeColumnIndex + 1)
        activeColumnIndex += 1
    }

    /// 指定ウィンドウIDを含むカラムのインデックスを返す
    func columnIndex(for windowID: WindowID) -> Int? {
        columns.firstIndex { $0.windows.contains(windowID) }
    }

    /// 2つのウィンドウIDをスワップする（同一カラム内・異なるカラム間どちらも可）
    mutating func swapWindows(_ a: WindowID, _ b: WindowID) {
        guard a != b else { return }
        guard let (colA, winA) = findWindowPosition(a),
              let (colB, winB) = findWindowPosition(b) else { return }
        columns[colA].windows[winA] = b
        columns[colB].windows[winB] = a
        let widthA = columns[colA].width
        columns[colA].width = columns[colB].width
        columns[colB].width = widthA
    }

    // MARK: - Column Stack Operations

    /// consumeWindowIntoColumn で使うスタック挿入位置
    enum ColumnInsertPosition {
        case above  // target の直上に挿入
        case below  // target の直下に挿入
    }

    /// draggedID を targetID のカラムに position で挿入する。
    /// ソースカラムが空になれば削除する。同一カラム内の場合は何もしない。
    mutating func consumeWindowIntoColumn(
        _ draggedID: WindowID,
        target targetID: WindowID,
        position: ColumnInsertPosition
    ) {
        guard draggedID != targetID else { return }
        guard let draggedColIdx = columnIndex(for: draggedID),
              let targetColIdx  = columnIndex(for: targetID),
              draggedColIdx != targetColIdx
        else { return }

        // 1. draggedID をソースカラムから取り出す
        columns[draggedColIdx].removeWindow(draggedID)

        // 2. ソースカラムが空になったら削除し、targetColIdx を補正
        var adjustedTargetIdx = targetColIdx
        if columns[draggedColIdx].isEmpty {
            removeColumn(at: draggedColIdx)
            if draggedColIdx < targetColIdx {
                adjustedTargetIdx -= 1
            }
        }

        // 3. targetID のカラム内の現在インデックスを取得
        guard let targetWinIdx = columns[adjustedTargetIdx].windows.firstIndex(of: targetID) else { return }

        // 4. position に応じて挿入
        let insertIdx: Int
        switch position {
        case .above: insertIdx = targetWinIdx
        case .below: insertIdx = targetWinIdx + 1
        }
        let safeIdx = min(insertIdx, columns[adjustedTargetIdx].windows.count)
        columns[adjustedTargetIdx].windows.insert(draggedID, at: safeIdx)

        // 5. フォーカスをターゲットカラム・挿入したウィンドウに移す
        focusColumn(at: adjustedTargetIdx)
        if let newWinIdx = columns[adjustedTargetIdx].windows.firstIndex(of: draggedID) {
            columns[adjustedTargetIdx].activeWindowIndex = newWinIdx
        }
    }

    /// expelWindow で使う挿入位置
    enum ExpelInsertSide {
        case left   // 元カラムの左に新カラム挿入
        case right  // 元カラムの右に新カラム挿入
    }

    /// windowID を含むカラムから windowID を抜き出し、新しい1ウィンドウカラムとして挿入する。
    /// カラムに1ウィンドウしか無い場合、または windowID が見つからない場合は何もせず false を返す。
    /// 成功時は activeColumnIndex が新カラムを指す。
    @discardableResult
    mutating func expelWindow(
        _ windowID: WindowID,
        newColumnWidth: CGFloat,
        insertSide: ExpelInsertSide
    ) -> Bool {
        guard let srcColIdx = columnIndex(for: windowID),
              columns[srcColIdx].windows.count > 1
        else { return false }

        columns[srcColIdx].removeWindow(windowID)

        let insertIdx: Int
        switch insertSide {
        case .left:  insertIdx = srcColIdx
        case .right: insertIdx = srcColIdx + 1
        }

        let newColumn = Column(windows: [windowID], width: newColumnWidth)
        addColumn(newColumn, at: insertIdx)  // addColumn 内で activeColumnIndex = insertIdx
        return true
    }

    /// ウィンドウIDのカラムインデックスとウィンドウインデックスを返す
    private func findWindowPosition(_ id: WindowID) -> (colIdx: Int, winIdx: Int)? {
        for (colIdx, col) in columns.enumerated() {
            if let winIdx = col.windows.firstIndex(of: id) {
                return (colIdx, winIdx)
            }
        }
        return nil
    }

    /// 指定ウィンドウIDを全カラムから削除し、空になったカラムも削除
    mutating func removeWindow(_ id: WindowID) {
        for i in (0..<columns.count).reversed() {
            columns[i].removeWindow(id)
            if columns[i].isEmpty {
                removeColumn(at: i)
            }
        }
    }

    // MARK: - Scroll

    /// スクロール delta を viewOffset に適用する。
    /// - deltaX: 正 = 右スワイプ（macOS ナチュラルスクロール）→ viewOffset を負方向へ
    /// - sensitivity: 感度係数
    /// - isContinuous: true = トラックパッド（static 更新）、false = マウスホイール（アニメーション）
    mutating func applyScrollDelta(deltaX: CGFloat, sensitivity: CGFloat, isContinuous: Bool, gap: CGFloat = 16) {
        let delta = -deltaX * sensitivity   // 右スワイプ(+) → オフセット負方向

        let current = viewOffset.current
        let xs = columnXPositions(gap: gap)
        let lastX = (xs.last ?? 0) + (columns.last?.width ?? 0)
        let minOffset = min(0, workingArea.width - gap - lastX)
        let newOffset = max(minOffset, min(0, current + delta))

        if isContinuous {
            viewOffset = .static(offset: newOffset)
        } else {
            viewOffset.animateTo(newOffset)
        }
    }
}
