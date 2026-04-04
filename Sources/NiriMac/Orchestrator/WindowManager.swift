import AppKit
import CoreGraphics
import QuartzCore
import Foundation

private let logFileURL = URL(fileURLWithPath: "/tmp/niri-mac.log")
private let logFileHandle: FileHandle? = {
    if !FileManager.default.fileExists(atPath: logFileURL.path) {
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
    }
    return try? FileHandle(forWritingTo: logFileURL)
}()

private func niriLog(_ message: String) {
    let line = message + "\n"
    print(line, terminator: "")
    if let data = line.data(using: .utf8) {
        logFileHandle?.seekToEndOfFile()
        logFileHandle?.write(data)
    }
}

/// niri-mac のメインオーケストレーター。
/// イベントを受け取り、状態を更新し、レイアウトを適用する。
final class WindowManager {
    private var screens: [Screen] = []
    private var windowRegistry: [WindowID: WindowInfo] = [:]

    private let axBridge: AccessibilityBridge
    private let observer: AXObserverBridge
    private let keyboard: KeyboardShortcutManager
    private let mouse: MouseEventManager
    private let config: LayoutConfig
    private let spaceBridge = SpaceBridge()

    private var displayLink: CVDisplayLink?
    private var needsLayout: Bool = false

    /// park済みウィンドウのキャッシュ（毎フレームのSpaceAPI呼び出しを防ぐ）
    private var parkedWindowIDs: Set<WindowID> = []

    /// 前回のfrontmostApplication PID（setWindowFrame由来の誤発火を防ぐ）
    private var lastFrontmostPID: pid_t = 0

    /// onAppActivated のdebounceタイマー（setWindowFrame由来の連続通知を間引く）
    private var appActivatedDebounceTimer: Timer?

    /// applyLayout で計算した最新フレーム（マウスヒットテスト用）
    private var lastComputedFrames: [(WindowID, CGRect)] = []

    /// スクロールフォーカス移動のクールダウン（連打防止）
    private var lastScrollFocusTime: Date = .distantPast
    private let scrollFocusCooldown: TimeInterval = 0.3

    init(config: LayoutConfig = LayoutConfig()) {
        self.axBridge = AccessibilityBridge()
        self.observer = AXObserverBridge()
        self.keyboard = KeyboardShortcutManager()
        self.mouse = MouseEventManager()
        self.config = config
    }

    // MARK: - Startup

    func start() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let buildDate = Bundle.main.object(forInfoDictionaryKey: "BuildDate") as? String ?? "n/a"
        niriLog("[niri-mac] ========================================")
        niriLog("[niri-mac] version=\(version) build=\(build) date=\(buildDate)")
        niriLog("[niri-mac] ========================================")

        guard AccessibilityBridge.checkPermission() else {
            print("[niri-mac] Accessibility permission required.")
            print("[niri-mac] Go to System Settings > Privacy & Security > Accessibility")
            return
        }

        setupScreens()
        discoverExistingWindows()
        setupObserver()
        setupKeyboard()
        setupMouse()
        startDisplayLink()
        applyLayout(animated: false)

        print("[niri-mac] Started. Managing \(windowRegistry.count) windows.")
    }

    func stop() {
        keyboard.stop()
        mouse.stop()
        observer.stopObserving()
        stopDisplayLink()
    }

    // MARK: - Setup

    private func setupScreens() {
        // NSScreen は Cocoa 座標（左下原点・Y上向き）
        // AX API は Quartz 座標（左上原点・Y下向き）
        // ここで一度だけ Quartz に変換し、以降は全て Quartz 座標で統一する
        // メインスクリーン（メニューバーのある画面）のみ管理対象とする
        let mainH = NSScreen.screens.first?.frame.height ?? 0
        screens = NSScreen.screens.prefix(1).compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            let quartzFrame   = WindowManager.cocoaToQuartz(screen.frame, mainH: mainH)
            let quartzVisible = WindowManager.cocoaToQuartz(screen.visibleFrame, mainH: mainH)
            return Screen(id: id, frame: quartzFrame, visibleFrame: quartzVisible)
        }
        if screens.isEmpty {
            let mainH2 = NSScreen.main?.frame.height ?? 900
            let f  = NSScreen.main?.frame         ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            let vf = NSScreen.main?.visibleFrame   ?? CGRect(x: 0, y: 0, width: 1440, height: 877)
            screens = [Screen(
                id: CGMainDisplayID(),
                frame: WindowManager.cocoaToQuartz(f, mainH: mainH2),
                visibleFrame: WindowManager.cocoaToQuartz(vf, mainH: mainH2)
            )]
        }
    }

    /// Cocoa の CGRect → Quartz の CGRect に変換（メインスクリーン高さを基準）
    private static func cocoaToQuartz(_ rect: CGRect, mainH: CGFloat) -> CGRect {
        CGRect(x: rect.origin.x,
               y: mainH - rect.origin.y - rect.height,
               width: rect.width,
               height: rect.height)
    }

    private func discoverExistingWindows() {
        let windows = axBridge.allWindows()
        for window in windows {
            windowRegistry[window.id] = window
            assignWindowToScreen(window)
        }
        // 各スクリーンの先頭カラムにフォーカスして viewOffset を整合させる
        for i in screens.indices {
            if !screens[i].activeWorkspace.columns.isEmpty {
                screens[i].activeWorkspace.activeColumnIndex = 0
                screens[i].activeWorkspace.recenterViewOffset(gap: config.gapWidth, animated: false)
            }
        }
    }

    private func assignWindowToScreen(_ window: WindowInfo) {
        // window.frame も screen.frame も Quartz 座標で統一済み → そのまま比較できる
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)

        // 管理対象外スクリーン（サブモニタ）上のウィンドウはスキップ
        // ただし仮想スクロール空間（管理スクリーン右外）のウィンドウは screen[0] に割り当てる
        let mainH = NSScreen.screens.first?.frame.height ?? 0
        for nsScreen in NSScreen.screens.dropFirst() {
            let qf = WindowManager.cocoaToQuartz(nsScreen.frame, mainH: mainH)
            if qf.contains(center) {
                niriLog("[assign] '\(window.title)' はサブモニタのためスキップ")
                return
            }
        }

        let screenIndex = screens.firstIndex { $0.frame.contains(center) } ?? 0
        guard screenIndex < screens.count else { return }

        let screenWidth = screens[screenIndex].frame.width
        let colWidth = window.frame.width > 0 ? window.frame.width : config.defaultColumnWidth(for: screenWidth)
        let column = Column(windows: [window.id], width: colWidth)
        screens[screenIndex].workspaces[screens[screenIndex].activeWorkspaceIndex].addColumn(column)
    }

    private func setupObserver() {
        observer.onWindowCreated = { [weak self] window in
            self?.handleWindowCreated(window)
        }
        observer.onWindowDestroyed = { [weak self] id in
            self?.handleWindowDestroyed(id)
        }
        observer.onApplicationTerminated = { [weak self] pid in
            self?.handleApplicationTerminated(pid: pid)
        }
        observer.startObserving()
    }

    private func setupKeyboard() {
        keyboard.onAction = { [weak self] action in
            self?.handleAction(action)
        }
        keyboard.start()
    }

    private func setupMouse() {
        mouse.onMouseDown = { [weak self] point in
            self?.handleMouseFocus(at: point)
        }
        mouse.onScroll = { [weak self] deltaX, deltaY, isContinuous, flags in
            self?.handleScroll(deltaX: deltaX, deltaY: deltaY, isContinuous: isContinuous, flags: flags)
        }
        mouse.onAppActivated = { [weak self] in
            guard let self else { return }
            // setWindowFrame が毎フレーム発火させる連続通知を debounce で間引く
            // 実際の Cmd+Tab 等は 0.3秒後に1回だけ処理される
            self.appActivatedDebounceTimer?.invalidate()
            self.appActivatedDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                guard let self else { return }
                let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
                guard currentPID != self.lastFrontmostPID else {
                    niriLog("[mouse] onAppActivated(debounce): PID unchanged (\(currentPID)) — skip")
                    return
                }
                niriLog("[mouse] onAppActivated(debounce): PID changed \(self.lastFrontmostPID) → \(currentPID)")
                self.lastFrontmostPID = currentPID
                self.syncFocusFromFrontWindow()
            }
        }
        mouse.start()
    }

    // MARK: - Display Link (アニメーション駆動)

    private func startDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let link = displayLink else { return }

        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, userInfo -> CVReturn in
            guard let ptr = userInfo else { return kCVReturnSuccess }
            let wm = Unmanaged<WindowManager>.fromOpaque(ptr).takeUnretainedValue()
            wm.displayLinkTick()
            return kCVReturnSuccess
        }, selfPtr)

        CVDisplayLinkStart(link)
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
    }

    private func displayLinkTick() {
        // CVDisplayLink は専用スレッドから呼ばれるため、全処理をメインスレッドに委譲
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            var hasAnimation = false
            for screen in self.screens {
                if case .animating = screen.activeWorkspace.viewOffset {
                    hasAnimation = true
                    break
                }
            }

            // アニメーション完了チェック・settle
            for i in self.screens.indices {
                if self.screens[i].activeWorkspace.viewOffset.isSettled {
                    self.screens[i].activeWorkspace.viewOffset.settle()
                }
            }

            if hasAnimation || self.needsLayout {
                niriLog("[tick] applyLayout: hasAnimation=\(hasAnimation) needsLayout=\(self.needsLayout)")
                self.applyLayout(animated: false)
                self.needsLayout = false
            }
        }
    }

    // MARK: - Event Handlers

    private func handleWindowCreated(_ window: WindowInfo) {
        guard windowRegistry[window.id] == nil else { return }

        // windowRegistry に未登録のウィンドウのみ追加
        // (既存ウィンドウの再検出を防ぐ)
        windowRegistry[window.id] = window
        axBridge.registerElement(window.axElement, for: window.id)

        // screen.frame も Quartz 座標なのでそのまま比較
        guard !screens.isEmpty else { return }
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        // 管理対象外スクリーン（サブモニタ）上のウィンドウはスキップ
        let mainH2 = NSScreen.screens.first?.frame.height ?? 0
        for nsScreen in NSScreen.screens.dropFirst() {
            let qf = WindowManager.cocoaToQuartz(nsScreen.frame, mainH: mainH2)
            if qf.contains(center) {
                niriLog("[window] '\(window.title)' はサブモニタのためスキップ")
                return
            }
        }
        let screenIdx = screens.firstIndex { $0.frame.contains(center) } ?? 0
        let screenWidth = screens[screenIdx].frame.width
        let colWidth = window.frame.width > 0 ? window.frame.width : config.defaultColumnWidth(for: screenWidth)
        let column = Column(windows: [window.id], width: colWidth)
        screens[screenIdx].workspaces[screens[screenIdx].activeWorkspaceIndex].addColumn(column)
        screens[screenIdx].activeWorkspace.recenterViewOffset(gap: config.gapWidth)

        applyLayout()
        try? axBridge.focusWindow(window.id)

        print("[niri-mac] Window created: \(window.title) (\(window.id))")
    }

    private func handleWindowDestroyed(_ id: WindowID) {
        guard windowRegistry[id] != nil else { return }
        windowRegistry.removeValue(forKey: id)
        axBridge.removeElement(for: id)
        parkedWindowIDs.remove(id)

        for i in screens.indices {
            for j in screens[i].workspaces.indices {
                screens[i].workspaces[j].removeWindow(id)
            }
        }

        applyLayout()
        focusActiveWindow()

        print("[niri-mac] Window destroyed: \(id)")
    }

    private func handleApplicationTerminated(pid: pid_t) {
        // アプリ終了時に該当PIDのウィンドウを全て除去
        let toRemove = windowRegistry.values.filter { $0.ownerPID == pid }.map { $0.id }
        for id in toRemove {
            handleWindowDestroyed(id)
        }
    }

    func handleAction(_ action: KeyboardShortcutManager.Action) {
        let screenIdx = activeScreenIndex()
        guard screenIdx < screens.count else { return }

        switch action {
        case .focusLeft:
            niriLog("[action] focusLeft col=\(screens[screenIdx].activeWorkspace.activeColumnIndex)")
            screens[screenIdx].activeWorkspace.focusLeft()
            screens[screenIdx].activeWorkspace.recenterViewOffset(gap: config.gapWidth)
            niriLog("[action] focusLeft → col=\(screens[screenIdx].activeWorkspace.activeColumnIndex) offset→\(screens[screenIdx].activeWorkspace.viewOffset.target)")
            focusActiveWindow()

        case .focusRight:
            niriLog("[action] focusRight col=\(screens[screenIdx].activeWorkspace.activeColumnIndex)")
            screens[screenIdx].activeWorkspace.focusRight()
            screens[screenIdx].activeWorkspace.recenterViewOffset(gap: config.gapWidth)
            niriLog("[action] focusRight → col=\(screens[screenIdx].activeWorkspace.activeColumnIndex) offset→\(screens[screenIdx].activeWorkspace.viewOffset.target)")
            focusActiveWindow()

        case .focusUp:
            niriLog("[action] focusUp")
            screens[screenIdx].activeWorkspace.columns[
                screens[screenIdx].activeWorkspace.activeColumnIndex
            ].focusPrevious()
            focusActiveWindow()

        case .focusDown:
            niriLog("[action] focusDown")
            screens[screenIdx].activeWorkspace.columns[
                screens[screenIdx].activeWorkspace.activeColumnIndex
            ].focusNext()
            focusActiveWindow()

        case .moveColumnLeft:
            niriLog("[action] moveColumnLeft")
            screens[screenIdx].activeWorkspace.moveColumnLeft()
            screens[screenIdx].activeWorkspace.recenterViewOffset(gap: config.gapWidth)
            niriLog("[action] moveColumnLeft → col=\(screens[screenIdx].activeWorkspace.activeColumnIndex) offset→\(screens[screenIdx].activeWorkspace.viewOffset.target)")

        case .moveColumnRight:
            niriLog("[action] moveColumnRight")
            screens[screenIdx].activeWorkspace.moveColumnRight()
            screens[screenIdx].activeWorkspace.recenterViewOffset(gap: config.gapWidth)
            niriLog("[action] moveColumnRight → col=\(screens[screenIdx].activeWorkspace.activeColumnIndex) offset→\(screens[screenIdx].activeWorkspace.viewOffset.target)")

        case .switchWorkspaceUp:
            niriLog("[action] switchWorkspaceUp → ws=\(screens[screenIdx].activeWorkspaceIndex)")
            screens[screenIdx].switchToPreviousWorkspace()
            needsLayout = true
            focusActiveWindow()
            return

        case .switchWorkspaceDown:
            // 動的ワークスペース: 末尾に達したら新規作成
            if screens[screenIdx].activeWorkspaceIndex >= screens[screenIdx].workspaces.count - 1 {
                // visibleFrame を Quartz 変換して渡す
                let mainH = NSScreen.screens.first?.frame.height ?? 0
                let nsScreen = NSScreen.screens.first(where: {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == screens[screenIdx].id
                })
                let quartzVisible = nsScreen.map { WindowManager.cocoaToQuartz($0.visibleFrame, mainH: mainH) }
                    ?? screens[screenIdx].frame
                screens[screenIdx].addWorkspace(visibleFrame: quartzVisible)
            }
            screens[screenIdx].switchToNextWorkspace()
            needsLayout = true
            focusActiveWindow()
            return

        case .moveWindowToWorkspaceUp:
            niriLog("[action] moveWindowToWorkspaceUp")
            moveActiveWindowToWorkspace(screenIdx: screenIdx, direction: .up)
            return

        case .moveWindowToWorkspaceDown:
            niriLog("[action] moveWindowToWorkspaceDown")
            moveActiveWindowToWorkspace(screenIdx: screenIdx, direction: .down)
            return

        case .consumeIntoColumnLeft:
            niriLog("[action] consumeIntoColumnLeft")
            consumeWindowIntoColumn(screenIdx: screenIdx, direction: .left)

        case .consumeIntoColumnRight:
            niriLog("[action] consumeIntoColumnRight")
            consumeWindowIntoColumn(screenIdx: screenIdx, direction: .right)

        case .expelFromColumn:
            niriLog("[action] expelFromColumn")
            expelWindowFromColumn(screenIdx: screenIdx)

        case .cycleColumnWidth:
            let ws = screens[screenIdx].activeWorkspace
            guard !ws.columns.isEmpty else { return }
            let activeIdx = ws.activeColumnIndex
            let screenWidth = screens[screenIdx].frame.width
            let currentWidth = screens[screenIdx].activeWorkspace.columns[activeIdx].width
            let currentFraction = currentWidth / screenWidth
            let nextPreset: CGFloat
            if currentFraction < 0.4 {
                nextPreset = 1.0/2.0
            } else if currentFraction < 0.6 {
                nextPreset = 2.0/3.0
            } else {
                nextPreset = 1.0/3.0
            }
            niriLog("[action] cycleColumnWidth col=\(activeIdx) \(Int(currentWidth))→\(Int(screenWidth * nextPreset))px")
            screens[screenIdx].activeWorkspace.columns[activeIdx].width = screenWidth * nextPreset

        case .quit:
            stop()
            NSApplication.shared.terminate(nil)
            return
        }

        needsLayout = true
    }

    // MARK: - Layout Application

    private func applyLayout(animated: Bool = true) {
        var allFrames: [(WindowID, CGRect)] = []
        for (screenIdx, screen) in screens.enumerated() {
            let ws = screen.activeWorkspace
            niriLog("[layout] screen[\(screenIdx)] frame=\(screen.frame) workingArea=\(ws.workingArea) offset=\(ws.viewOffset.current) cols=\(ws.columns.count) activeCol=\(ws.activeColumnIndex)")
            let frames = LayoutEngine.computeWindowFrames(
                workspace: ws,
                screenFrame: screen.frame,
                config: config
            )
            allFrames.append(contentsOf: frames)

            // 駐車フォールバック用: 右端外の次の空き Y 座標
            let parkX = screen.frame.maxX + config.gapWidth
            var parkY = screen.frame.minY

            for (windowID, frame) in frames {
                let title = windowRegistry[windowID]?.title ?? "?"
                niriLog("[layout]   win=\(windowID) '\(title)' frame=\(frame) offScreen=\(isWindowOffScreen(frame, screen: screen))")
                applyWindowVisibility(windowID: windowID, frame: frame, screen: screen, parkX: parkX, parkY: &parkY)
            }
            _ = screenIdx  // suppress warning
        }
        lastComputedFrames = allFrames
    }

    /// 画面外判定: ウィンドウの中心(midX)が画面端を越えたら画面外とみなす（左右対称）
    private func isWindowOffScreen(_ frame: CGRect, screen: Screen) -> Bool {
        let isOffLeft  = frame.midX < screen.frame.minX
        let isOffRight = frame.midX >= screen.frame.maxX
        return isOffLeft || isOffRight
    }

    /// 画面内外に応じてウィンドウを完全非表示/復帰する。
    /// Space API（CGSAddWindowsToSpaces）は現環境で機能しないため、
    /// 画面外へのポジション移動で完全非表示を実現する。
    private func applyWindowVisibility(
        windowID: WindowID,
        frame: CGRect,
        screen: Screen,
        parkX: CGFloat,
        parkY: inout CGFloat
    ) {
        if isWindowOffScreen(frame, screen: screen) {
            // キャッシュ済みならスキップ（毎フレームのsetFrame呼び出しを防ぐ）
            if parkedWindowIDs.contains(windowID) { return }

            // 左右どちらに出ているかで完全非表示位置を決定
            let hiddenX: CGFloat
            if frame.midX < screen.frame.minX {
                // 左側: ウィンドウ全体が画面左端より外に出るよう移動
                hiddenX = screen.frame.minX - frame.width - 1
            } else {
                // 右側: ウィンドウ全体が画面右端より外に出るよう移動
                hiddenX = screen.frame.maxX + 1
            }
            let hiddenFrame = CGRect(x: hiddenX, y: frame.origin.y, width: frame.width, height: frame.height)
            parkedWindowIDs.insert(windowID)
            niriLog("[layout]   🅿️ hide win=\(windowID) → x=\(Int(hiddenX))")
            try? axBridge.setWindowFrame(windowID, frame: hiddenFrame)
        } else {
            // 画面内に戻った → キャッシュから除去して通常setFrame
            if parkedWindowIDs.contains(windowID) {
                parkedWindowIDs.remove(windowID)
                niriLog("[layout]   ↩️ show win=\(windowID)")
            }
            do {
                niriLog("[layout]   → setFrame win=\(windowID) → x=\(Int(frame.origin.x)) y=\(Int(frame.origin.y)) w=\(Int(frame.width)) h=\(Int(frame.height))")
                try axBridge.setWindowFrame(windowID, frame: frame)
                if let actual = axBridge.windowFrame(windowID) {
                    niriLog("[layout]   ✓ actual win=\(windowID) → x=\(Int(actual.origin.x)) y=\(Int(actual.origin.y)) w=\(Int(actual.width)) h=\(Int(actual.height))")
                    if abs(actual.origin.x - frame.origin.x) > 2 || abs(actual.origin.y - frame.origin.y) > 2 {
                        niriLog("[layout]   ⚠️ フレームずれ: 設定=\(frame.origin) 実際=\(actual.origin)")
                    }
                }
            } catch {
                niriLog("[layout]   ⚠️ setWindowFrame failed: \(error)")
            }
        }
    }

    private func focusActiveWindow() {
        let screenIdx = activeScreenIndex()
        guard screenIdx < screens.count,
              let windowID = screens[screenIdx].activeWorkspace.activeWindowID
        else { return }

        try? axBridge.focusWindow(windowID)

        // Feature 2: warp-mouse-to-focus
        // キーボード操作でフォーカスが移動した際、マウスカーソルをウィンドウ中央にワープ
        if config.warpMouseToFocus,
           let frame = lastComputedFrames.first(where: { $0.0 == windowID })?.1,
           frame.width > 0 {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            CGDisplayMoveCursorToPoint(screens[screenIdx].id, center)
        }
    }

    // MARK: - Mouse Handlers

    /// Feature 1: クリックでフォーカス同期
    /// クリック座標（Quartz）を lastComputedFrames と照合し activeColumnIndex を更新する
    private func handleMouseFocus(at point: CGPoint, updateViewOffset: Bool = true) {
        for (screenIdx, screen) in screens.enumerated() {
            guard screen.frame.contains(point) else { continue }
            let ws = screens[screenIdx].activeWorkspace

            // クリック座標がどのウィンドウに当たるか検索
            for (windowID, frame) in lastComputedFrames {
                guard frame.contains(point) else { continue }
                guard let colIdx = ws.columnIndex(for: windowID) else { continue }
                guard let winIdx = ws.columns[colIdx].windows.firstIndex(of: windowID) else { continue }

                // フォーカスが変わっていなければ何もしない（needsLayout=trueの無限ループを防ぐ）
                if ws.activeColumnIndex == colIdx && ws.columns[colIdx].activeWindowIndex == winIdx {
                    niriLog("[mouse] focus: no change win=\(windowID) col=\(colIdx) — skip")
                    return
                }

                // カラムフォーカスを更新
                screens[screenIdx].activeWorkspace.focusColumn(at: colIdx)

                // カラム内ウィンドウフォーカスを更新
                screens[screenIdx].activeWorkspace.columns[colIdx].activeWindowIndex = winIdx

                if updateViewOffset {
                    screens[screenIdx].activeWorkspace.recenterViewOffset(gap: config.gapWidth)
                }
                niriLog("[mouse] click focus: win=\(windowID) col=\(colIdx) offset→\(screens[screenIdx].activeWorkspace.viewOffset.target) updateViewOffset=\(updateViewOffset)")
                needsLayout = true
                return
            }
        }
    }

    /// Feature 3: トラックパッド / マウスホイールで水平スクロール
    /// Ctrl+Opt が押されている場合はカラムフォーカス移動に切り替え
    private func handleScroll(deltaX: CGFloat, deltaY: CGFloat, isContinuous: Bool, flags: NSEvent.ModifierFlags) {
        let screenIdx = activeScreenIndex()
        guard screenIdx < screens.count else { return }

        let filtered = flags.intersection([.control, .option])

        // Ctrl+Opt+スクロール → カラムフォーカス移動
        if filtered == [.control, .option] {
            let now = Date()
            guard now.timeIntervalSince(lastScrollFocusTime) >= scrollFocusCooldown else { return }
            lastScrollFocusTime = now

            let primary = abs(deltaY) >= abs(deltaX) ? deltaY : deltaX
            if primary > 0 {
                handleAction(.focusRight)
            } else if primary < 0 {
                handleAction(.focusLeft)
            }
            return
        }

        // 修飾キーなし → 水平ビュースクロール
        guard abs(deltaX) > 0.5 else { return }
        let sensitivity = isContinuous ? config.scrollSensitivity : config.mouseWheelScrollSensitivity
        let delta = -deltaX * sensitivity

        var ws = screens[screenIdx].activeWorkspace
        let current = ws.viewOffset.current
        let xs = ws.columnXPositions(gap: config.gapWidth)
        let lastX = (xs.last ?? 0) + (ws.columns.last?.width ?? 0)
        let minOffset = min(0, ws.workingArea.width - config.gapWidth - lastX)
        let newOffset = max(minOffset, min(0, current + delta))

        if isContinuous {
            // トラックパッド: 連続イベントのためアニメーション不要（即時反映で滑らか）
            ws.viewOffset = .static(offset: newOffset)
        } else {
            // マウスホイール: 離散イベントのためアニメーションで補間
            ws.viewOffset.animateTo(newOffset)
        }
        screens[screenIdx].activeWorkspace = ws
        needsLayout = true
    }

    /// Feature 1 補足: Cmd+Tab 等のアプリ切り替え時にフォーカス状態を同期
    private func syncFocusFromFrontWindow() {
        guard screenIndexForFrontWindow() != nil else { return }
        guard let quartzFrame = { () -> CGRect? in
            guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
            let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
            var ref: AnyObject?
            guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &ref) == .success,
                  let axWin = ref else { return nil }
            return WindowInfo.fetchFrame(from: axWin as! AXUIElement)
        }() else { return }

        let center = CGPoint(x: quartzFrame.midX, y: quartzFrame.midY)
        // Cmd+Tab等のアプリ切り替えではフォーカスのみ更新し、viewOffsetは変えない
        handleMouseFocus(at: center, updateViewOffset: false)
    }

    // MARK: - Helpers

    private func activeScreenIndex() -> Int {
        // 前面アプリのフォーカスウィンドウが属するスクリーンを優先
        if let idx = screenIndexForFrontWindow() {
            return idx
        }
        // フォールバック: マウス位置
        let mouseLocation = NSEvent.mouseLocation
        return screens.firstIndex { $0.frame.contains(mouseLocation) } ?? 0
    }

    /// 前面アプリのフォーカスウィンドウからスクリーンインデックスを取得
    private func screenIndexForFrontWindow() -> Int? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindowRef: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
              let axWindow = focusedWindowRef,
              let quartzFrame = WindowInfo.fetchFrame(from: axWindow as! AXUIElement) else { return nil }
        // screen.frame も Quartz 座標なのでそのまま比較
        let center = CGPoint(x: quartzFrame.midX, y: quartzFrame.midY)
        return screens.firstIndex { $0.frame.contains(center) }
    }

    private func moveActiveWindowToWorkspace(screenIdx: Int, direction: Direction) {
        guard let windowID = screens[screenIdx].activeWorkspace.activeWindowID else { return }
        let targetIdx: Int
        if direction == .up {
            targetIdx = screens[screenIdx].activeWorkspaceIndex - 1
        } else {
            targetIdx = screens[screenIdx].activeWorkspaceIndex + 1
        }
        guard targetIdx >= 0, targetIdx < screens[screenIdx].workspaces.count else { return }

        screens[screenIdx].activeWorkspace.removeWindow(windowID)

        let screenWidth = screens[screenIdx].frame.width
        let colWidth = (windowRegistry[windowID]?.frame.width ?? 0) > 0 ? windowRegistry[windowID]!.frame.width : config.defaultColumnWidth(for: screenWidth)
        let column = Column(windows: [windowID], width: colWidth)
        screens[screenIdx].workspaces[targetIdx].addColumn(column)

        needsLayout = true
    }

    private func consumeWindowIntoColumn(screenIdx: Int, direction: Direction) {
        var ws = screens[screenIdx].activeWorkspace
        let activeIdx = ws.activeColumnIndex

        let targetIdx: Int
        if direction == .left {
            targetIdx = activeIdx - 1
        } else {
            targetIdx = activeIdx + 1
        }

        guard targetIdx >= 0, targetIdx < ws.columns.count else { return }
        guard let windowID = ws.columns[activeIdx].activeWindowID else { return }

        // アクティブカラムからウィンドウを削除
        ws.columns[activeIdx].removeWindow(windowID)

        if ws.columns[activeIdx].isEmpty {
            // カラム削除後、targetIdx がずれる場合を補正
            // direction == .right のとき targetIdx = activeIdx + 1 だが、
            // activeIdx を削除すると targetIdx は activeIdx になる
            let adjustedTargetIdx = (direction == .left) ? targetIdx : activeIdx
            ws.removeColumn(at: activeIdx)
            let safeIdx = min(adjustedTargetIdx, ws.columns.count - 1)
            ws.focusColumn(at: safeIdx)
            ws.columns[safeIdx].windows.append(windowID)
        } else {
            // カラムは残るので targetIdx はそのまま有効
            ws.columns[targetIdx].windows.append(windowID)
            ws.focusColumn(at: targetIdx)
        }

        screens[screenIdx].activeWorkspace = ws
        needsLayout = true
    }

    private func expelWindowFromColumn(screenIdx: Int) {
        var ws = screens[screenIdx].activeWorkspace
        let activeIdx = ws.activeColumnIndex
        guard ws.columns[activeIdx].windows.count > 1,
              let windowID = ws.columns[activeIdx].activeWindowID
        else { return }

        ws.columns[activeIdx].removeWindow(windowID)
        let screenWidth = screens[screenIdx].frame.width
        let newColWidth = (windowRegistry[windowID]?.frame.width ?? 0) > 0 ? windowRegistry[windowID]!.frame.width : config.defaultColumnWidth(for: screenWidth)
        let newColumn = Column(windows: [windowID], width: newColWidth)
        ws.addColumn(newColumn, at: activeIdx + 1)
        screens[screenIdx].activeWorkspace = ws
        needsLayout = true
    }
}
