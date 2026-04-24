import AppKit
import ApplicationServices
import CoreGraphics

protocol AccessibilityBridgeProtocol {
    func allWindows() -> [WindowInfo]
    func setWindowFrame(_ id: WindowID, frame: CGRect) throws
    func focusWindow(_ id: WindowID) throws
    func windowFrame(_ id: WindowID) -> CGRect?
}

enum AccessibilityError: Error {
    case permissionDenied
    case elementNotFound
    case attributeError(AXError)
    case invalidValue
}

final class AccessibilityBridge: AccessibilityBridgeProtocol {
    /// AXUIElement キャッシュ（WindowID -> AXUIElement）
    private var elementCache: [WindowID: AXUIElement] = [:]

    /// Accessibility 権限チェック
    static func checkPermission() -> Bool {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// 全実行中アプリのウィンドウを収集
    func allWindows() -> [WindowInfo] {
        var windows: [WindowInfo] = []
        elementCache.removeAll()

        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
        }

        for app in apps {
            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)

            var windowList: AnyObject?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowList) == .success,
                  let axWindows = windowList as? [AXUIElement]
            else { continue }

            for axWindow in axWindows {
                guard WindowInfo.isManageable(axElement: axWindow),
                      let info = WindowInfo(axElement: axWindow, ownerPID: pid)
                else { continue }

                windows.append(info)
                AXUIElementSetMessagingTimeout(axWindow, 0.5)
                elementCache[info.id] = axWindow
            }
        }

        return windows
    }

    /// ウィンドウの位置とサイズを設定
    /// - Parameter frame: Quartz座標系（左上原点・Y軸下向き）— LayoutEngine の出力をそのまま渡す
    func setWindowFrame(_ id: WindowID, frame: CGRect) throws {
        guard let element = elementCache[id] else {
            throw AccessibilityError.elementNotFound
        }

        // AX API も Quartz 座標系なのでそのまま設定する（座標変換不要）
        // サイズを先に設定（位置より先に設定しないとウィンドウが画面外に逃げることがある）
        var size = frame.size
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw AccessibilityError.invalidValue
        }
        let sizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        if sizeResult != .success && sizeResult != .cannotComplete {
            throw AccessibilityError.attributeError(sizeResult)
        }

        // 位置を設定
        var origin = frame.origin
        guard let positionValue = AXValueCreate(.cgPoint, &origin) else {
            throw AccessibilityError.invalidValue
        }
        let posResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        if posResult != .success && posResult != .cannotComplete {
            throw AccessibilityError.attributeError(posResult)
        }
    }

    /// ウィンドウにフォーカスを当てる
    func focusWindow(_ id: WindowID) throws {
        guard let element = elementCache[id] else {
            throw AccessibilityError.elementNotFound
        }

        // ウィンドウを前面に
        let raiseResult = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        if raiseResult != .success {
            // 失敗しても継続
        }

        // アプリをアクティブ化
        var pidValue: pid_t = 0
        AXUIElementGetPid(element, &pidValue)
        if let app = NSRunningApplication(processIdentifier: pidValue) {
            app.activate(options: [.activateIgnoringOtherApps])
        }

        // フォーカスを設定
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    /// ウィンドウの現在フレームを取得
    func windowFrame(_ id: WindowID) -> CGRect? {
        guard let element = elementCache[id] else { return nil }
        return WindowInfo.fetchFrame(from: element)
    }

    /// AXUIElement を elementCache に登録
    func registerElement(_ element: AXUIElement, for id: WindowID) {
        // AXUIElementSetAttributeValue がメインスレッドをブロックする時間を制限する。
        // デフォルト(~6秒)のままだと tapDisabledByTimeout が発生してクリックが届かなくなる。
        AXUIElementSetMessagingTimeout(element, 0.5)
        elementCache[id] = element
    }

    func removeElement(for id: WindowID) {
        elementCache.removeValue(forKey: id)
    }

    /// AXUIElement を返す（CGWindowID 取得用）
    func element(for id: WindowID) -> AXUIElement? {
        elementCache[id]
    }
}
