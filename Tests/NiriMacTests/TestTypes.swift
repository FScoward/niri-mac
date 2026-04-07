// TestTypes.swift
// テストで共有する型定義（executableTarget は @testable import できないため再定義）

import CoreGraphics
import CoreFoundation
import QuartzCore
import Foundation

// MARK: - WindowID
typealias WindowID = UInt32

// MARK: - ViewOffset

enum ViewOffset {
    case `static`(offset: CGFloat)
    case animating(from: CGFloat, to: CGFloat, startTime: CFTimeInterval, duration: CFTimeInterval)

    var target: CGFloat {
        switch self {
        case .static(let offset): return offset
        case .animating(_, let to, _, _): return to
        }
    }

    var current: CGFloat {
        switch self {
        case .static(let offset): return offset
        case .animating(let from, let to, let startTime, let duration):
            let elapsed = CACurrentMediaTime() - startTime
            let t = min(elapsed / duration, 1.0)
            let eased = 1 - pow(1 - t, 3)
            return from + (to - from) * eased
        }
    }

    var isSettled: Bool {
        switch self {
        case .static: return true
        case .animating(_, _, let startTime, let duration):
            return (CACurrentMediaTime() - startTime) >= duration
        }
    }

    mutating func settle() {
        let v = current
        self = .static(offset: v)
    }

    mutating func animateTo(_ target: CGFloat, duration: CFTimeInterval = 0.25) {
        let currentValue = current
        if abs(currentValue - target) < 0.5 {
            self = .static(offset: target)
            return
        }
        self = .animating(from: currentValue, to: target, startTime: CACurrentMediaTime(), duration: duration)
    }
}

// MARK: - HeightDistribution

enum HeightDistribution {
    case equal
    case proportional([CGFloat])
}

// MARK: - Column

struct Column {
    var windows: [WindowID]
    var activeWindowIndex: Int
    var width: CGFloat
    var heightDistribution: HeightDistribution
    var isPinned: Bool

    init(windows: [WindowID], width: CGFloat) {
        self.windows = windows
        self.activeWindowIndex = 0
        self.width = width
        self.heightDistribution = .equal
        self.isPinned = false
    }

    var activeWindowID: WindowID? {
        guard !windows.isEmpty, activeWindowIndex < windows.count else { return nil }
        return windows[activeWindowIndex]
    }

    var isEmpty: Bool { windows.isEmpty }

    mutating func moveActiveWindowUp() {
        guard activeWindowIndex > 0 else { return }
        let i = activeWindowIndex
        windows.swapAt(i, i - 1)
        if case .proportional(var ratios) = heightDistribution, ratios.count == windows.count {
            ratios.swapAt(i, i - 1)
            heightDistribution = .proportional(ratios)
        }
        activeWindowIndex = i - 1
    }

    mutating func moveActiveWindowDown() {
        guard activeWindowIndex < windows.count - 1 else { return }
        let i = activeWindowIndex
        windows.swapAt(i, i + 1)
        if case .proportional(var ratios) = heightDistribution, ratios.count == windows.count {
            ratios.swapAt(i, i + 1)
            heightDistribution = .proportional(ratios)
        }
        activeWindowIndex = i + 1
    }

    mutating func resizeActiveWindowHeight(delta: CGFloat) {
        let n = windows.count
        guard n >= 2 else { return }

        var ratios: [CGFloat]
        if case .proportional(let r) = heightDistribution, r.count == n {
            let sum = r.reduce(0, +)
            ratios = sum > 0 ? r.map { $0 / sum } : Array(repeating: 1.0 / CGFloat(n), count: n)
        } else {
            ratios = Array(repeating: 1.0 / CGFloat(n), count: n)
        }

        let i = activeWindowIndex
        let minRatio: CGFloat = 0.05
        let maxRatio: CGFloat = 1.0 - CGFloat(n - 1) * minRatio
        ratios[i] = max(minRatio, min(maxRatio, ratios[i] + delta))

        let remaining = 1.0 - ratios[i]
        let otherSum = ratios.enumerated().filter { $0.offset != i }.map { $0.element }.reduce(0, +)
        for j in 0..<n where j != i {
            if otherSum > 0 {
                ratios[j] = max(minRatio, remaining * ratios[j] / otherSum)
            } else {
                ratios[j] = remaining / CGFloat(n - 1)
            }
        }

        let total = ratios.reduce(0, +)
        if total > 0 { ratios = ratios.map { $0 / total } }
        heightDistribution = .proportional(ratios)
    }
}

// MARK: - Workspace

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

    func columnXPositions(gap: CGFloat = 16) -> [CGFloat] {
        var xs: [CGFloat] = []
        var x: CGFloat = 0
        for col in columns {
            xs.append(x)
            x += col.width + gap
        }
        return xs
    }

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
        let currentOffset = viewOffset.current

        let screenLeft  = activeX + currentOffset
        let screenRight = screenLeft + activeWidth

        if screenLeft >= 0 && screenRight <= effectiveWidth {
            return
        }

        let newOffset: CGFloat
        if screenLeft < 0 {
            newOffset = -activeX + gap
        } else {
            newOffset = -(activeX + activeWidth - effectiveWidth + gap)
        }

        let lastX = xs.last! + columns.last!.width
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
            activeColumnIndex = min(index, columns.count - 1)
        } else if index < activeColumnIndex {
            activeColumnIndex -= 1
        }
    }

    mutating func focusColumn(at index: Int) {
        guard index >= 0, index < columns.count else { return }
        activeColumnIndex = index
    }

    func columnIndex(for windowID: WindowID) -> Int? {
        columns.firstIndex { $0.windows.contains(windowID) }
    }

    // MARK: - Column Stack Operations

    enum ColumnInsertPosition {
        case above
        case below
    }

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

        columns[draggedColIdx].windows.removeAll { $0 == draggedID }

        var adjustedTargetIdx = targetColIdx
        if columns[draggedColIdx].isEmpty {
            removeColumn(at: draggedColIdx)
            if draggedColIdx < targetColIdx {
                adjustedTargetIdx -= 1
            }
        }

        guard let targetWinIdx = columns[adjustedTargetIdx].windows.firstIndex(of: targetID) else { return }

        let insertIdx: Int
        switch position {
        case .above: insertIdx = targetWinIdx
        case .below: insertIdx = targetWinIdx + 1
        }
        let safeIdx = min(insertIdx, columns[adjustedTargetIdx].windows.count)
        columns[adjustedTargetIdx].windows.insert(draggedID, at: safeIdx)

        focusColumn(at: adjustedTargetIdx)
        if let newWinIdx = columns[adjustedTargetIdx].windows.firstIndex(of: draggedID) {
            columns[adjustedTargetIdx].activeWindowIndex = newWinIdx
        }
    }

    var activeWindowID: WindowID? {
        guard !columns.isEmpty, activeColumnIndex < columns.count else { return nil }
        return columns[activeColumnIndex].activeWindowID
    }
}

// MARK: - LayoutConfig

struct LayoutConfig {
    var gapWidth: CGFloat = 16
    var gapHeight: CGFloat = 16
    var defaultColumnWidthFraction: CGFloat = 1.0 / 3.0
    var animationDuration: CFTimeInterval = 0.25
}

// MARK: - LayoutEngine

enum LayoutEngine {
    static func columnXPositions(columns: [Column], gap: CGFloat, startX: CGFloat = 0) -> [CGFloat] {
        var xs: [CGFloat] = []
        var x = startX
        for col in columns {
            xs.append(x)
            x += col.width + gap
        }
        return xs
    }

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

    static func computeWindowFrames(workspace: Workspace, screenFrame: CGRect, config: LayoutConfig) -> [(WindowID, CGRect)] {
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
                let screenY = workingArea.minY + winY
                let frame = CGRect(x: screenX, y: screenY, width: column.width, height: winHeight)
                results.append((windowID, frame))
            }
        }

        return results
    }

    /// isWindowOffScreen: 仕様書 R-01
    static func isWindowOffScreen(_ frame: CGRect, workingArea: CGRect) -> Bool {
        return frame.maxX <= workingArea.minX || frame.minX >= workingArea.maxX
    }

    static func nearestGapIndex(
        cursorX: CGFloat,
        workspace: Workspace,
        config: LayoutConfig
    ) -> Int {
        let gap = config.gapWidth
        let xs = workspace.columnXPositions(gap: gap)
        let offset = workspace.viewOffset.current
        let workingMinX = workspace.workingArea.minX

        var gapPositions: [CGFloat] = []
        gapPositions.append(workingMinX + gap / 2)

        for (i, col) in workspace.columns.enumerated() {
            let colScreenX = workingMinX + gap + xs[i] + offset
            let colRightX = colScreenX + col.width
            gapPositions.append(colRightX + gap / 2)
        }

        var nearestIdx = 0
        var minDist = CGFloat.greatestFiniteMagnitude
        for (i, gapX) in gapPositions.enumerated() {
            let dist = abs(cursorX - gapX)
            if dist < minDist { minDist = dist; nearestIdx = i }
        }
        return nearestIdx
    }
}
