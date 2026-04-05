import AppKit
import ApplicationServices

/// ウィンドウライフサイクルイベントを監視する。
final class AXObserverBridge {
    var onWindowCreated: ((WindowInfo) -> Void)?
    var onWindowDestroyed: ((WindowID) -> Void)?
    var onWindowMoved: ((WindowID, CGRect) -> Void)?
    var onWindowResized: ((WindowID, CGRect) -> Void)?
    var onApplicationLaunched: ((pid_t) -> Void)?
    var onApplicationTerminated: ((pid_t) -> Void)?

    private var observers: [pid_t: AXObserver] = [:]
    private var notificationCenter = NotificationCenter.default
    private var workspaceObservers: [Any] = []

    /// AXUIElement のハッシュ値 → WindowID マッピング
    /// kAXUIElementDestroyedNotification 発火時は要素が破棄済みのため
    /// _AXUIElementGetWindow が失敗する。登録時に事前保存して対応する。
    private var elementWindowMap: [CFHashCode: WindowID] = [:]

    func startObserving() {
        // 既存アプリを登録
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            registerObserver(for: app.processIdentifier)
        }

        // 新規アプリ起動/終了を監視
        let launched = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.registerObserver(for: app.processIdentifier)
            self?.onApplicationLaunched?(app.processIdentifier)
        }

        let terminated = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            self?.removeObserver(for: pid)
            self?.onApplicationTerminated?(pid)
        }

        workspaceObservers = [launched, terminated]
    }

    func stopObserving() {
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        observers.removeAll()
        elementWindowMap.removeAll()
    }

    private func registerObserver(for pid: pid_t) {
        guard observers[pid] == nil else { return }

        var observer: AXObserver?
        let result = AXObserverCreate(pid, axCallback, &observer)
        guard result == .success, let obs = observer else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        // アプリ要素レベルで登録する通知（kAXUIElementDestroyedNotification も含む）
        let appNotifications: [String] = [
            kAXWindowCreatedNotification as String,
            kAXUIElementDestroyedNotification as String,
            kAXWindowMovedNotification as String,
            kAXWindowResizedNotification as String,
        ]
        for notification in appNotifications {
            AXObserverAddNotification(obs, appElement, notification as CFString, selfPtr)
        }

        // 既存ウィンドウにも個別登録（windowID の事前マッピングを兼ねる）
        var windowList: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowList) == .success,
           let windows = windowList as? [AXUIElement] {
            for windowElement in windows {
                addDestroyedNotification(obs: obs, windowElement: windowElement, selfPtr: selfPtr)
            }
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observers[pid] = obs
    }

    /// 新規ウィンドウの破棄通知をウィンドウ要素に登録する（handleWindowCreated から呼ぶ）
    func registerWindowDestroyedNotification(for windowElement: AXUIElement, pid: pid_t) {
        guard let obs = observers[pid] else { return }
        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        addDestroyedNotification(obs: obs, windowElement: windowElement, selfPtr: selfPtr)
    }

    /// 破棄通知の登録と elementWindowMap への事前保存を行う
    private func addDestroyedNotification(obs: AXObserver, windowElement: AXUIElement, selfPtr: UnsafeMutableRawPointer) {
        // 事前にwindowIDを取得してマッピングに保存（可能な場合）
        var windowID: CGWindowID = 0
        if _AXUIElementGetWindow(windowElement, &windowID) == .success {
            elementWindowMap[CFHash(windowElement)] = windowID
        }
        // windowID取得の成否に関わらず通知を登録する
        AXObserverAddNotification(obs, windowElement, kAXUIElementDestroyedNotification as CFString, selfPtr)
    }

    private func removeObserver(for pid: pid_t) {
        observers.removeValue(forKey: pid)
    }

    fileprivate func handleNotification(observer: AXObserver, element: AXUIElement, notification: String) {
        let windowCreated = kAXWindowCreatedNotification as String
        let elementDestroyed = kAXUIElementDestroyedNotification as String
        let windowMoved = kAXWindowMovedNotification as String
        let windowResized = kAXWindowResizedNotification as String

        switch notification {
        case windowCreated:
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            if let info = WindowInfo(axElement: element, ownerPID: pid),
               WindowInfo.isManageable(axElement: element) {
                DispatchQueue.main.async { [weak self] in
                    self?.onWindowCreated?(info)
                }
            }

        case elementDestroyed:
            let hash = CFHash(element)
            if let windowID = elementWindowMap[hash] {
                // 事前保存したマッピングから取得（確実）
                elementWindowMap.removeValue(forKey: hash)
                DispatchQueue.main.async { [weak self] in
                    self?.onWindowDestroyed?(windowID)
                }
            } else {
                // フォールバック: 要素から直接取得を試みる
                var windowID: CGWindowID = 0
                if _AXUIElementGetWindow(element, &windowID) == .success {
                    DispatchQueue.main.async { [weak self] in
                        self?.onWindowDestroyed?(windowID)
                    }
                }
            }

        case windowMoved:
            var windowID: CGWindowID = 0
            if _AXUIElementGetWindow(element, &windowID) == .success,
               let frame = WindowInfo.fetchFrame(from: element) {
                DispatchQueue.main.async { [weak self] in
                    self?.onWindowMoved?(windowID, frame)
                }
            }

        case windowResized:
            var windowID: CGWindowID = 0
            if _AXUIElementGetWindow(element, &windowID) == .success,
               let frame = WindowInfo.fetchFrame(from: element) {
                DispatchQueue.main.async { [weak self] in
                    self?.onWindowResized?(windowID, frame)
                }
            }

        default:
            break
        }
    }
}

/// AXObserver のグローバルコールバック
private func axCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    userData: UnsafeMutableRawPointer?
) {
    guard let ptr = userData else { return }
    let bridge = Unmanaged<AXObserverBridge>.fromOpaque(ptr).takeUnretainedValue()
    bridge.handleNotification(observer: observer, element: element, notification: notification as String)
}
