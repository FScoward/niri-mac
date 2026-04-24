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
private let logQueue = DispatchQueue(label: "niri-mac.log", qos: .utility)

private func niriLog(_ message: String) {
    let line = message + "\n"
    print(line, terminator: "")
    logQueue.async {
        if let data = line.data(using: .utf8) {
            logFileHandle?.seekToEndOfFile()
            logFileHandle?.write(data)
        }
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
    private var config: LayoutConfig
    private let focusOverlayManager = FocusOverlayManager()
    private let dropTargetOverlay = DropTargetOverlayManager()
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

    /// applyLayout 完了後にフォーカスを当てるフラグ（ワークスペース切り替え時に使用）
    private var focusAfterLayout: Bool = false

    /// スクロールフォーカス移動のクールダウン（連打防止）
    private var lastScrollFocusTime: Date = .distantPast
    private let scrollFocusCooldown: TimeInterval = 0.3

    /// マウスボタンが押されているかどうか
    private var isMouseDown: Bool = false

    /// MouseDown 時にクリックしたウィンドウIDと元フレーム（移動距離判定用）
    private var mouseDownWindowID: WindowID? = nil
    private var mouseDownFrame: CGRect? = nil

    /// ドラッグ中のウィンドウID（移動距離 > 閾値 になったら確定）
    private var draggedWindowID: WindowID? = nil

    /// ドラッグ判定の移動距離閾値（px）
    private let dragThreshold: CGFloat = 20

    /// スワップ直後のクールダウン終了時刻（applyLayout 由来の windowMoved 誤検知を防ぐ）
    private var swapCooldownEnd: Date = .distantPast

    /// 最後に検知したスペースID（同一スペースの重複処理を防ぐ）
    private var lastKnownSpaceID: UInt64? = nil

    /// スペース切り替えのデバウンスタイマー
    private var spaceChangedDebounceTimer: Timer? = nil

    /// 画面変更のデバウンスタイマー
    private var screenChangeDebounceTimer: Timer?

    /// didChangeScreenParametersNotification のオブザーバートークン
    private var screenParametersObserver: NSObjectProtocol?

    /// macOSスペースごとのビュー状態
    private struct SpaceState {
        var columns: [Column]
        var activeColumnIndex: Int
        var viewOffset: CGFloat
    }

    /// スペースIDをキーに状態を記憶
    private var spaceStates: [UInt64: SpaceState] = [:]

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

        // 除外アプリ設定を読み込む
        config.excludedBundleIDs = ExclusionStore.load()
        niriLog("[exclusion] loaded \(config.excludedBundleIDs.count) excluded apps: \(config.excludedBundleIDs.sorted())")

        setupScreens()
        discoverExistingWindows()
        lastKnownSpaceID = spaceBridge.currentSpaceID()
        niriLog("[space-sync] initial spaceID=\(lastKnownSpaceID.map { String($0) } ?? "nil")")
        setupObserver()
        setupKeyboard()
        setupMouse()
        startDisplayLink()
        applyLayout(animated: false)

        print("[niri-mac] Started. Managing \(windowRegistry.count) windows.")
    }

    func stop() {
        focusOverlayManager.removeAll()
        keyboard.stop()
        mouse.stop()
        observer.stopObserving()
        screenChangeDebounceTimer?.invalidate()
        screenChangeDebounceTimer = nil
        if let obs = screenParametersObserver {
            NotificationCenter.default.removeObserver(obs)
            screenParametersObserver = nil
        }
        appActivatedDebounceTimer?.invalidate()
        appActivatedDebounceTimer = nil
        spaceChangedDebounceTimer?.invalidate()
        spaceChangedDebounceTimer = nil
        stopDisplayLink()
    }

    // MARK: - App Exclusion

    private func isExcluded(_ window: WindowInfo) -> Bool {
        guard let bundleID = window.ownerBundleID else { return false }
        return config.excludedBundleIDs.contains(bundleID)
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

    private func refreshScreenGeometry() {
        let mainH = NSScreen.screens.first?.frame.height ?? 0
        for i in screens.indices {
            guard let nsScreen = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == screens[i].id
            }) else { continue }
            let quartzFrame   = WindowManager.cocoaToQuartz(nsScreen.frame, mainH: mainH)
            let quartzVisible = WindowManager.cocoaToQuartz(nsScreen.visibleFrame, mainH: mainH)
            screens[i].frame = quartzFrame
            for j in screens[i].workspaces.indices {
                screens[i].workspaces[j].workingArea = quartzVisible
            }
        }
        niriLog("[screen] geometry refreshed: \(screens.map { "id=\($0.id) size=\($0.frame.size)" }.joined(separator: ", "))")
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
            guard !isExcluded(window) else {
                niriLog("[exclusion] skip '\(window.ownerBundleID ?? "?")'  windowID=\(window.id)")
                continue
            }
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

    private func syncWindowsForCurrentSpace() {
        guard let currentSpaceID = spaceBridge.currentSpaceID() else {
            niriLog("[space-sync] currentSpaceID() returned nil — skip")
            return
        }
        guard currentSpaceID != lastKnownSpaceID else { return }

        niriLog("[space-sync] spaceID changed: \(lastKnownSpaceID.map { String($0) } ?? "nil") → \(currentSpaceID)")

        // 離脱前のスペース状態をcolumnsごと保存
        if let previousSpaceID = lastKnownSpaceID {
            for screen in screens {
                let ws = screen.activeWorkspace
                spaceStates[previousSpaceID] = SpaceState(
                    columns: ws.columns,
                    activeColumnIndex: ws.activeColumnIndex,
                    viewOffset: ws.viewOffset.current
                )
            }
            niriLog("[space-sync] saved state for spaceID=\(previousSpaceID)")
        }

        lastKnownSpaceID = currentSpaceID

        let freshWindows = axBridge.allWindows()

        // 現在のスペースに属するウィンドウIDを特定
        var currentSpaceWindowIDs: Set<WindowID> = []
        for window in freshWindows {
            let spaces = spaceBridge.spacesForWindow(windowID: window.id)
            if spaces.contains(currentSpaceID) {
                currentSpaceWindowIDs.insert(window.id)
            }
        }
        niriLog("[space-sync] currentSpace windows: \(currentSpaceWindowIDs.sorted())")

        for i in screens.indices {
            if let saved = spaceStates[currentSpaceID] {
                // 保存済みカラム配置を復元（存在しないウィンドウをフィルタ）
                var restoredColumns = saved.columns.compactMap { col -> Column? in
                    let validWindows = col.windows.filter { currentSpaceWindowIDs.contains($0) }
                    guard !validWindows.isEmpty else { return nil }
                    var newCol = col
                    newCol.windows = validWindows
                    newCol.activeWindowIndex = min(col.activeWindowIndex, validWindows.count - 1)
                    return newCol
                }

                // 保存済みカラムに含まれていない新規ウィンドウを末尾に追加
                let savedWindowIDs = Set(restoredColumns.flatMap { $0.windows })
                let newWindowIDs = currentSpaceWindowIDs.subtracting(savedWindowIDs)
                for window in freshWindows where newWindowIDs.contains(window.id) {
                    guard !isExcluded(window) else { continue }
                    windowRegistry[window.id] = window
                    axBridge.registerElement(window.axElement, for: window.id)
                    let col = Column(windows: [window.id], width: window.frame.width)
                    restoredColumns.append(col)
                    niriLog("[space-sync] added new window to layout: \(window.id)")
                }

                screens[i].workspaces[screens[i].activeWorkspaceIndex].columns = restoredColumns
                let safeIdx = min(saved.activeColumnIndex, max(0, restoredColumns.count - 1))
                screens[i].workspaces[screens[i].activeWorkspaceIndex].activeColumnIndex = safeIdx
                screens[i].workspaces[screens[i].activeWorkspaceIndex].viewOffset = .static(offset: saved.viewOffset)
                niriLog("[space-sync] restored state for spaceID=\(currentSpaceID) offset=\(saved.viewOffset) col=\(safeIdx)")
            } else {
                // 初回訪問: レイアウトをクリアして再構築
                screens[i].workspaces[screens[i].activeWorkspaceIndex].columns = []
                screens[i].workspaces[screens[i].activeWorkspaceIndex].activeColumnIndex = 0
                for window in freshWindows where currentSpaceWindowIDs.contains(window.id) {
                    guard !isExcluded(window) else { continue }
                    windowRegistry[window.id] = window
                    axBridge.registerElement(window.axElement, for: window.id)
                    assignWindowToScreen(window)
                }
                screens[i].workspaces[screens[i].activeWorkspaceIndex].recenterViewOffset(gap: config.gapWidth, animated: false)
                niriLog("[space-sync] first visit spaceID=\(currentSpaceID) — recentered")
            }
        }

        parkedWindowIDs.removeAll()
        applyLayout(animated: false)
        activateWindow()  // スペース切り替えはマウス操作起点 → カーソル移動しない

        niriLog("[space-sync] layout applied (\(currentSpaceWindowIDs.count) windows)")
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

    private func handleScreenParametersChanged() {
        screenChangeDebounceTimer?.invalidate()
        screenChangeDebounceTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            niriLog("[screen] screen parameters changed, refreshing layout")
            self.refreshScreenGeometry()
            self.needsLayout = true
        }
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
        observer.onWindowResized = { [weak self] windowID, newFrame in
            guard let self else { return }
            // applyLayout の setWindowFrame が誤発火させる通知を防ぐ
            // ユーザーがマウスでドラッグ中のみ受け付ける
            guard self.isMouseDown else { return }
            for screenIdx in screens.indices {
                for wsIdx in screens[screenIdx].workspaces.indices {
                    for colIdx in screens[screenIdx].workspaces[wsIdx].columns.indices {
                        if screens[screenIdx].workspaces[wsIdx].columns[colIdx].windows.contains(windowID) {
                            let newWidth = newFrame.width
                            niriLog("[window] resized: win=\(windowID) newWidth=\(Int(newWidth))px")
                            screens[screenIdx].workspaces[wsIdx].columns[colIdx].width = newWidth
                            // needsLayout は mouseUp 時にまとめて立てる（ドラッグ中は applyLayout を走らせない）
                            return
                        }
                    }
                }
            }
        }
        observer.onWindowMoved = { [weak self] windowID, newFrame in
            guard let self else { return }
            // スワップ直後のクールダウン中は無視（applyLayout 由来の移動通知を防ぐ）
            guard Date() > self.swapCooldownEnd else { return }
            // マウスボタンが押されていない場合は無視（setWindowFrame 由来など）
            guard self.isMouseDown else { return }
            // 押下時と同じウィンドウのみ対象
            guard self.mouseDownWindowID == windowID else { return }
            // 移動距離が閾値を超えた場合のみドラッグと判定
            guard let downFrame = self.mouseDownFrame else { return }
            let dx = newFrame.origin.x - downFrame.origin.x
            let dy = newFrame.origin.y - downFrame.origin.y
            let distance = sqrt(dx * dx + dy * dy)
            niriLog("[drag] windowMoved: win=\(windowID) distance=\(Int(distance))px threshold=\(Int(self.dragThreshold))px")
            if distance > self.dragThreshold {
                self.draggedWindowID = windowID
                niriLog("[drag] drag confirmed: win=\(windowID)")
            }
        }
        observer.onSpaceChanged = { [weak self] in
            guard let self else { return }
            self.spaceChangedDebounceTimer?.invalidate()
            self.spaceChangedDebounceTimer = Timer.scheduledTimer(
                withTimeInterval: 0.3,
                repeats: false
            ) { [weak self] _ in
                guard let self else { return }
                niriLog("[space-sync] activeSpaceDidChange detected")
                self.syncWindowsForCurrentSpace()
            }
        }
        observer.onApplicationLaunched = { [weak self] pid in
            // kAXWindowCreatedNotification を拾えなかった場合のフォールバック:
            // JVM/Electron 系など起動が遅いアプリに対応するため複数回リトライする
            for delay in [0.6, 2.0, 5.0, 10.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    // アプリが終了済みの場合はスキップ（無効な AX 要素を防ぐ）
                    let isAlive = NSWorkspace.shared.runningApplications
                        .contains { $0.processIdentifier == pid }
                    guard isAlive else { return }
                    let windows = self.axBridge.allWindows().filter { $0.ownerPID == pid }
                    for window in windows {
                        self.handleWindowCreated(window)
                    }
                }
            }
        }
        observer.startObserving()
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenParametersChanged()
        }
    }

    private func setupKeyboard() {
        keyboard.onAction = { [weak self] action in
            self?.handleAction(action)
        }
        keyboard.start()
    }

    private func setupMouse() {
        mouse.onMouseDown = { [weak self] point in
            guard let self else { return }
            self.isMouseDown = true
            for (windowID, frame) in self.lastComputedFrames {
                if frame.contains(point) {
                    self.mouseDownWindowID = windowID
                    self.mouseDownFrame = frame
                    break
                }
            }
            self.handleMouseFocus(at: point)
        }
        mouse.onScroll = { [weak self] deltaX, deltaY, isContinuous, flags in
            self?.handleScroll(deltaX: deltaX, deltaY: deltaY, isContinuous: isContinuous, flags: flags)
        }
        mouse.onMouseUp = { [weak self] point in
            guard let self else { return }
            self.isMouseDown = false
            self.mouseDownWindowID = nil
            self.mouseDownFrame = nil
            self.needsLayout = true  // リサイズ・スワップ確定時にレイアウトを適用
            self.handleMouseUp(at: point)
        }
        mouse.onMouseDragged = { [weak self] point in
            guard let self, let draggedID = self.draggedWindowID else {
                self?.dropTargetOverlay.hide()
                return
            }
            for (windowID, frame) in self.lastComputedFrames {
                guard frame.contains(point), windowID != draggedID else { continue }
                let zone: DropZone = self.isSameColumn(draggedID, windowID)
                    ? .swap
                    : self.dropZone(point: point, in: frame)
                self.dropTargetOverlay.show(frame: frame, zone: zone)
                return
            }
            self.dropTargetOverlay.hide()
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
                self.applyLayout(animated: false)
                self.needsLayout = false
                if self.focusAfterLayout {
                    self.focusAfterLayout = false
                    self.focusActiveWindow()
                }
            }
        }
    }

    // MARK: - Event Handlers

    private func handleWindowCreated(_ window: WindowInfo) {
        guard windowRegistry[window.id] == nil else { return }
        guard !isExcluded(window) else {
            niriLog("[exclusion] skip '\(window.ownerBundleID ?? "?")'  windowID=\(window.id)")
            return
        }

        // windowRegistry に未登録のウィンドウのみ追加
        // (既存ウィンドウの再検出を防ぐ)
        windowRegistry[window.id] = window
        axBridge.registerElement(window.axElement, for: window.id)
        // ウィンドウ要素に破棄通知を個別登録（appElement への登録では発火しないため）
        observer.registerWindowDestroyedNotification(for: window.axElement, pid: window.ownerPID)

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

        // 開いた瞬間から高さを最大化（アプリのデフォルトサイズが一瞬見えるフラッシュを防ぐ）
        let wa = screens[screenIdx].workspaces[screens[screenIdx].activeWorkspaceIndex].workingArea
        let preFrame = CGRect(x: window.frame.origin.x, y: wa.minY, width: colWidth, height: wa.height)
        try? axBridge.setWindowFrame(window.id, frame: preFrame)

        let column = Column(windows: [window.id], width: colWidth)
        screens[screenIdx].workspaces[screens[screenIdx].activeWorkspaceIndex].addColumn(column)
        screens[screenIdx].activeWorkspace.recenterViewOffset(gap: config.gapWidth)

        applyLayout(animated: false)
        try? axBridge.focusWindow(window.id)

        // アプリが非同期で自分のサイズを上書きするレースコンディション対策：
        // 0.5秒後にもう一度レイアウトを再適用する
        let winID = window.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.windowRegistry[winID] != nil else { return }
            self.needsLayout = true
        }

        print("[niri-mac] Window created: \(window.title) (\(window.id))")
    }

    private func handleWindowDestroyed(_ id: WindowID) {
        guard windowRegistry[id] != nil else { return }
        dropTargetOverlay.hide()

        // アクティブウィンドウかどうかを削除前に確認（②）
        let screenIdx = activeScreenIndex()
        let wasActive = screenIdx < screens.count &&
            screens[screenIdx].activeWorkspace.activeWindowID == id

        windowRegistry.removeValue(forKey: id)
        axBridge.removeElement(for: id)
        parkedWindowIDs.remove(id)

        // ドラッグ状態をクリア（③）
        if mouseDownWindowID == id { mouseDownWindowID = nil }
        if draggedWindowID == id { draggedWindowID = nil }

        for i in screens.indices {
            for j in screens[i].workspaces.indices {
                screens[i].workspaces[j].removeWindow(id)
                // カラム削除後に viewOffset を再センタリング（④）
                screens[i].workspaces[j].recenterViewOffset(animated: true)
            }
        }

        applyLayout()
        // アクティブウィンドウが閉じた場合のみフォーカスを移動（②）
        // ウィンドウ破棄はユーザーがマウスで×ボタンを押した等の受動的イベント → カーソル移動しない
        if wasActive { activateWindow() }

        niriLog("[niri-mac] Window destroyed: \(id)")
    }

    private func handleApplicationTerminated(pid: pid_t) {
        // アプリ終了時に該当PIDのウィンドウを全て除去
        let toRemove = windowRegistry.values.filter { $0.ownerPID == pid }.map { $0.id }
        for id in toRemove {
            handleWindowDestroyed(id)
        }
    }

    /// メニューバー用: アクティブカラムのインデックスを返す
    var activeColumnIndex: Int? {
        let idx = activeScreenIndex()
        guard idx < screens.count else { return nil }
        let ws = screens[idx].activeWorkspace
        guard !ws.columns.isEmpty else { return nil }
        return ws.activeColumnIndex
    }

    /// メニューバー用: アクティブカラムが現在 pin されているかを返す
    var activeColumnIsPinned: Bool {
        let idx = activeScreenIndex()
        guard idx < screens.count else { return false }
        let ws = screens[idx].activeWorkspace
        guard !ws.columns.isEmpty, ws.activeColumnIndex < ws.columns.count else { return false }
        return ws.columns[ws.activeColumnIndex].isPinned
    }

    /// メニューバー用: カラムインデックスを指定して handleAction を呼ぶ（togglePin 専用）
    func handleAction(_ action: KeyboardShortcutManager.Action, forColumnIndex columnIndex: Int?) {
        guard action == .togglePin, let colIdx = columnIndex else {
            handleAction(action)
            return
        }
        let screenIdx = activeScreenIndex()
        guard screenIdx < screens.count,
              colIdx < screens[screenIdx].activeWorkspace.columns.count else { return }
        let current = screens[screenIdx].activeWorkspace.columns[colIdx].isPinned
        screens[screenIdx].activeWorkspace.columns[colIdx].isPinned = !current
        niriLog("[action] togglePin(menu) col=\(colIdx) pinned=\(!current)")
        needsLayout = true
    }

    // MARK: - App Exclusion API（メニューバー用）

    /// 現在フォーカス中のアプリの bundleID（取得できない場合は nil）
    var focusedAppBundleID: String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return app.bundleIdentifier
    }

    /// 除外アプリ一覧（bundleID と表示名のペア）
    var excludedApps: [(bundleID: String, name: String)] {
        config.excludedBundleIDs.sorted().map { bundleID in
            let name = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first?.localizedName
                ?? bundleID
            return (bundleID: bundleID, name: name)
        }
    }

    /// アプリを除外リストに追加し、既存ウィンドウをレイアウトから即座に削除する
    func excludeApp(bundleID: String) {
        guard !config.excludedBundleIDs.contains(bundleID) else { return }
        config.excludedBundleIDs.insert(bundleID)
        ExclusionStore.save(config.excludedBundleIDs)
        niriLog("[exclusion] excluded '\(bundleID)'")

        // 既にタイリングに入っているウィンドウを即座に除去
        let toRemove = windowRegistry.values
            .filter { $0.ownerBundleID == bundleID }
            .map { $0.id }
        for id in toRemove {
            handleWindowDestroyed(id)
        }
    }

    /// アプリを除外リストから削除する
    func includeApp(bundleID: String) {
        guard config.excludedBundleIDs.contains(bundleID) else { return }
        config.excludedBundleIDs.remove(bundleID)
        ExclusionStore.save(config.excludedBundleIDs)
        niriLog("[exclusion] included '\(bundleID)'")

        // 既に起動中のウィンドウを即座にタイリングへ復帰させる
        let windows = axBridge.allWindows().filter { $0.ownerBundleID == bundleID }
        for window in windows {
            handleWindowCreated(window)
        }
    }

    // MARK: - Focus Highlight Toggles

    var focusBorderEnabled: Bool { config.focusBorderEnabled }
    var focusDimEnabled: Bool { config.focusDimEnabled }
    var autoFitEnabled: Bool { config.autoFitEnabled }

    func toggleFocusBorder() {
        config.focusBorderEnabled.toggle()
        needsLayout = true
    }

    func toggleFocusDim() {
        config.focusDimEnabled.toggle()
        needsLayout = true
    }

    func toggleAutoFit() {
        config.autoFitEnabled.toggle()
        niriLog("[action] toggleAutoFit → \(config.autoFitEnabled)")
        needsLayout = true
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
            focusAfterLayout = true  // applyLayout 完了後にフォーカス（レイアウト前に呼ぶとマウスが画面外へ飛ぶ）
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
            focusAfterLayout = true  // applyLayout 完了後にフォーカス（レイアウト前に呼ぶとマウスが画面外へ飛ぶ）
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
            var ws = screens[screenIdx].activeWorkspace
            guard !ws.columns.isEmpty else { return }
            let activeIdx = ws.activeColumnIndex
            let screenWidth = screens[screenIdx].frame.width

            // Auto-Fit 中に cycle を押した場合、まず現在表示されている幅を全カラムに固定してから
            // cycle を適用する。これをしないとアクティブ以外のカラムが stale な column.width に戻ってしまう。
            if config.autoFitEnabled && ws.isAutoFitEligible {
                let n = ws.columns.count
                let effectiveWidth = ws.workingArea.width - 2 * config.gapWidth
                let displayedWidth: CGFloat
                switch n {
                case 1: displayedWidth = effectiveWidth * config.autoFitCenterWidthFraction
                case 2: displayedWidth = (effectiveWidth - config.gapWidth) / 2
                case 3: displayedWidth = (effectiveWidth - 2 * config.gapWidth) / 3
                default: displayedWidth = ws.columns[activeIdx].width
                }
                for i in 0..<ws.columns.count {
                    ws.columns[i].width = displayedWidth
                }
            }

            let currentWidth = ws.columns[activeIdx].width
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
            ws.columns[activeIdx].width = screenWidth * nextPreset
            // ユーザーが明示的に幅を操作したので Auto-Fit を解除
            ws.autoFitOverridden = true
            // Auto-Fit 中に裏で累積した viewOffset を破棄（stale スクロール防止）
            ws.viewOffset = .static(offset: 0)
            screens[screenIdx].activeWorkspace = ws

        case .togglePin:
            guard !screens[screenIdx].activeWorkspace.columns.isEmpty else { return }
            let activeIdx = screens[screenIdx].activeWorkspace.activeColumnIndex
            let current = screens[screenIdx].activeWorkspace.columns[activeIdx].isPinned
            screens[screenIdx].activeWorkspace.columns[activeIdx].isPinned = !current
            niriLog("[action] togglePin col=\(activeIdx) pinned=\(!current)")

        case .moveWindowUpInColumn:
            niriLog("[action] moveWindowUpInColumn")
            let colIdx = screens[screenIdx].activeWorkspace.activeColumnIndex
            screens[screenIdx].activeWorkspace.columns[colIdx].moveActiveWindowUp()

        case .moveWindowDownInColumn:
            niriLog("[action] moveWindowDownInColumn")
            let colIdx = screens[screenIdx].activeWorkspace.activeColumnIndex
            screens[screenIdx].activeWorkspace.columns[colIdx].moveActiveWindowDown()

        case .growWindowHeight:
            niriLog("[action] growWindowHeight")
            let colIdx = screens[screenIdx].activeWorkspace.activeColumnIndex
            screens[screenIdx].activeWorkspace.columns[colIdx].resizeActiveWindowHeight(delta: 0.10)

        case .shrinkWindowHeight:
            niriLog("[action] shrinkWindowHeight")
            let colIdx = screens[screenIdx].activeWorkspace.activeColumnIndex
            screens[screenIdx].activeWorkspace.columns[colIdx].resizeActiveWindowHeight(delta: -0.10)

        case .toggleAutoFit:
            toggleAutoFit()

        case .quit:
            stop()
            NSApplication.shared.terminate(nil)
            return

        case .reLayout:
            niriLog("[action] reLayout")
            refreshScreenGeometry()
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

            let workingArea = ws.workingArea
            for (windowID, frame) in frames {
                let title = windowRegistry[windowID]?.title ?? "?"
                niriLog("[layout]   win=\(windowID) '\(title)' frame=\(frame) offScreen=\(isWindowOffScreen(frame, workingArea: workingArea))")
                applyWindowVisibility(windowID: windowID, frame: frame, screen: screen, workingArea: workingArea, parkX: parkX, parkY: &parkY)
            }
            _ = screenIdx  // suppress warning
        }
        lastComputedFrames = allFrames

        // Y位置補正パス: 高さ変更を拒否したウィンドウ（iTerm2等の文字グリッドスナップ）の
        // 後続ウィンドウY位置を実際の高さに合わせてずらす
        for screen in screens {
            let ws = screen.activeWorkspace
            for col in ws.columns {
                guard col.windows.count > 1 else { continue }
                var prevActualBottom: CGFloat? = nil
                for windowID in col.windows {
                    guard !parkedWindowIDs.contains(windowID) else { continue }
                    guard var computedFrame = allFrames.first(where: { $0.0 == windowID })?.1 else { continue }
                    if let prevBottom = prevActualBottom, prevBottom > computedFrame.origin.y + 2 {
                        let correctedY = prevBottom
                        niriLog("[layout]   🔧 Y補正 win=\(windowID): y=\(Int(computedFrame.origin.y))→\(Int(correctedY))")
                        computedFrame.origin.y = correctedY
                        try? axBridge.setWindowFrame(windowID, frame: computedFrame)
                    }
                    let actualFrame = axBridge.windowFrame(windowID) ?? computedFrame
                    prevActualBottom = actualFrame.maxY + config.gapHeight
                }
            }
        }

        // フォーカスオーバーレイを更新（parkedWindowIDs を除いた可視フレームのみ渡す）
        // applyLayout はメインスレッドで動くため直接呼び出す
        let visibleFrames = allFrames.filter { !parkedWindowIDs.contains($0.0) }
        let screenIdx = activeScreenIndex()
        let managedFocusedID: WindowID? = screenIdx < screens.count
            ? screens[screenIdx].activeWorkspace.activeWindowID
            : nil

        // float window（管理対象外）がフォーカスを持つ場合も border/dim を適用する
        var focusedID: WindowID? = managedFocusedID
        var overlayFrames = visibleFrames
        if let (fwID, fwFrame) = frontmostWindowIDAndFrame(),
           !visibleFrames.contains(where: { $0.0 == fwID }) {
            // 管理対象外ウィンドウ（float window）がフロント → それを overlay の対象にする
            focusedID = fwID
            overlayFrames.append((fwID, fwFrame))
        }

        let pinnedWindowIDs = Set(screens.flatMap { $0.activeWorkspace.columns }
            .filter { $0.isPinned }
            .flatMap { $0.windows })
        focusOverlayManager.update(
            focusedID: focusedID,
            allFrames: overlayFrames,
            pinnedWindowIDs: pinnedWindowIDs,
            config: config
        )
    }

    /// 画面外判定。ウィンドウが workingArea の完全外側にある場合のみ off-screen とする。
    private func isWindowOffScreen(_ frame: CGRect, workingArea: CGRect) -> Bool {
        return frame.maxX <= workingArea.minX || frame.minX >= workingArea.maxX
    }

    /// 画面内外に応じてウィンドウを完全非表示/復帰する。
    /// Space API（CGSAddWindowsToSpaces）は現環境で機能しないため、
    /// 画面外へのポジション移動で完全非表示を実現する。
    private func applyWindowVisibility(
        windowID: WindowID,
        frame: CGRect,
        screen: Screen,
        workingArea: CGRect,
        parkX: CGFloat,
        parkY: inout CGFloat
    ) {
        // ドラッグ中のウィンドウは WM が位置を上書きしない（スナップバックを防ぐ）
        if windowID == draggedWindowID { return }
        // マウスボタン押下中のウィンドウ候補もスキップ（ドラッグ判定前にアニメーションで戻されるのを防ぐ）
        if isMouseDown && windowID == mouseDownWindowID { return }

        if isWindowOffScreen(frame, workingArea: workingArea) {
            // キャッシュ済みならスキップ（毎フレームのsetFrame呼び出しを防ぐ）
            if parkedWindowIDs.contains(windowID) { return }

            // 左右どちらに出ているかで退避方向を決定（反対側に飛ばさない）
            let hiddenX: CGFloat
            if frame.minX < workingArea.minX {
                hiddenX = workingArea.minX - frame.width - 1
            } else {
                hiddenX = parkX
            }
            let hiddenFrame = CGRect(x: hiddenX, y: frame.origin.y, width: frame.width, height: frame.height)
            niriLog("[layout]   🅿️ hide win=\(windowID) → x=\(Int(parkX))")
            try? axBridge.setWindowFrame(windowID, frame: hiddenFrame)
            // 実際に移動できたときだけキャッシュに追加（失敗時は次フレームで再試行）
            if let actual = axBridge.windowFrame(windowID), isWindowOffScreen(actual, workingArea: workingArea) {
                parkedWindowIDs.insert(windowID)
            } else {
                niriLog("[layout]   ⚠️ hide失敗 win=\(windowID) actual.x=\(Int(axBridge.windowFrame(windowID)?.origin.x ?? -1))")
            }
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

    /// AX フォーカスのみ。カーソル移動なし（マウス操作・受動的イベント用）
    private func activateWindow() {
        let screenIdx = activeScreenIndex()
        guard screenIdx < screens.count,
              let windowID = screens[screenIdx].activeWorkspace.activeWindowID
        else { return }
        try? axBridge.focusWindow(windowID)
    }

    /// AX フォーカス + カーソルをウィンドウ中央にワープ（キーボード操作専用）
    private func focusActiveWindow() {
        let screenIdx = activeScreenIndex()
        guard screenIdx < screens.count,
              let windowID = screens[screenIdx].activeWorkspace.activeWindowID
        else { return }

        try? axBridge.focusWindow(windowID)

        guard config.warpMouseToFocus else { return }

        // viewOffset がアニメーション中でも target を使って最終フレームを計算する
        var ws = screens[screenIdx].activeWorkspace
        ws.viewOffset = .static(offset: ws.viewOffset.target)
        let frames = LayoutEngine.computeWindowFrames(
            workspace: ws,
            screenFrame: screens[screenIdx].frame,
            config: config
        )
        if let frame = frames.first(where: { $0.0 == windowID })?.1, frame.width > 0 {
            CGDisplayMoveCursorToPoint(screens[screenIdx].id, CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    // MARK: - Drag Helpers

    /// windowID を含むカラム全体の結合フレーム（Quartz座標）を返す
    private func columnFrame(for windowID: WindowID) -> CGRect? {
        for screen in screens {
            let ws = screen.activeWorkspace
            guard let colIdx = ws.columnIndex(for: windowID) else { continue }
            let ids = ws.columns[colIdx].windows
            let frames = ids.compactMap { id in lastComputedFrames.first(where: { $0.0 == id })?.1 }
            guard !frames.isEmpty else { continue }
            return frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        }
        return nil
    }

    /// windowID を含むカラムのウィンドウ数を返す
    private func columnWindowCount(for windowID: WindowID) -> Int {
        for screen in screens {
            let ws = screen.activeWorkspace
            guard let colIdx = ws.columnIndex(for: windowID) else { continue }
            return ws.columns[colIdx].windows.count
        }
        return 0
    }

    /// a と b が同一カラムにあるか判定する
    private func isSameColumn(_ a: WindowID, _ b: WindowID) -> Bool {
        for screen in screens {
            let ws = screen.activeWorkspace
            if let colA = ws.columnIndex(for: a), let colB = ws.columnIndex(for: b) {
                return colA == colB
            }
        }
        return false
    }

    /// point が frame（ターゲットウィンドウ、Quartz座標）のどのゾーンにあるか判定する。
    /// 左右端20%は insertLeft/insertRight、中央60%は上/中/下の3ゾーン。
    /// Quartz座標（Y下向き）: minY=視覚上端, maxY=視覚下端
    private func dropZone(point: CGPoint, in frame: CGRect) -> DropZone {
        let edgeWidth = frame.width * 0.20
        if point.x < frame.minX + edgeWidth { return .insertLeft }
        if point.x > frame.maxX - edgeWidth { return .insertRight }
        let third = frame.height / 3
        if point.y < frame.minY + third { return .stackAbove }
        if point.y > frame.maxY - third { return .stackBelow }
        return .swap
    }

    // MARK: - Mouse Handlers

    /// ドラッグ終了時の処理。スタックゾーン判定でモードを決定する。
    private func handleMouseUp(at point: CGPoint) {
        defer {
            dropTargetOverlay.hide()
        }
        guard let draggedID = draggedWindowID else { return }
        draggedWindowID = nil

        // ターゲット検出 → スタック/スワップ

        // Priority 1: カーソルヒット
        var targetID: WindowID? = nil
        var targetFrame: CGRect = .zero
        for (windowID, frame) in lastComputedFrames {
            guard windowID != draggedID, frame.contains(point) else { continue }
            targetID = windowID; targetFrame = frame; break
        }

        // Priority 2: フレームオーバーラップ最大（同カラム内ウィンドウは除外）
        // スタックされたウィンドウは同カラム内で必ずオーバーラップするため、
        // ここで拾うと expel 分岐に到達できなくなる。
        if targetID == nil, let draggedFrame = axBridge.windowFrame(draggedID) {
            var bestOverlap: CGFloat = 0
            for (windowID, frame) in lastComputedFrames {
                guard windowID != draggedID,
                      !isSameColumn(draggedID, windowID) else { continue }
                let intersection = draggedFrame.intersection(frame)
                guard !intersection.isNull else { continue }
                let overlap = intersection.width * intersection.height
                if overlap > bestOverlap {
                    bestOverlap = overlap; targetID = windowID; targetFrame = frame
                }
            }
        }

        guard let target = targetID else {
            // スタックカラム（2枚以上）からのドラッグをターゲットなし領域にドロップ → expel
            if tryExpelDraggedWindow(draggedID: draggedID, dropX: point.x, reason: "no-target") {
                return
            }
            niriLog("[drag] mouseUp: no target — restoring layout")
            needsLayout = true
            return
        }

        // ゾーン判定
        let zone: DropZone
        if isSameColumn(draggedID, target) {
            zone = .swap
        } else if targetFrame.contains(point) {
            zone = dropZone(point: point, in: targetFrame)
        } else if let draggedFrame = axBridge.windowFrame(draggedID) {
            zone = draggedFrame.midY < targetFrame.midY ? .stackAbove : .stackBelow
        } else {
            zone = point.y < targetFrame.midY ? .stackAbove : .stackBelow
        }
        niriLog("[drag] mouseUp: dragged=\(draggedID) target=\(target) zone=\(zone)")

        if isSameColumn(draggedID, target) {
            // 方向判定: dragged の実位置（AX）と layout 位置の水平差分を測る。
            // カラム幅の 1/3 を超えたら expel（余白なしでも解除可能）、以下なら swap。
            let layoutX: CGFloat = lastComputedFrames.first(where: { $0.0 == draggedID })?.1.midX ?? targetFrame.midX
            let actualX: CGFloat = axBridge.windowFrame(draggedID)?.midX ?? layoutX
            let horizontalDrift = abs(actualX - layoutX)
            let expelThreshold = targetFrame.width / 3

            if horizontalDrift > expelThreshold {
                _ = tryExpelDraggedWindow(draggedID: draggedID, dropX: actualX, reason: "same-col drift=\(Int(horizontalDrift))px")
            } else {
                // swap: 同カラム内 reorder
                for i in screens.indices {
                    for j in screens[i].workspaces.indices {
                        let has1 = screens[i].workspaces[j].columnIndex(for: draggedID) != nil
                        let has2 = screens[i].workspaces[j].columnIndex(for: target) != nil
                        if has1 && has2 { screens[i].workspaces[j].swapWindows(draggedID, target); break }
                    }
                }
            }
        } else {
            switch zone {
            case .stackAbove:
                consumeWindowByMouse(draggedID, target: target, position: .above)
            case .stackBelow:
                consumeWindowByMouse(draggedID, target: target, position: .below)
            case .swap:
                // cross-column 中央ゾーン → 2ウィンドウの位置交換（スワップ）
                for i in screens.indices {
                    for j in screens[i].workspaces.indices {
                        let has1 = screens[i].workspaces[j].columnIndex(for: draggedID) != nil
                        let has2 = screens[i].workspaces[j].columnIndex(for: target) != nil
                        if has1 && has2 { screens[i].workspaces[j].swapWindows(draggedID, target); break }
                    }
                }
            case .insertLeft:
                expelWindowByMouseInsert(draggedID, target: target, insertBefore: true)
            case .insertRight:
                expelWindowByMouseInsert(draggedID, target: target, insertBefore: false)
            }
        }
        swapCooldownEnd = Date().addingTimeInterval(0.5)
        needsLayout = true
    }

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
    ///
    /// niri 設計方針に準拠:
    /// - 修飾キーなし → アプリへ透過（WMは無視）
    /// - Ctrl のみ   → 水平レイアウトスクロール
    /// - Ctrl+Opt    → カラムフォーカス移動
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

        // Option + スクロール → レイアウトスクロール（縦横どちらも使える）
        if filtered == [.option] {
            let effective = abs(deltaX) >= abs(deltaY) ? deltaX : -deltaY
            guard abs(effective) > 0.5 else { return }
            applyLayoutScroll(effectiveDeltaX: effective, sensitivity: config.optionScrollSensitivity, isContinuous: isContinuous, screenIdx: screenIdx)
            return
        }

        // Ctrl のみ + 水平スクロール → レイアウトスクロール
        guard filtered == [.control], abs(deltaX) > 0.5 else { return }
        applyLayoutScroll(effectiveDeltaX: deltaX, sensitivity: isContinuous ? config.scrollSensitivity : config.mouseWheelScrollSensitivity, isContinuous: isContinuous, screenIdx: screenIdx)
    }

    private func applyLayoutScroll(effectiveDeltaX: CGFloat, sensitivity: CGFloat, isContinuous: Bool, screenIdx: Int) {
        // Auto-Fit 中はスクロール自体が無意味なので viewOffset を触らない
        if config.autoFitEnabled && screens[screenIdx].activeWorkspace.isAutoFitEligible {
            return
        }

        var ws = screens[screenIdx].activeWorkspace
        ws.applyScrollDelta(deltaX: effectiveDeltaX, sensitivity: sensitivity, isContinuous: isContinuous, gap: config.gapWidth)
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

    /// フロントウィンドウの WindowID と Quartz フレームを返す（AX 経由）
    /// niri-mac 自身と取得失敗時は nil を返す
    private func frontmostWindowIDAndFrame() -> (WindowID, CGRect)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let axWin = ref else { return nil }
        let axUIWin = axWin as! AXUIElement
        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(axUIWin, &windowID) == .success else { return nil }
        guard let frame = WindowInfo.fetchFrame(from: axUIWin) else { return nil }
        return (windowID, frame)
    }

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

    /// マウスドラッグによる consume: draggedID を targetID のカラムに position で挿入する
    private func consumeWindowByMouse(
        _ draggedID: WindowID,
        target targetID: WindowID,
        position: Workspace.ColumnInsertPosition
    ) {
        niriLog("[drag] stack: \(draggedID) → \(position == .above ? "above" : "below") \(targetID)")
        for i in screens.indices {
            for j in screens[i].workspaces.indices {
                let hasDragged = screens[i].workspaces[j].columnIndex(for: draggedID) != nil
                let hasTarget  = screens[i].workspaces[j].columnIndex(for: targetID) != nil
                if hasDragged && hasTarget {
                    if let tCol = screens[i].workspaces[j].columnIndex(for: targetID) {
                        niriLog("[drag] stack before: col[\(tCol)]=\(screens[i].workspaces[j].columns[tCol].windows)")
                    }
                    screens[i].workspaces[j].consumeWindowIntoColumn(draggedID, target: targetID, position: position)
                    if let tCol = screens[i].workspaces[j].columnIndex(for: targetID) {
                        niriLog("[drag] stack after:  col[\(tCol)]=\(screens[i].workspaces[j].columns[tCol].windows)")
                    }
                    return
                }
            }
        }
    }

    /// ドラッグで別カラムの左端/右端にドロップしたとき、追い出して新カラムとして挿入する。
    /// - insertBefore: true → ターゲットカラムの左に挿入、false → 右に挿入
    private func expelWindowByMouseInsert(_ draggedID: WindowID, target targetID: WindowID, insertBefore: Bool) {
        for i in screens.indices {
            for j in screens[i].workspaces.indices {
                guard let srcIdx = screens[i].workspaces[j].columnIndex(for: draggedID),
                      let tgtIdx = screens[i].workspaces[j].columnIndex(for: targetID)
                else { continue }

                let srcCol = screens[i].workspaces[j].columns[srcIdx]

                if srcCol.windows.count == 1 {
                    // 単一ウィンドウカラム → カラムごとリオーダー
                    let col = screens[i].workspaces[j].columns[srcIdx]
                    screens[i].workspaces[j].columns.remove(at: srcIdx)
                    let adjustedTgt = srcIdx < tgtIdx ? tgtIdx - 1 : tgtIdx
                    let insertIdx = insertBefore ? adjustedTgt : adjustedTgt + 1
                    let safeIdx = max(0, min(insertIdx, screens[i].workspaces[j].columns.count))
                    screens[i].workspaces[j].columns.insert(col, at: safeIdx)
                    screens[i].workspaces[j].activeColumnIndex = safeIdx
                } else {
                    // 複数ウィンドウカラム → アクティブウィンドウを追い出して新カラム作成
                    guard let windowID = srcCol.activeWindowID else { continue }
                    let screenWidth = screens[i].frame.width
                    let colWidth = (windowRegistry[windowID]?.frame.width ?? 0) > 0
                        ? windowRegistry[windowID]!.frame.width
                        : config.defaultColumnWidth(for: screenWidth)
                    screens[i].workspaces[j].columns[srcIdx].removeWindow(windowID)
                    let insertIdx = insertBefore ? tgtIdx : tgtIdx + 1
                    let safeIdx = max(0, min(insertIdx, screens[i].workspaces[j].columns.count))
                    let newCol = Column(windows: [windowID], width: colWidth)
                    screens[i].workspaces[j].columns.insert(newCol, at: safeIdx)
                    screens[i].workspaces[j].activeColumnIndex = safeIdx
                }
                niriLog("[drag] expel insert: dragged=\(draggedID) target=\(targetID) before=\(insertBefore)")
                needsLayout = true
                return
            }
        }
    }

    /// draggedID をスタックカラムから抜き出して新しいカラムとして挿入する共通ヘルパー。
    /// dropX が元カラム中央より左なら左側、右なら右側に新カラムを挿入する。
    /// - Returns: expel が発動したら true（カラムが1ウィンドウしかない場合などは false）
    @discardableResult
    private func tryExpelDraggedWindow(draggedID: WindowID, dropX: CGFloat, reason: String) -> Bool {
        for i in screens.indices {
            for j in screens[i].workspaces.indices {
                guard let colIdx = screens[i].workspaces[j].columnIndex(for: draggedID) else { continue }

                // 元カラム中央の X を同カラム内ウィンドウのレイアウトフレームから推定
                let colCenterX: CGFloat = screens[i].workspaces[j].columns[colIdx].windows
                    .compactMap { wid in self.lastComputedFrames.first(where: { $0.0 == wid })?.1 }
                    .first.map { $0.midX } ?? dropX

                let side: Workspace.ExpelInsertSide = dropX < colCenterX ? .left : .right
                let screenWidth = screens[i].frame.width
                let newColWidth = (windowRegistry[draggedID]?.frame.width ?? 0) > 0
                    ? windowRegistry[draggedID]!.frame.width
                    : config.defaultColumnWidth(for: screenWidth)

                if screens[i].workspaces[j].expelWindow(draggedID, newColumnWidth: newColWidth, insertSide: side) {
                    niriLog("[drag] expel(\(reason)): win=\(draggedID) → \(side == .left ? "left" : "right") of col \(colIdx)")
                    swapCooldownEnd = Date().addingTimeInterval(0.5)
                    needsLayout = true
                    return true
                }
            }
        }
        return false
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
