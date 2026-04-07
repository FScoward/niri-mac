# Expel / Column Reorder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ドラッグ方向（横/縦）で操作モードを自動判別し、横ドラッグ時はゴーストカラムによる挿入位置プレビュー付きで expel / column reorder を行う。

**Architecture:** `LayoutEngine` に純粋関数 `nearestGapIndex` を追加してテスト可能にする。`DropTargetOverlayManager` にゴーストカラム表示 API を追加する。`WindowManager` でドラッグ方向ロックとゴーストインデックスを管理し、mouseUp 時に横/縦を分岐させる。

**Tech Stack:** Swift, AppKit, CoreGraphics, CVDisplayLink

---

## ファイル構成

| ファイル | 変更 |
|---|---|
| `Sources/NiriMac/Bridge/DropTargetOverlayManager.swift` | `DropZone.ghostColumn` 追加、`showGhost(frame:)` 追加 |
| `Sources/NiriMac/Engine/LayoutEngine.swift` | `nearestGapIndex` static メソッド追加 |
| `Sources/NiriMac/Orchestrator/WindowManager.swift` | 新フィールド、`onMouseDown`/`onMouseDragged`/`handleMouseUp` 書き換え、`reorderColumnByMouse`/`expelWindowByMouse(insertIndex:)` 追加 |
| `Tests/NiriMacTests/TestTypes.swift` | `LayoutEngine.nearestGapIndex` 追加（production と同一実装） |
| `Tests/NiriMacTests/ExpelColumnReorderTests.swift` | 新規テストファイル |

---

### Task 1: DropTargetOverlayManager — ghostColumn ゾーン追加

**Files:**
- Modify: `Sources/NiriMac/Bridge/DropTargetOverlayManager.swift`

- [ ] **Step 1: `DropZone` に `.ghostColumn` ケースを追加する**

`DropTargetOverlayManager.swift` の `enum DropZone` を以下に変更：

```swift
enum DropZone {
    case stackAbove   // 青破線: ターゲットの上にスタック
    case swap         // 黄破線: スワップ（現状維持）
    case stackBelow   // 青破線: ターゲットの下にスタック
    case expel        // 赤破線: 解除モード（旧）
    case ghostColumn  // オレンジ破線: 横ドラッグ挿入プレビュー
}
```

- [ ] **Step 2: `zoneColors` に `.ghostColumn` を追加する**

`zoneColors` メソッドの switch に追加：

```swift
case .ghostColumn:
    return (
        NSColor(red: 1.0, green: 0.62, blue: 0.25, alpha: 1.0).cgColor,   // #ff9f40
        NSColor(red: 1.0, green: 0.62, blue: 0.25, alpha: 0.12).cgColor
    )
```

- [ ] **Step 3: `showGhost(frame:)` 公開 API を追加する**

`DropTargetOverlayManager` クラス内の `hide()` の直後に追加：

```swift
/// 横ドラッグ中のゴーストカラム挿入位置をオレンジ破線で表示する（Quartz座標系）
func showGhost(frame: CGRect) {
    show(frame: frame, zone: .ghostColumn)
}
```

- [ ] **Step 4: ビルドが通ることを確認する**

```bash
swift build 2>&1 | tail -5
```

期待: `Build complete!`

- [ ] **Step 5: コミット**

```bash
git add Sources/NiriMac/Bridge/DropTargetOverlayManager.swift
git commit -m "feat: DropTargetOverlayManager に ghostColumn ゾーンと showGhost(frame:) を追加"
```

---

### Task 2: LayoutEngine — nearestGapIndex 純粋関数追加

**Files:**
- Modify: `Sources/NiriMac/Engine/LayoutEngine.swift`
- Modify: `Tests/NiriMacTests/TestTypes.swift`
- Create: `Tests/NiriMacTests/ExpelColumnReorderTests.swift`

- [ ] **Step 1: テストファイルを作成して失敗するテストを書く**

`Tests/NiriMacTests/ExpelColumnReorderTests.swift` を新規作成：

```swift
import XCTest
@testable import NiriMac

final class ExpelColumnReorderTests: XCTestCase {

    // workingArea: x=0, y=0, w=1800, h=1000
    // gap=16, col幅=580 (≈1/3), columns=[A, B, C]
    // col[0]: screenX = 0+16+0 = 16, right = 596
    // col[1]: screenX = 16+580+16 = 612, right = 1192
    // col[2]: screenX = 1192+16 = 1208, right = 1788
    // gapPositions: [8, 604, 1200, 1796]
    //   index 0 = 8   (先頭)
    //   index 1 = 604 (col[0]の後ろ)
    //   index 2 = 1200(col[1]の後ろ)
    //   index 3 = 1796(col[2]の後ろ = 末尾)

    private func makeWorkspace() -> Workspace {
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1800, height: 1000))
        ws.columns = [
            Column(windows: [1], width: 580),
            Column(windows: [2], width: 580),
            Column(windows: [3], width: 580),
        ]
        ws.viewOffset = .static(offset: 0)
        return ws
    }

    private var config: LayoutConfig { LayoutConfig(gapWidth: 16, gapHeight: 16) }

    func test_nearestGapIndex_beforeFirstColumn() {
        let ws = makeWorkspace()
        // cursorX=0 → nearest gap index 0 (先頭)
        let idx = LayoutEngine.nearestGapIndex(cursorX: 0, workspace: ws, config: config)
        XCTAssertEqual(idx, 0)
    }

    func test_nearestGapIndex_afterFirstColumn() {
        let ws = makeWorkspace()
        // cursorX=700 → nearest is gap[1]=604, index 1
        let idx = LayoutEngine.nearestGapIndex(cursorX: 700, workspace: ws, config: config)
        XCTAssertEqual(idx, 1)
    }

    func test_nearestGapIndex_middleOfScreen() {
        let ws = makeWorkspace()
        // cursorX=900 → nearest is gap[2]=1200? No, 1200-900=300, 900-604=296 → index 1
        let idx = LayoutEngine.nearestGapIndex(cursorX: 900, workspace: ws, config: config)
        XCTAssertEqual(idx, 1)
    }

    func test_nearestGapIndex_afterLastColumn() {
        let ws = makeWorkspace()
        // cursorX=1790 → nearest is gap[3]=1796, index 3
        let idx = LayoutEngine.nearestGapIndex(cursorX: 1790, workspace: ws, config: config)
        XCTAssertEqual(idx, 3)
    }

    func test_nearestGapIndex_withScrollOffset() {
        var ws = makeWorkspace()
        ws.viewOffset = .static(offset: -200)  // 200px 左にスクロール
        // col[0]: screenX=16-200=-184, right=396
        // gap[0]=8, gap[1]=404, gap[2]=1000, gap[3]=1596
        // cursorX=500 → nearest gap[2]=1000? |500-404|=96, |500-1000|=500 → index 1
        let idx = LayoutEngine.nearestGapIndex(cursorX: 500, workspace: ws, config: config)
        XCTAssertEqual(idx, 1)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
swift test --filter ExpelColumnReorderTests 2>&1 | tail -10
```

期待: `error: ... 'nearestGapIndex' is not a member of 'LayoutEngine'`

- [ ] **Step 3: `LayoutEngine.swift` に `nearestGapIndex` を追加する**

`Sources/NiriMac/Engine/LayoutEngine.swift` の末尾（`}` の直前）に追加：

```swift
/// カーソルX（Quartz スクリーン座標）から最も近いカラム間ギャップのインデックスを返す。
/// - 返り値: 新カラムを挿入するインデックス（0=先頭, columns.count=末尾）
static func nearestGapIndex(
    cursorX: CGFloat,
    workspace: Workspace,
    config: LayoutConfig
) -> Int {
    let gap = config.gapWidth
    let xs = workspace.columnXPositions(gap: gap)
    let offset = workspace.viewOffset.current
    let workingMinX = workspace.workingArea.minX

    // ギャップ中点 X を収集: 先頭 + 各カラム右端+gap/2
    var gapPositions: [CGFloat] = []
    gapPositions.append(workingMinX + gap / 2)  // 先頭（index 0）

    for (i, col) in workspace.columns.enumerated() {
        let colScreenX = workingMinX + gap + xs[i] + offset
        let colRightX = colScreenX + col.width
        gapPositions.append(colRightX + gap / 2)  // col[i]の後ろ（index i+1）
    }

    var nearestIdx = 0
    var minDist = CGFloat.greatestFiniteMagnitude
    for (i, gapX) in gapPositions.enumerated() {
        let dist = abs(cursorX - gapX)
        if dist < minDist { minDist = dist; nearestIdx = i }
    }
    return nearestIdx
}
```

- [ ] **Step 4: TestTypes.swift の `LayoutEngine` にも同じ実装を追加する**

`Tests/NiriMacTests/TestTypes.swift` の `LayoutEngine` enum 末尾に追加（production と同一実装）：

```swift
static func nearestGapIndex(
    cursorX: CGFloat,
    workspace: Workspace,
    config: LayoutConfig
) -> Int {
    let gap = config.gapWidth
    let xs = workspace.columnXPositions(gap: gap)
    let offset = workspace.viewOffset.current
    let workingMinX = workspace.workingArea.minX

    var gapPositions: [CGFloat] = []
    gapPositions.append(workingMinX + gap / 2)

    for (i, col) in workspace.columns.enumerated() {
        let colScreenX = workingMinX + gap + xs[i] + offset
        let colRightX = colScreenX + col.width
        gapPositions.append(colRightX + gap / 2)
    }

    var nearestIdx = 0
    var minDist = CGFloat.greatestFiniteMagnitude
    for (i, gapX) in gapPositions.enumerated() {
        let dist = abs(cursorX - gapX)
        if dist < minDist { minDist = dist; nearestIdx = i }
    }
    return nearestIdx
}
```

- [ ] **Step 5: テストが通ることを確認する**

```bash
swift test --filter ExpelColumnReorderTests 2>&1 | tail -10
```

期待: `Test Suite 'ExpelColumnReorderTests' passed`

- [ ] **Step 6: 全テストが通ることを確認する**

```bash
swift test 2>&1 | tail -5
```

期待: `Test Suite 'All tests' passed`

- [ ] **Step 7: コミット**

```bash
git add Sources/NiriMac/Engine/LayoutEngine.swift \
        Tests/NiriMacTests/TestTypes.swift \
        Tests/NiriMacTests/ExpelColumnReorderTests.swift
git commit -m "feat: LayoutEngine.nearestGapIndex 追加 + テスト"
```

---

### Task 3: WindowManager — 新フィールドと mouseDownPoint 追加

**Files:**
- Modify: `Sources/NiriMac/Orchestrator/WindowManager.swift`

- [ ] **Step 1: 新フィールドを追加する**

`WindowManager` クラス内の `private let dragThreshold: CGFloat = 20` の直後に追加：

```swift
/// ドラッグ方向ロック（確定後は mouseUp まで変わらない）
private var dragDirectionLock: DragDirection? = nil
private enum DragDirection { case horizontal, vertical }

/// ゴーストカラムの挿入予定インデックス（横ドラッグ確定後に更新）
private var ghostInsertIndex: Int? = nil

/// MouseDown 時のカーソル座標（方向判定用）
private var mouseDownPoint: CGPoint? = nil
```

- [ ] **Step 2: `onMouseDown` コールバックに新フィールドのリセットと mouseDownPoint 記録を追加する**

`setupMouse()` 内の `mouse.onMouseDown` クロージャを以下に置き換える（`niriLog` 行の前に追加）：

```swift
mouse.onMouseDown = { [weak self] point in
    guard let self else { return }
    self.isMouseDown = true
    self.dragDirectionLock = nil     // 追加
    self.ghostInsertIndex = nil      // 追加
    self.mouseDownPoint = point      // 追加
    for (windowID, frame) in self.lastComputedFrames {
        if frame.contains(point) {
            self.mouseDownWindowID = windowID
            self.mouseDownFrame = frame
            break
        }
    }
    niriLog("[drag-dbg] mouseDown: win=\(String(describing: self.mouseDownWindowID)) point=\(point)")
    self.handleMouseFocus(at: point)
}
```

- [ ] **Step 3: ビルドが通ることを確認する**

```bash
swift build 2>&1 | tail -5
```

期待: `Build complete!`

- [ ] **Step 4: コミット**

```bash
git add Sources/NiriMac/Orchestrator/WindowManager.swift
git commit -m "feat: WindowManager にドラッグ方向フィールドと mouseDownPoint を追加"
```

---

### Task 4: WindowManager — onMouseDragged を方向検出ロジックへ書き換え

**Files:**
- Modify: `Sources/NiriMac/Orchestrator/WindowManager.swift`

- [ ] **Step 1: `ghostColumnFrame` ヘルパーメソッドを追加する**

`WindowManager` 内の `dropZone(point:in:)` メソッドの直前に追加：

```swift
/// 挿入インデックスに対応するゴーストカラムの表示フレーム（Quartz座標）を返す
private func ghostColumnFrame(insertIndex: Int, draggedWindowID: WindowID, screenIdx: Int) -> CGRect? {
    guard screenIdx < screens.count else { return nil }
    let ws = screens[screenIdx].activeWorkspace
    let gap = config.gapWidth
    guard let sourceColIdx = ws.columnIndex(for: draggedWindowID) else { return nil }
    let ghostWidth = ws.columns[sourceColIdx].width
    let xs = ws.columnXPositions(gap: gap)
    let offset = ws.viewOffset.current
    let workingMinX = ws.workingArea.minX

    let ghostX: CGFloat
    if insertIndex == 0 {
        ghostX = workingMinX + gap
    } else {
        let prevColIdx = insertIndex - 1
        guard prevColIdx < xs.count else { return nil }
        let prevColScreenX = workingMinX + gap + xs[prevColIdx] + offset
        ghostX = prevColScreenX + ws.columns[prevColIdx].width + gap
    }

    return CGRect(
        x: ghostX,
        y: ws.workingArea.minY + gap,
        width: ghostWidth,
        height: ws.workingArea.height - gap * 2
    )
}
```

- [ ] **Step 2: `onMouseDragged` クロージャを方向検出ロジックに書き換える**

`setupMouse()` 内の `mouse.onMouseDragged = { ... }` ブロック全体を以下に置き換える：

```swift
mouse.onMouseDragged = { [weak self] point in
    guard let self, let draggedID = self.draggedWindowID else {
        self?.dropTargetOverlay.hide()
        return
    }

    // 方向未確定なら Δx/Δy で判定（閾値: 1.5倍以上の差）
    if self.dragDirectionLock == nil, let downPoint = self.mouseDownPoint {
        let dx = abs(point.x - downPoint.x)
        let dy = abs(point.y - downPoint.y)
        if dx > dy * 1.5 {
            self.dragDirectionLock = .horizontal
            niriLog("[drag] direction locked: horizontal")
        } else if dy > dx * 1.5 {
            self.dragDirectionLock = .vertical
            niriLog("[drag] direction locked: vertical")
        }
    }

    switch self.dragDirectionLock {
    case .horizontal:
        // ゴーストカラムを最近傍ギャップにスナップ
        let screenIdx = self.activeScreenIndex()
        let insertIdx = LayoutEngine.nearestGapIndex(
            cursorX: point.x,
            workspace: self.screens[screenIdx].activeWorkspace,
            config: self.config
        )
        self.ghostInsertIndex = insertIdx
        if let ghostFrame = self.ghostColumnFrame(
            insertIndex: insertIdx,
            draggedWindowID: draggedID,
            screenIdx: screenIdx
        ) {
            self.dropTargetOverlay.showGhost(frame: ghostFrame)
        }

    case .vertical:
        // 既存のスタックゾーン判定
        for (windowID, frame) in self.lastComputedFrames {
            guard frame.contains(point), windowID != draggedID else { continue }
            let zone: DropZone = self.isSameColumn(draggedID, windowID)
                ? .swap
                : self.dropZone(point: point, in: frame)
            self.dropTargetOverlay.show(frame: frame, zone: zone)
            return
        }
        self.dropTargetOverlay.hide()

    case nil:
        // 方向未確定: オーバーレイなし
        self.dropTargetOverlay.hide()
    }
}
```

- [ ] **Step 3: ビルドが通ることを確認する**

```bash
swift build 2>&1 | tail -5
```

期待: `Build complete!`

- [ ] **Step 4: コミット**

```bash
git add Sources/NiriMac/Orchestrator/WindowManager.swift
git commit -m "feat: onMouseDragged を方向検出（横=ゴーストカラム/縦=スタックゾーン）に書き換え"
```

---

### Task 5: WindowManager — reorderColumnByMouse + expelWindowByMouse(insertIndex:) 追加

**Files:**
- Modify: `Sources/NiriMac/Orchestrator/WindowManager.swift`

- [ ] **Step 1: `reorderColumnByMouse` を追加する**

既存の `expelWindowByMouse(windowID:side:)` の直前に追加：

```swift
/// 単一ウィンドウカラムをインデックス toIndex の位置に移動する（column reorder）
private func reorderColumnByMouse(windowID: WindowID, toIndex: Int, screenIdx: Int) {
    niriLog("[drag] reorder: win=\(windowID) → index \(toIndex)")
    guard screenIdx < screens.count else { return }
    var ws = screens[screenIdx].activeWorkspace
    guard let colIdx = ws.columnIndex(for: windowID) else { return }

    // 移動なし: toIndex が現在のカラムの前後のどちらか
    guard toIndex != colIdx, toIndex != colIdx + 1 else {
        niriLog("[drag] reorder: no-op (same position)")
        return
    }

    let col = ws.columns.remove(at: colIdx)
    // colIdx より後ろの insertIndex は 1 ずれる
    let adjustedIdx = toIndex > colIdx ? toIndex - 1 : toIndex
    let safeIdx = min(max(adjustedIdx, 0), ws.columns.count)
    ws.columns.insert(col, at: safeIdx)
    ws.activeColumnIndex = safeIdx
    ws.recenterViewOffset(gap: config.gapWidth)
    screens[screenIdx].activeWorkspace = ws
}
```

- [ ] **Step 2: `expelWindowByMouse(windowID:insertIndex:screenIdx:)` を追加する**

`reorderColumnByMouse` の直後に追加：

```swift
/// スタックカラムからウィンドウを切り出し、insertIndex の位置に独立カラムとして挿入する
private func expelWindowByMouse(windowID: WindowID, insertIndex: Int, screenIdx: Int) {
    niriLog("[drag] expel: win=\(windowID) → index \(insertIndex)")
    guard screenIdx < screens.count else { return }
    var ws = screens[screenIdx].activeWorkspace
    guard let colIdx = ws.columnIndex(for: windowID),
          ws.columns[colIdx].windows.count > 1 else { return }

    let sourceColWidth = ws.columns[colIdx].width
    ws.columns[colIdx].removeWindow(windowID)
    // ウィンドウを除去しても元カラムは残る（count > 1 保証）
    let newColumn = Column(windows: [windowID], width: sourceColWidth)
    let safeIdx = min(max(insertIndex, 0), ws.columns.count)
    ws.addColumn(newColumn, at: safeIdx)
    ws.focusColumn(at: safeIdx)
    ws.recenterViewOffset(gap: config.gapWidth)
    screens[screenIdx].activeWorkspace = ws
}
```

- [ ] **Step 3: ビルドが通ることを確認する**

```bash
swift build 2>&1 | tail -5
```

期待: `Build complete!`

- [ ] **Step 4: コミット**

```bash
git add Sources/NiriMac/Orchestrator/WindowManager.swift
git commit -m "feat: reorderColumnByMouse + expelWindowByMouse(insertIndex:) を追加"
```

---

### Task 6: WindowManager — handleMouseUp を横/縦分岐に書き換え

**Files:**
- Modify: `Sources/NiriMac/Orchestrator/WindowManager.swift`

- [ ] **Step 1: `handleMouseUp` を書き換える**

既存の `handleMouseUp(at:)` メソッド全体を以下に置き換える：

```swift
/// ドラッグ終了時の処理。方向ロックに応じてモードを分岐する。
private func handleMouseUp(at point: CGPoint) {
    defer {
        dragDirectionLock = nil
        ghostInsertIndex = nil
    }
    guard let draggedID = draggedWindowID else { return }
    draggedWindowID = nil

    let screenIdx = activeScreenIndex()

    // 横ドラッグ: ゴーストカラム挿入
    if dragDirectionLock == .horizontal, let insertIdx = ghostInsertIndex {
        guard screenIdx < screens.count else { needsLayout = true; return }
        let ws = screens[screenIdx].activeWorkspace
        let windowCount = ws.columnIndex(for: draggedID)
            .map { ws.columns[$0].windows.count } ?? 0

        if windowCount == 1 {
            reorderColumnByMouse(windowID: draggedID, toIndex: insertIdx, screenIdx: screenIdx)
        } else if windowCount > 1 {
            expelWindowByMouse(windowID: draggedID, insertIndex: insertIdx, screenIdx: screenIdx)
        }
        swapCooldownEnd = Date().addingTimeInterval(0.5)
        needsLayout = true
        return
    }

    // 縦ドラッグ（または方向未確定）: 既存のターゲット検出 → スタック/スワップ

    // Priority 1: カーソルヒット
    var targetID: WindowID? = nil
    var targetFrame: CGRect = .zero
    for (windowID, frame) in lastComputedFrames {
        guard windowID != draggedID, frame.contains(point) else { continue }
        targetID = windowID; targetFrame = frame; break
    }

    // Priority 2: フレームオーバーラップ最大
    if targetID == nil, let draggedFrame = axBridge.windowFrame(draggedID) {
        var bestOverlap: CGFloat = 0
        for (windowID, frame) in lastComputedFrames {
            guard windowID != draggedID else { continue }
            let intersection = draggedFrame.intersection(frame)
            guard !intersection.isNull else { continue }
            let overlap = intersection.width * intersection.height
            if overlap > bestOverlap {
                bestOverlap = overlap; targetID = windowID; targetFrame = frame
            }
        }
    }

    guard let target = targetID else {
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
        for i in screens.indices {
            for j in screens[i].workspaces.indices {
                let has1 = screens[i].workspaces[j].columnIndex(for: draggedID) != nil
                let has2 = screens[i].workspaces[j].columnIndex(for: target) != nil
                if has1 && has2 { screens[i].workspaces[j].swapWindows(draggedID, target); break }
            }
        }
    } else {
        switch zone {
        case .stackAbove:
            consumeWindowByMouse(draggedID, target: target, position: .above)
        case .stackBelow:
            consumeWindowByMouse(draggedID, target: target, position: .below)
        case .swap:
            for i in screens.indices {
                for j in screens[i].workspaces.indices {
                    let has1 = screens[i].workspaces[j].columnIndex(for: draggedID) != nil
                    let has2 = screens[i].workspaces[j].columnIndex(for: target) != nil
                    if has1 && has2 { screens[i].workspaces[j].swapWindows(draggedID, target); break }
                }
            }
        case .stackAbove, .stackBelow, .swap, .expel, .ghostColumn:
            break
        }
    }
    swapCooldownEnd = Date().addingTimeInterval(0.5)
    needsLayout = true
}
```

**注意**: switch の `case .ghostColumn` は到達しないが、exhaustive チェックのために記述する（`.expel` も到達しないが既存のため残す）。実際に重複している case は Swift コンパイラが警告するため、`.stackAbove, .stackBelow, .swap` の後に `.expel, .ghostColumn: break` として1行にまとめる。以下が正確なコード：

```swift
switch zone {
case .stackAbove:
    consumeWindowByMouse(draggedID, target: target, position: .above)
case .stackBelow:
    consumeWindowByMouse(draggedID, target: target, position: .below)
case .swap:
    for i in screens.indices {
        for j in screens[i].workspaces.indices {
            let has1 = screens[i].workspaces[j].columnIndex(for: draggedID) != nil
            let has2 = screens[i].workspaces[j].columnIndex(for: target) != nil
            if has1 && has2 {
                screens[i].workspaces[j].swapWindows(draggedID, target)
                break
            }
        }
    }
case .expel, .ghostColumn:
    break  // 縦ドラッグパスでは到達しない
}
```

- [ ] **Step 2: ビルドが通ることを確認する**

```bash
swift build 2>&1 | tail -5
```

期待: `Build complete!`

- [ ] **Step 3: 全テストが通ることを確認する**

```bash
swift test 2>&1 | tail -5
```

期待: `Test Suite 'All tests' passed`

- [ ] **Step 4: コミット**

```bash
git add Sources/NiriMac/Orchestrator/WindowManager.swift
git commit -m "feat: handleMouseUp を横/縦方向で分岐（横=ゴースト挿入、縦=スタック/スワップ）"
```

---

### Task 7: クリーンアップ — 旧 expelWindowByMouse(side:) と DragSide 削除

**Files:**
- Modify: `Sources/NiriMac/Orchestrator/WindowManager.swift`

- [ ] **Step 1: 旧 `expelWindowByMouse(windowID:side:)` と `DragSide` enum を削除する**

`WindowManager.swift` から以下のコードを削除する：

```swift
private enum DragSide { case left, right }

/// マウスドラッグによる Expel: windowID を含むカラムから切り出して独立カラムにする
private func expelWindowByMouse(windowID: WindowID, side: DragSide) {
    // ... 全体
}
```

（検索キー: `private enum DragSide` と `private func expelWindowByMouse(windowID: WindowID, side: DragSide)`）

- [ ] **Step 2: デバッグログをクリーンアップする**

`[drag-dbg]` プレフィックスのログ行を削除する（`niriLog("[drag-dbg]` を検索して削除）。

- [ ] **Step 3: ビルドが通ることを確認する**

```bash
swift build 2>&1 | tail -5
```

期待: `Build complete!`

- [ ] **Step 4: 全テストが通ることを確認する**

```bash
swift test 2>&1 | tail -5
```

期待: `Test Suite 'All tests' passed`

- [ ] **Step 5: 動作確認**

```bash
bash make-app.sh && open NiriMac.app
tail -f /tmp/niri-mac.log | grep -E "\[drag\]"
```

確認手順:
1. 単一ウィンドウカラムを**横**にドラッグ → オレンジ破線のゴーストカラムがギャップにスナップ → ドロップでカラム移動
2. スタックカラムのウィンドウを**横**にドラッグ → ゴーストが表示 → ドロップで独立カラムに切り出し
3. スタックカラムのウィンドウを**縦**にドラッグ → 青/黄破線の3ゾーンが表示、ゴーストは出ない
4. 斜めドラッグ → どちらのオーバーレイも出ない
5. 横ドラッグで元位置と同じギャップにドロップ → 何も起きない（no-op）

- [ ] **Step 6: コミット**

```bash
git add Sources/NiriMac/Orchestrator/WindowManager.swift
git commit -m "refactor: 旧 expelWindowByMouse(side:) と DragSide を削除、デバッグログ整理"
```
