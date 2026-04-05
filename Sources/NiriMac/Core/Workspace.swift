import CoreGraphics
import Foundation

/// niri の ScrollingSpace に相当。カラムの水平ストリップ + スクロール位置。
struct Workspace {
    let id: UUID
    var columns: [Column]
    var activeColumnIndex: Int
    var viewOffset: ViewOffset
    var workingArea: CGRect

    init(workingArea: CGRect) {
        self.id = UUID()
        self.columns = []
        self.activeColumnIndex = 0
        self.viewOffset = .static(offset: 0)
        self.workingArea = workingArea
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
        let insertIndex = index ?? (activeColumnIndex + 1)
        let safeIndex = min(max(insertIndex, 0), columns.count)
        columns.insert(column, at: safeIndex)
        activeColumnIndex = safeIndex
    }

    mutating func removeColumn(at index: Int) {
        guard index < columns.count else { return }
        let wasActive = index == activeColumnIndex
        columns.remove(at: index)
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
}
