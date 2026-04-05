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
        let wasActive = idx == activeWindowIndex
        windows.remove(at: idx)
        guard !windows.isEmpty else { return }
        if wasActive {
            // 右優先: 削除後の同インデックス（右隣）、末尾超えなら最後（左隣）
            activeWindowIndex = min(idx, windows.count - 1)
        } else if idx < activeWindowIndex {
            // アクティブより前を削除 → インデックスをずらしてフォーカスを維持
            activeWindowIndex -= 1
        }
        // アクティブより後を削除 → 何もしない
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
