import AppKit
import CoreGraphics

/// AXUIElement をラップし、ウィンドウの情報を保持する。
struct WindowInfo: Identifiable {
    let id: WindowID
    let axElement: AXUIElement
    let ownerPID: pid_t
    let ownerBundleID: String?
    var title: String
    var frame: CGRect
    var isMinimized: Bool
    var isFullscreen: Bool

    init?(axElement: AXUIElement, ownerPID: pid_t) {
        self.axElement = axElement
        self.ownerPID = ownerPID

        // ウィンドウIDを取得
        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(axElement, &windowID) == .success else { return nil }
        self.id = windowID

        // バンドルIDを取得
        if let app = NSRunningApplication(processIdentifier: ownerPID) {
            self.ownerBundleID = app.bundleIdentifier
        } else {
            self.ownerBundleID = nil
        }

        // タイトルを取得
        var titleValue: AnyObject?
        AXUIElementCopyAttributeValue(axElement, kAXTitleAttribute as CFString, &titleValue)
        self.title = (titleValue as? String) ?? ""

        // フレームを取得
        self.frame = WindowInfo.fetchFrame(from: axElement) ?? .zero

        // 最小化状態
        var minimizedValue: AnyObject?
        AXUIElementCopyAttributeValue(axElement, kAXMinimizedAttribute as CFString, &minimizedValue)
        self.isMinimized = (minimizedValue as? Bool) ?? false

        // フルスクリーン状態
        var fullscreenValue: AnyObject?
        AXUIElementCopyAttributeValue(axElement, "AXFullscreen" as CFString, &fullscreenValue)
        self.isFullscreen = (fullscreenValue as? Bool) ?? false
    }

    static func fetchFrame(from element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }

        return CGRect(origin: position, size: size)
    }

    /// 管理対象かどうか判定（デスクトップ、メニューバー等を除外）
    static func isManageable(axElement: AXUIElement) -> Bool {
        var roleValue: AnyObject?
        var subroleValue: AnyObject?

        AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleValue)
        AXUIElementCopyAttributeValue(axElement, kAXSubroleAttribute as CFString, &subroleValue)

        let role = roleValue as? String
        let subrole = subroleValue as? String

        guard role == kAXWindowRole as String else { return false }

        // 標準ウィンドウのみ管理対象
        if let s = subrole, s == kAXStandardWindowSubrole as String {
            return true
        }
        // サブロールがない場合も管理対象とする
        if subrole == nil || subrole == "" {
            return true
        }
        return false
    }
}
