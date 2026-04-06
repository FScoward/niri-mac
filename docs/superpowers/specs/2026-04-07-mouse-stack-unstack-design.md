# Mouse Stack / Unstack — Design Spec

**Date**: 2026-04-07  
**Status**: Approved

---

## Context

現在、カラムへのスタック（consume）とスタック解除（expel）はキーボードショートカットのみ対応している。マウスのみでこれらの操作を完結できるようにする。

---

## Goal

- **スタック**: ウィンドウを別のウィンドウにドラッグ＆ドロップして同じカラムに積める
- **解除（Expel）**: スタックされたウィンドウをカラムの外にドラッグして独立カラムに切り出せる

---

## Visual Design

### スタック操作（ドロップゾーン3分割）

ドラッグ中、ターゲットウィンドウを3つのゾーンに分割して DropTargetOverlay を表示する：

| ゾーン | 位置 | 枠色 | 動作 |
|---|---|---|---|
| 上1/3 | ターゲット上部 | 青破線（`#6b7bff`） | ターゲットの上にスタック |
| 中1/3 | ターゲット中央 | 黄破線（`#ffc800`） | スワップ（現状維持） |
| 下1/3 | ターゲット下部 | 青破線（`#6b7bff`） | ターゲットの下にスタック |

同一カラム内の既存の縦ドラッグ（並び替え）はゾーン判定なしで現状維持。

### 解除操作（カラム境界越えドロップ）

スタックされたカラム（ウィンドウ2つ以上）のウィンドウをドラッグ中：
- カーソルが現在のカラムの左端または右端を越えると「解除モード」へ移行
- DropTargetOverlay を赤破線（`#ff6b6b`）に切り替えて通知
- その状態でドロップ → ドラッグしたウィンドウが独立カラムとして切り出される
- カーソルが現カラムの**左端**を越えた場合 → 現カラムの左に新カラムを挿入
- カーソルが現カラムの**右端**を越えた場合 → 現カラムの右に新カラムを挿入

---

## Architecture

### `DropTargetOverlayManager` の拡張

現在の `show(frame:)` / `hide()` に加えて、ゾーンと色を指定できる API を追加する：

```swift
enum DropZone {
    case stackAbove   // 青破線（上スタック）
    case swap         // 黄破線（スワップ）
    case stackBelow   // 青破線（下スタック）
    case expel        // 赤破線（解除モード）
}

func show(frame: CGRect, zone: DropZone)
```

`CAShapeLayer` の `strokeColor` と `lineDashPattern` を zone に応じて切り替える。

### `Workspace` の拡張

```swift
/// draggedID を targetID のカラムに position で挿入する
/// - .above: targetID の直上に挿入
/// - .below: targetID の直下に挿入
mutating func consumeWindowIntoColumn(
    _ draggedID: WindowID,
    target targetID: WindowID,
    position: ColumnInsertPosition
)

enum ColumnInsertPosition { case above, below }
```

既存の `consumeWindowIntoColumn(screenIdx:direction:)` は `WindowManager` 側のキーボードパスなので変更しない。

### `WindowManager` の変更

#### `onMouseDragged` ハンドラの拡張

```swift
mouse.onMouseDragged = { [weak self] point in
    guard let self, let draggedID = self.draggedWindowID else {
        self?.dropTargetOverlay.hide(); return
    }

    // 1. 解除モード判定: 現カラムの bounds を越えているか
    if let draggedColFrame = self.columnFrame(for: draggedID),
       self.columnWindowCount(for: draggedID) > 1,
       !draggedColFrame.contains(point) {
        // カーソルが現カラム外: 解除モード overlay
        if let draggedFrame = self.lastComputedFrames[draggedID] {
            self.dropTargetOverlay.show(frame: draggedFrame, zone: .expel)
        }
        return
    }

    // 2. スタック/スワップゾーン判定
    for (windowID, frame) in self.lastComputedFrames {
        guard frame.contains(point), windowID != draggedID else { continue }
        let zone = self.dropZone(point: point, in: frame)
        self.dropTargetOverlay.show(frame: frame, zone: zone)
        return
    }
    self.dropTargetOverlay.hide()
}
```

ゾーン判定ヘルパー：

```swift
private func dropZone(point: CGPoint, in frame: CGRect) -> DropZone {
    let third = frame.height / 3
    if point.y < frame.minY + third { return .stackAbove }
    if point.y > frame.maxY - third { return .stackBelow }
    return .swap
}
```

#### `handleMouseUp` の拡張

```swift
private func handleMouseUp(at point: CGPoint) {
    guard let draggedID = draggedWindowID else { return }
    draggedWindowID = nil

    // 解除モード: 現カラム外にドロップ
    if let draggedColFrame = columnFrame(for: draggedID),
       columnWindowCount(for: draggedID) > 1,
       !draggedColFrame.contains(point) {
        expelWindowFromColumn(for: draggedID, dropX: point.x)
        swapCooldownEnd = Date().addingTimeInterval(0.5)
        needsLayout = true
        return
    }

    // スタック/スワップ: ターゲット探索
    for (windowID, frame) in lastComputedFrames {
        guard frame.contains(point), windowID != draggedID else { continue }
        let zone = dropZone(point: point, in: frame)
        switch zone {
        case .stackAbove:
            consumeWindowIntoColumnByMouse(draggedID, target: windowID, position: .above)
        case .stackBelow:
            consumeWindowIntoColumnByMouse(draggedID, target: windowID, position: .below)
        case .swap:
            swapWindowsByMouse(draggedID, windowID)
        case .expel:
            break  // ここには来ない
        }
        swapCooldownEnd = Date().addingTimeInterval(0.5)
        needsLayout = true
        return
    }

    // どこにもドロップしなかった → レイアウト復元
    needsLayout = true
}
```

### `expelWindowFromColumn(for:dropX:)` の実装

`WindowManager` の既存 `expelWindowFromColumn(screenIdx:)` はキーボード用（アクティブウィンドウを追い出す）。マウス用は任意の `windowID` と drop X 位置を受け取る新メソッドとして追加する。

---

## Data Flow

```
leftMouseDragged
    ↓ onMouseDragged(point)
WindowManager
    ├─ カラム外 → DropTargetOverlay.show(.expel)
    └─ ターゲット上 → DropTargetOverlay.show(zone: .stackAbove/.swap/.stackBelow)

leftMouseUp
    ↓ handleMouseUp(point)
WindowManager
    ├─ カラム外ドロップ → expelWindowFromColumn(for:dropX:)
    ├─ .stackAbove/.stackBelow → consumeWindowIntoColumnByMouse(_:target:position:)
    └─ .swap → swapWindowsByMouse(_:_:)
```

---

## Error Handling

- `draggedWindowID` が nil → 即 hide()
- 単一ウィンドウのカラムからのドラッグ → 解除モードに入らない（`columnWindowCount > 1` 条件）
- ドロップ先なし → 既存スナップバック動作を維持
- `swapCooldownEnd` で 0.5秒間の誤検知防止は既存通り

---

## Out of Scope

- スタック操作のアニメーション
- 同一カラム内の縦ドラッグへのゾーン適用（既存の並び替え動作を維持）
- キーボードショートカットの変更

---

## Files to Create / Modify

| ファイル | 変更内容 |
|---|---|
| `Sources/NiriMac/Bridge/DropTargetOverlayManager.swift` | `DropZone` enum 追加、`show(frame:zone:)` に拡張 |
| `Sources/NiriMac/Core/Workspace.swift` | `consumeWindowIntoColumn(_:target:position:)` 追加 |
| `Sources/NiriMac/Orchestrator/WindowManager.swift` | `onMouseDragged` 拡張、`handleMouseUp` 拡張、`expelWindowFromColumn(for:side:)` 追加、`columnFrame(for:)` / `columnWindowCount(for:)` / `dropZone(point:in:)` ヘルパー追加 |

---

## Verification

```bash
swift build && bash make-app.sh && open NiriMac.app
```

1. 2カラムに1ウィンドウずつ用意
2. 左カラムのウィンドウを右カラムのウィンドウの上1/3にドロップ → 右カラムの上にスタック
3. 同じく下1/3 → 右カラムの下にスタック
4. 同じく中1/3 → スワップ（現状維持）
5. スタックされたカラムのウィンドウをカラム外にドロップ → 独立カラムとして分離
6. 単一ウィンドウのカラムをカラム外にドロップ → 何も起きない（解除モードに入らない）
