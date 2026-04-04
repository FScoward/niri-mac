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

    /// アクティブカラムが画面中央に来るよう viewOffset を更新
    ///
    /// 本家 niri の compute_new_view_offset に合わせた常時センタリング方式:
    /// - アクティブカラムを常に画面中央に配置する
    /// - 右端・左端クランプで画面外に出ないよう制限する
    mutating func recenterViewOffset(gap: CGFloat = 16, animated: Bool = true) {
        guard !columns.isEmpty, activeColumnIndex < columns.count else {
            if animated {
                viewOffset.animateTo(0)
            } else {
                viewOffset = .static(offset: 0)
            }
            return
        }

        let xs = columnXPositions(gap: gap)
        let activeX = xs[activeColumnIndex]
        let activeWidth = columns[activeColumnIndex].width
        let effectiveWidth = workingArea.width

        // センタリング: アクティブカラムの中心を画面中心に合わせる
        let target = -(activeX + activeWidth / 2 - effectiveWidth / 2)

        // 右端クランプ: 最終カラム右端が画面右端を超えないよう制限
        let lastX = xs.last! + columns.last!.width
        let minOffset = min(0, effectiveWidth - gap * 2 - lastX)

        // 左端クランプ: オフセットが正にならないよう制限
        let clampedOffset = max(minOffset, min(0, target))

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
        columns.remove(at: index)
        if activeColumnIndex >= columns.count {
            activeColumnIndex = max(0, columns.count - 1)
        }
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
