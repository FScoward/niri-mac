# Mouse Stack / Unstack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** マウスのドラッグ&ドロップで、ウィンドウを別のウィンドウのカラムにスタック（上・下）、または既存スタックカラムから独立カラムへ解除（Expel）できるようにする。

**Architecture:** `DropTargetOverlayManager` に `DropZone` enum（stackAbove/swap/stackBelow/expel）を追加してゾーン別の色付き破線枠を表示し、`Workspace` に `consumeWindowIntoColumn(_:target:position:)` を追加してドラッグでのスタックを可能にする。`WindowManager.onMouseDragged` でゾーン検出、`handleMouseUp` でスタック・スワップ・Expelの分岐を実装する。

**Tech Stack:** Swift, AppKit (NSPanel, CAShapeLayer), CoreGraphics

---

### Task 1: DropTargetOverlayManager に DropZone 対応を追加する

**Files:**
- Modify: `Sources/NiriMac/Bridge/DropTargetOverlayManager.swift`

- [ ] **Step 1: `DropZone` enum と `show(frame:zone:)` を追加する**

`Sources/NiriMac/Bridge/DropTargetOverlayManager.swift` 全体を以下に置き換える:

```swift
import AppKit
import CoreGraphics

/// ドロップゾーンの種類。色と動作を決定する。
enum DropZone {
    case stackAbove   // 青破線: ターゲットの上にスタック
    case swap         // 黄破線: スワップ（現状維持）
    case stackBelow   // 青破線: ターゲットの下にスタック
    case expel        // 赤破線: 解除モード
}

/// ドラッグ中のドロップターゲットウィンドウに破線の色枠を重ねて表示する NSPanel オーバーレイ。
/// WindowManager から show(frame:zone:) / hide() を呼ぶことでリアルタイム更新される。
final class DropTargetOverlayManager {

    private var panel: NSPanel?
    private var borderLayer: CAShapeLayer?

    // MARK: - Public API

    /// 指定フレーム（Quartz座標系）にゾーン対応の破線枠を表示する
    func show(frame: CGRect, zone: DropZone = .swap) {
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let cocoaFrame = quartzToCocoa(frame, screenHeight: screenHeight)

        let p = panel ?? makePanel()
        panel = p
        p.setFrame(cocoaFrame, display: true)

        let (strokeColor, bgColor) = zoneColors(zone)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        borderLayer?.strokeColor = strokeColor
        if let contentView = p.contentView {
            contentView.layer?.backgroundColor = bgColor
            let bounds = contentView.bounds
            let path = CGPath(
                roundedRect: bounds.insetBy(dx: 2, dy: 2),
                cornerWidth: 6, cornerHeight: 6, transform: nil
            )
            borderLayer?.path = path
        }
        CATransaction.commit()
        p.orderFrontRegardless()
    }

    /// オーバーレイを非表示にする
    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - ゾーン別スタイル

    private func zoneColors(_ zone: DropZone) -> (CGColor, CGColor) {
        switch zone {
        case .stackAbove, .stackBelow:
            return (
                NSColor(red: 0.42, green: 0.48, blue: 1.0, alpha: 1.0).cgColor,
                NSColor(red: 0.42, green: 0.48, blue: 1.0, alpha: 0.08).cgColor
            )
        case .swap:
            return (
                NSColor(red: 1.0, green: 0.78, blue: 0.0, alpha: 1.0).cgColor,
                NSColor(red: 1.0, green: 0.78, blue: 0.0, alpha: 0.05).cgColor
            )
        case .expel:
            return (
                NSColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1.0).cgColor,
                NSColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 0.08).cgColor
            )
        }
    }

    // MARK: - Quartz → Cocoa 座標変換

    private func quartzToCocoa(_ frame: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.origin.x,
            y: screenHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    // MARK: - NSPanel ファクトリ

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        p.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        p.ignoresMouseEvents = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(red: 0.42, green: 0.48, blue: 1.0, alpha: 0.08).cgColor
        p.contentView = view

        let border = CAShapeLayer()
        border.fillColor = NSColor.clear.cgColor
        border.strokeColor = NSColor(red: 0.42, green: 0.48, blue: 1.0, alpha: 1.0).cgColor
        border.lineWidth = 2.0
        border.lineDashPattern = [NSNumber(value: 6), NSNumber(value: 4)]
        view.layer?.addSublayer(border)
        borderLayer = border

        return p
    }
}
```

- [ ] **Step 2: ビルドして確認する**

```bash
cd /Users/fumiyasu/ghq/github.com/FScoward/niri-mac && swift build 2>&1 | grep -E "error:|Build complete"
```

期待値: `Build complete!`

- [ ] **Step 3: コミットする**

```bash
git add Sources/NiriMac/Bridge/DropTargetOverlayManager.swift
git commit -m "feat: add DropZone enum and zone-based styling to DropTargetOverlayManager"
```

---

### Task 2: Workspace に consumeWindowIntoColumn を追加する

**Files:**
- Modify: `Sources/NiriMac/Core/Workspace.swift`
- Test: `Tests/NiriMacTests/WorkspaceTests.swift`

- [ ] **Step 1: テストを書く**

`Tests/NiriMacTests/WorkspaceTests.swift` の末尾（最後の `}` の前）に追加する:

```swift
    // MARK: - consumeWindowIntoColumn

    @Test func consumeWindowIntoColumn_above_insertsBefore() {
        // Win 1 (col 0) を Win 2 (col 1) の上にスタック
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            Column(windows: [1], width: 400),
            Column(windows: [2, 3], width: 400),
        ]
        ws.activeColumnIndex = 0

        ws.consumeWindowIntoColumn(1, target: 2, position: .above)

        // col 0 が消えて col 0（元col1）が [1, 2, 3] になる
        #expect(ws.columns.count == 1)
        #expect(ws.columns[0].windows == [1, 2, 3])
    }

    @Test func consumeWindowIntoColumn_below_insertsAfter() {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            Column(windows: [1], width: 400),
            Column(windows: [2, 3], width: 400),
        ]

        ws.consumeWindowIntoColumn(1, target: 2, position: .below)

        // [2, 1, 3] になる
        #expect(ws.columns.count == 1)
        #expect(ws.columns[0].windows == [2, 1, 3])
    }

    @Test func consumeWindowIntoColumn_removesEmptySourceColumn() {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            Column(windows: [1], width: 400),   // col 0: 1個だけ
            Column(windows: [2], width: 400),   // col 1
        ]

        ws.consumeWindowIntoColumn(1, target: 2, position: .above)

        #expect(ws.columns.count == 1)
        #expect(ws.columns[0].windows.contains(1))
        #expect(ws.columns[0].windows.contains(2))
    }

    @Test func consumeWindowIntoColumn_sourceHasMultipleWindows_columnRemains() {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            Column(windows: [1, 2], width: 400),  // col 0: 2個
            Column(windows: [3], width: 400),      // col 1
        ]

        ws.consumeWindowIntoColumn(1, target: 3, position: .below)

        // col 0 は [2] のまま残る
        #expect(ws.columns.count == 2)
        #expect(ws.columns[0].windows == [2])
        #expect(ws.columns[1].windows == [3, 1])
    }

    @Test func consumeWindowIntoColumn_sameColumn_isNoop() {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [Column(windows: [1, 2], width: 400)]

        ws.consumeWindowIntoColumn(1, target: 2, position: .above)

        // 変化なし
        #expect(ws.columns.count == 1)
        #expect(ws.columns[0].windows == [1, 2])
    }

    @Test func consumeWindowIntoColumn_setsFocusToDraggedWindow() {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [
            Column(windows: [1], width: 400),
            Column(windows: [2], width: 400),
        ]

        ws.consumeWindowIntoColumn(1, target: 2, position: .below)

        // 挿入後、activeWindowIndex が 1（Win 1 の位置）を指す
        #expect(ws.columns[0].activeWindowID == 1)
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
swift test --filter WorkspaceTests 2>&1 | grep -E "✘|error:|passed|failed" | tail -10
```

期待値: `consumeWindowIntoColumn` 関連テストが FAIL

- [ ] **Step 3: `ColumnInsertPosition` と `consumeWindowIntoColumn` を実装する**

`Sources/NiriMac/Core/Workspace.swift` の `swapWindows` メソッドの後（`findWindowPosition` の前）に追加する:

```swift
    // MARK: - Column Stack Operations

    /// consumeWindowIntoColumn で使うスタック挿入位置
    enum ColumnInsertPosition {
        case above  // target の直上に挿入
        case below  // target の直下に挿入
    }

    /// draggedID を targetID のカラムに position で挿入する。
    /// ソースカラムが空になれば削除する。同一カラム内の場合は何もしない。
    mutating func consumeWindowIntoColumn(
        _ draggedID: WindowID,
        target targetID: WindowID,
        position: ColumnInsertPosition
    ) {
        guard draggedID != targetID else { return }
        guard let draggedColIdx = columnIndex(for: draggedID),
              let targetColIdx  = columnIndex(for: targetID),
              draggedColIdx != targetColIdx
        else { return }

        // 1. draggedID をソースカラムから取り出す
        columns[draggedColIdx].removeWindow(draggedID)

        // 2. ソースカラムが空になったら削除し、targetColIdx を補正
        var adjustedTargetIdx = targetColIdx
        if columns[draggedColIdx].isEmpty {
            removeColumn(at: draggedColIdx)
            if draggedColIdx < targetColIdx {
                adjustedTargetIdx -= 1
            }
        }

        // 3. targetID のカラム内の現在インデックスを取得
        guard let targetWinIdx = columns[adjustedTargetIdx].windows.firstIndex(of: targetID) else { return }

        // 4. position に応じて挿入
        let insertIdx: Int
        switch position {
        case .above: insertIdx = targetWinIdx
        case .below: insertIdx = targetWinIdx + 1
        }
        let safeIdx = min(insertIdx, columns[adjustedTargetIdx].windows.count)
        columns[adjustedTargetIdx].windows.insert(draggedID, at: safeIdx)

        // 5. フォーカスをターゲットカラム・挿入したウィンドウに移す
        focusColumn(at: adjustedTargetIdx)
        if let newWinIdx = columns[adjustedTargetIdx].windows.firstIndex(of: draggedID) {
            columns[adjustedTargetIdx].activeWindowIndex = newWinIdx
        }
    }
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
swift test --filter WorkspaceTests 2>&1 | grep -E "✘|passed|failed" | tail -5
```

期待値: 全テスト PASS

- [ ] **Step 5: 全テストが通ることを確認する**

```bash
swift test 2>&1 | grep -E "✘|passed|failed" | tail -5
```

期待値: 全テスト PASS

- [ ] **Step 6: コミットする**

```bash
git add Sources/NiriMac/Core/Workspace.swift Tests/NiriMacTests/WorkspaceTests.swift
git commit -m "feat: add consumeWindowIntoColumn to Workspace for mouse-based stacking"
```

---

### Task 3: WindowManager にマウスドラッグのスタック＆解除ロジックを統合する

**Files:**
- Modify: `Sources/NiriMac/Orchestrator/WindowManager.swift`

#### Step 1–3: ヘルパーメソッドを追加する

- [ ] **Step 1: `columnFrame(for:)` / `columnWindowCount(for:)` / `isSameColumn(_:_:)` / `dropZone(point:in:)` を追加する**

`WindowManager.swift` の `// MARK: - Mouse Handlers` の直前（`handleMouseUp` の前）に追加する:

```swift
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

    /// point が frame（ターゲットウィンドウ、Quartz座標）の3ゾーンのどこにあるか判定する
    private func dropZone(point: CGPoint, in frame: CGRect) -> DropZone {
        let third = frame.height / 3
        if point.y < frame.minY + third { return .stackAbove }
        if point.y > frame.maxY - third { return .stackBelow }
        return .swap
    }
```

- [ ] **Step 2: ビルドして確認する**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

期待値: `Build complete!`

- [ ] **Step 3: `onMouseDragged` ハンドラを拡張する**

`setupMouse()` 内の既存の `mouse.onMouseDragged = { ... }` ブロック全体を以下に置き換える:

```swift
        mouse.onMouseDragged = { [weak self] point in
            guard let self, let draggedID = self.draggedWindowID else {
                self?.dropTargetOverlay.hide()
                return
            }
            // 解除モード: 2ウィンドウ以上のカラムでカーソルがカラム外
            if let colFrame = self.columnFrame(for: draggedID),
               self.columnWindowCount(for: draggedID) > 1,
               !colFrame.contains(point) {
                if let draggedFrame = self.lastComputedFrames.first(where: { $0.0 == draggedID })?.1 {
                    self.dropTargetOverlay.show(frame: draggedFrame, zone: .expel)
                }
                return
            }
            // ターゲットウィンドウを探してゾーン別に表示
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
```

- [ ] **Step 4: `expelWindowByMouse(windowID:side:)` と `consumeWindowByMouse(_:target:position:)` を追加する**

`expelWindowFromColumn(screenIdx:)` メソッドの後（`}` の後）に追加する:

```swift
    private enum DragSide { case left, right }

    /// マウスドラッグによる Expel: windowID を含むカラムから切り出して独立カラムにする
    private func expelWindowByMouse(windowID: WindowID, side: DragSide) {
        niriLog("[drag] expel: \(windowID) to \(side == .left ? "left" : "right")")
        for i in screens.indices {
            for j in screens[i].workspaces.indices {
                guard let colIdx = screens[i].workspaces[j].columnIndex(for: windowID),
                      screens[i].workspaces[j].columns[colIdx].windows.count > 1 else { continue }
                var ws = screens[i].workspaces[j]
                ws.columns[colIdx].removeWindow(windowID)
                let screenWidth = screens[i].frame.width
                let newColWidth = config.defaultColumnWidth(for: screenWidth)
                let newColumn = Column(windows: [windowID], width: newColWidth)
                let insertIdx = (side == .left) ? colIdx : colIdx + 1
                ws.addColumn(newColumn, at: insertIdx)
                screens[i].workspaces[j] = ws
                return
            }
        }
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
                    screens[i].workspaces[j].consumeWindowIntoColumn(draggedID, target: targetID, position: position)
                    return
                }
            }
        }
    }
```

- [ ] **Step 5: `handleMouseUp(at:)` を拡張する**

既存の `handleMouseUp(at:)` メソッド全体を以下に置き換える:

```swift
    /// ドラッグ終了時のスタック/スワップ/Expel 判定
    private func handleMouseUp(at point: CGPoint) {
        guard let draggedID = draggedWindowID else { return }
        draggedWindowID = nil

        // 解除モード: 2ウィンドウ以上のカラムでカーソルがカラム外
        if let colFrame = columnFrame(for: draggedID),
           columnWindowCount(for: draggedID) > 1,
           !colFrame.contains(point) {
            let side: DragSide = point.x < colFrame.midX ? .left : .right
            expelWindowByMouse(windowID: draggedID, side: side)
            swapCooldownEnd = Date().addingTimeInterval(0.5)
            needsLayout = true
            return
        }

        // ターゲットウィンドウを探してスタック/スワップ
        for (windowID, frame) in lastComputedFrames {
            guard frame.contains(point), windowID != draggedID else { continue }

            if isSameColumn(draggedID, windowID) {
                // 同一カラム → スワップ（既存動作）
                niriLog("[drag] swap (same col): \(draggedID) ↔ \(windowID)")
                for i in screens.indices {
                    for j in screens[i].workspaces.indices {
                        let has1 = screens[i].workspaces[j].columnIndex(for: draggedID) != nil
                        let has2 = screens[i].workspaces[j].columnIndex(for: windowID) != nil
                        if has1 && has2 {
                            screens[i].workspaces[j].swapWindows(draggedID, windowID)
                            break
                        }
                    }
                }
            } else {
                // 異なるカラム → ゾーンに応じてスタックまたはスワップ
                switch dropZone(point: point, in: frame) {
                case .stackAbove:
                    consumeWindowByMouse(draggedID, target: windowID, position: .above)
                case .stackBelow:
                    consumeWindowByMouse(draggedID, target: windowID, position: .below)
                case .swap:
                    niriLog("[drag] swap: \(draggedID) ↔ \(windowID)")
                    for i in screens.indices {
                        for j in screens[i].workspaces.indices {
                            let has1 = screens[i].workspaces[j].columnIndex(for: draggedID) != nil
                            let has2 = screens[i].workspaces[j].columnIndex(for: windowID) != nil
                            if has1 && has2 {
                                screens[i].workspaces[j].swapWindows(draggedID, windowID)
                                break
                            }
                        }
                    }
                case .expel:
                    break  // ここには来ない
                }
            }
            swapCooldownEnd = Date().addingTimeInterval(0.5)
            needsLayout = true
            return
        }

        // どのウィンドウにもドロップされなかった → レイアウトを元に戻す
        niriLog("[drag] mouseUp: no target — restoring layout")
        needsLayout = true
    }
```

- [ ] **Step 6: ビルドして確認する**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

期待値: `Build complete!`

- [ ] **Step 7: 全テストを実行して回帰がないことを確認する**

```bash
swift test 2>&1 | grep -E "✘|passed|failed" | tail -5
```

期待値: 全テスト PASS

- [ ] **Step 8: コミットする**

```bash
git add Sources/NiriMac/Orchestrator/WindowManager.swift
git commit -m "feat: integrate mouse stack/expel into drag flow with 3-zone drop target"
```

---

### Task 4: ビルド＆手動受け入れテスト

- [ ] **Step 1: ビルドしてアプリを起動する**

```bash
swift build && bash make-app.sh && open NiriMac.app
```

- [ ] **Step 2: 別カラムの上1/3にドロップ → 上スタックを確認する**

1. 2カラムに1ウィンドウずつ用意
2. 左カラムのウィンドウをドラッグして右カラムの上1/3に近づける
3. 青い破線枠（上半分）が出ることを確認
4. ドロップ → 右カラムに2ウィンドウが積まれ、ドラッグしたウィンドウが上に来ることを確認

- [ ] **Step 3: 別カラムの下1/3にドロップ → 下スタックを確認する**

1. 同様に下1/3に近づける → 青い破線枠（下半分）が出ることを確認
2. ドロップ → ドラッグしたウィンドウが下に来ることを確認

- [ ] **Step 4: 別カラムの中1/3にドロップ → スワップを確認する**

1. 中央に近づける → 黄色の破線枠が出ることを確認
2. ドロップ → スワップ（位置が入れ替わる）することを確認

- [ ] **Step 5: カラム境界外にドロップ → Expel を確認する**

1. スタック済みのカラムのウィンドウをドラッグしてカラム外へ
2. 赤い破線枠が出ることを確認
3. ドロップ → 独立カラムとして分離されることを確認

- [ ] **Step 6: 単一ウィンドウのカラムをカラム外にドロップ → 何も起きないことを確認する**

1. 1ウィンドウだけのカラムをカラム外へドラッグ
2. 赤枠が出ないことを確認
3. ドロップ → スナップバックして何も変化しないことを確認

- [ ] **Step 7: ログで確認する**

```bash
tail -f /tmp/niri-mac.log | grep -E "drag|stack|expel|swap"
```
