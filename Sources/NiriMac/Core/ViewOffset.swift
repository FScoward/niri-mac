import CoreFoundation
import QuartzCore

/// niri の ViewOffset に相当。スクロール位置の状態機械。
enum ViewOffset {
    case `static`(offset: CGFloat)
    case animating(from: CGFloat, to: CGFloat, startTime: CFTimeInterval, duration: CFTimeInterval)

    /// アニメーション完了後の目標値（アニメーション中も「到達予定位置」を返す）
    var target: CGFloat {
        switch self {
        case .static(let offset):
            return offset
        case .animating(_, let to, _, _):
            return to
        }
    }

    var current: CGFloat {
        switch self {
        case .static(let offset):
            return offset
        case .animating(let from, let to, let startTime, let duration):
            let elapsed = CACurrentMediaTime() - startTime
            let t = min(elapsed / duration, 1.0)
            let eased = easeOutCubic(t)
            return from + (to - from) * eased
        }
    }

    var isSettled: Bool {
        switch self {
        case .static:
            return true
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

    private func easeOutCubic(_ t: CGFloat) -> CGFloat {
        return 1 - pow(1 - t, 3)
    }
}
