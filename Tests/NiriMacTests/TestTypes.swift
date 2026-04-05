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

    init(windows: [WindowID], width: CGFloat) {
        self.windows = windows
        self.activeWindowIndex = 0
        self.width = width
        self.heightDistribution = .equal
    }

    var activeWindowID: WindowID? {
        guard !windows.isEmpty, activeWindowIndex < windows.count else { return nil }
        return windows[activeWindowIndex]
    }

    var isEmpty: Bool { windows.isEmpty }
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
}
