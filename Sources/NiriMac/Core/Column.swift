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

    /// アクティブウィンドウを1つ上へ移動（先頭なら何もしない）
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

    /// アクティブウィンドウを1つ下へ移動（末尾なら何もしない）
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

    /// アクティブウィンドウの高さ比率を delta 分だけ増減する。
    /// 残りのウィンドウから比例的に差し引く / 追加する。
    /// - delta は normalized 値（例: +0.10 で 10% 増）
    /// - 各ウィンドウの比率は最小 0.05 を保証
    mutating func resizeActiveWindowHeight(delta: CGFloat) {
        let n = windows.count
        guard n >= 2 else { return }

        // 現在の比率を取得（.equal もしくはカウント不一致の場合は等分で初期化）
        var ratios: [CGFloat]
        if case .proportional(let r) = heightDistribution, r.count == n {
            let sum = r.reduce(0, +)
            ratios = sum > 0 ? r.map { $0 / sum } : Array(repeating: 1.0 / CGFloat(n), count: n)
        } else {
            ratios = Array(repeating: 1.0 / CGFloat(n), count: n)
        }

        let i = activeWindowIndex
        let minRatio: CGFloat = 0.05
        // active の最大比率は残り全ウィンドウが minRatio を確保できる上限
        let maxRatio: CGFloat = 1.0 - CGFloat(n - 1) * minRatio

        // active を増減（上下限クランプ）
        ratios[i] = max(minRatio, min(maxRatio, ratios[i] + delta))

        // 残り比率を他ウィンドウで現在の比率に比例配分（最小保証あり）
        let remaining = 1.0 - ratios[i]
        let otherSum = ratios.enumerated().filter { $0.offset != i }.map { $0.element }.reduce(0, +)
        for j in 0..<n where j != i {
            if otherSum > 0 {
                ratios[j] = max(minRatio, remaining * ratios[j] / otherSum)
            } else {
                ratios[j] = remaining / CGFloat(n - 1)
            }
        }

        // 最終正規化（クランプ後の誤差を吸収）
        let total = ratios.reduce(0, +)
        if total > 0 {
            ratios = ratios.map { $0 / total }
        }

        heightDistribution = .proportional(ratios)
    }
}
