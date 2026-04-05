import CoreGraphics

enum HeightDistribution {
    case equal
    case proportional([CGFloat])
}

/// niri の Column に相当。1列に縦積みされるウィンドウ群。
struct Column {
    var windows: [WindowID]
    var activeWindowIndex: Int
    var width: CGFloat
    var heightDistribution: HeightDistribution
    /// true の場合、スクロールに関わらず画面左側に固定表示される
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

    mutating func removeWindow(_ id: WindowID) {
        guard let idx = windows.firstIndex(of: id) else { return }
        windows.remove(at: idx)
        if activeWindowIndex >= windows.count {
            activeWindowIndex = max(0, windows.count - 1)
        }
    }

    mutating func focusNext() {
        guard windows.count > 1 else { return }
        activeWindowIndex = (activeWindowIndex + 1) % windows.count
    }

    mutating func focusPrevious() {
        guard windows.count > 1 else { return }
        activeWindowIndex = (activeWindowIndex - 1 + windows.count) % windows.count
    }
}
