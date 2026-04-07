# Expel / Column Reorder — Design Spec

**Date**: 2026-04-07  
**Status**: Approved

---

## Context

現在の expel（スタック解除）はマウスドラッグで動作するが、以下の問題がある：

1. 単一ウィンドウのカラムはドラッグで移動できない（expel条件 `windowCount > 1` に阻まれる）
2. 横ドラッグと縦ドラッグで同じ検出ロジックが走り、スタックゾーンと expel モードが競合する
3. ゴーストカラム（挿入位置のビジュアルフィードバック）がない

---

## Goal

- **単一ウィンドウカラム**: 横ドラッグでカラムの並び順を変更できる（column reorder）
- **スタックカラム（2枚以上）**: 横ドラッグでウィンドウを切り出し独立カラムにできる（expel）
- **縦ドラッグ**: 従来どおりスタック/スワップゾーンを表示
- **ゴーストカラム**: ドロップ先を半透明プレースホルダーで事前表示

---

## Drag Direction Detection

ドラッグ開始点（mouseDown）から現在点までのΔx・Δyで方向を判定する。  
20px を超えた時点で方向を確定し、以降は切り替えない（ロック）。

| 条件 | モード |
|---|---|
| `\|Δx\| > \|Δy\| × 1.5` | 横ドラッグ → 移動・解除モード |
| `\|Δy\| > \|Δx\| × 1.5` | 縦ドラッグ → スタックモード |
| それ以外（斜め） | 未確定 → オーバーレイなし |

---

## 横ドラッグ — 移動・解除モード

### トリガー条件

- 方向が「横ドラッグ」に確定した時点でモード開始
- カラムの種類によって挙動が分岐する

| カラムの種類 | 横ドラッグの動作 |
|---|---|
| 単一ウィンドウ | カラムごと移動（column reorder） |
| スタック（2枚以上） | そのウィンドウだけ切り出し（expel） |

### ゴーストカラム（視覚フィードバック）

ドラッグ中、現在のカーソルX座標から最も近いカラム間ギャップを計算し、  
そのギャップに半透明のゴーストカラムを表示する。

```
Col 1  │  Col 2  │ 👻Ghost │  Col 3
```

- ゴーストカラムの幅: ドラッグ元カラムの幅と同じ
- 色: `rgba(255,159,64,0.15)` + `1px dashed #ff9f40`
- 最近傍ギャップへスナップ（連続的に更新）

### ドロップ時の処理

```
ゴーストが表示されているギャップ位置に新カラムを挿入
  → 単一ウィンドウカラムの場合: 元カラムを削除して新位置に再挿入（reorder）
  → スタックカラムの場合: 元カラムからウィンドウを除去し、新カラムをギャップに挿入（expel）
```

新カラムの幅は元カラムの幅を引き継ぐ。

---

## 縦ドラッグ — スタックモード

既存の3ゾーン実装を維持する。

| ゾーン | 位置 | 動作 |
|---|---|---|
| 上1/3 | ターゲット上部 | ターゲットの上にスタック |
| 中1/3 | ターゲット中央 | スワップ |
| 下1/3 | ターゲット下部 | ターゲットの下にスタック |

同一カラム内の縦ドラッグは並び替えのみ（既存動作を維持）。

---

## Ghost Column の挿入位置計算

```swift
/// カーソルX座標から最も近いカラム間ギャップのインデックスを返す
/// 返り値: 新カラムを挿入するインデックス（0 = 先頭, columns.count = 末尾）
/// - cursorX: Quartz スクリーン座標系のX（lastComputedFrames と同じ座標系）
private func nearestGapIndex(cursorX: CGFloat, screenIdx: Int) -> Int
```

ギャップ候補はスクリーン座標の `lastComputedFrames` から各カラムの右端Xを収集：  
`[workingArea.minX, col[0].frame.maxX + gap/2, col[1].frame.maxX + gap/2, ..., workingArea.maxX]`  
各ギャップ中点との距離を計算し、最小インデックスを返す。

```swift
/// ゴーストカラムの表示フレームを計算
/// - insertIndex: nearestGapIndex の返り値
/// - 返り値: ゴーストカラムを表示すべきスクリーン座標の CGRect
private func ghostColumnFrame(insertIndex: Int, draggedWindowID: WindowID, screenIdx: Int) -> CGRect?
```

`DropTargetOverlayManager.showGhost(frame:)` に渡す表示フレームを返す。  
幅はドラッグ元カラムの幅、高さは `workingArea.height - gapHeight * 2`。

---

## Architecture

### 変更が必要なファイル

| ファイル | 変更内容 |
|---|---|
| `Sources/NiriMac/Bridge/DropTargetOverlayManager.swift` | `DropZone.ghostColumn` ケース追加、`showGhost(frame:)` API 追加 |
| `Sources/NiriMac/Orchestrator/WindowManager.swift` | ドラッグ方向ロック、`onMouseDragged` でゴーストカラム制御、`handleMouseUp` でギャップ挿入処理、`reorderColumnByMouse` / `expelWindowByMouse(windowID:insertIndex:)` メソッド追加 |

### WindowManager への追加フィールド・メソッド

```swift
/// ドラッグ方向ロック（確定後は変わらない）
private var dragDirectionLock: DragDirection? = nil
enum DragDirection { case horizontal, vertical }

/// ゴーストカラムの挿入予定インデックス（横ドラッグ確定後に更新）
private var ghostInsertIndex: Int? = nil

/// 単一ウィンドウカラムをインデックス toIndex へ移動
private func reorderColumnByMouse(windowID: WindowID, toIndex: Int)

/// スタックカラムからウィンドウを切り出し、インデックス insertIndex に独立カラムとして挿入
private func expelWindowByMouse(windowID: WindowID, insertIndex: Int)
```

### Data Flow

```
leftMouseDragged
    ↓ onMouseDragged(point)
方向判定（dragDirectionLock が nil なら判定、確定後はロック）
    ├─ 横: nearestGapIndex → ghostInsertIndex 更新
    │       → ghostColumnFrame → DropTargetOverlay.showGhost(frame:)
    └─ 縦: 既存スタックゾーン判定 → DropTargetOverlay.show(frame:zone:)

leftMouseUp
    ↓ handleMouseUp(point)
    ├─ 横（ghostInsertIndex あり）
    │   ├─ 単一ウィンドウ → reorderColumnByMouse(windowID:toIndex:)
    │   └─ スタック      → expelWindowByMouse(windowID:insertIndex:)
    └─ 縦（既存）
        ├─ .stackAbove / .stackBelow → consumeWindowByMouse
        └─ .swap → swapWindowsByMouse
```

---

## Error Handling

| 状況 | 挙動 |
|---|---|
| ドロップ先ギャップが元カラムと同じ位置 | 何もしない（no-op） |
| `draggedWindowID` が nil | 即 hide() |
| 方向未確定のままドロップ | 既存のスナップバック動作 |
| `swapCooldownEnd` 内のドロップ | 無視 |

---

## Out of Scope

- ゴーストカラムのアニメーション（フェードイン/アウト）
- ピン留めカラムの reorder
- キーボードショートカットの変更

---

## Verification

```bash
swift build && bash make-app.sh && open NiriMac.app
```

1. 単一ウィンドウカラムを横ドラッグ → ゴーストが各ギャップにスナップ → ドロップでカラム移動
2. スタックカラムのウィンドウを横ドラッグ → ゴーストが表示 → ドロップで独立カラムに切り出し
3. スタックカラムのウィンドウを縦ドラッグ → スタックゾーン（既存）が表示、ゴーストは出ない
4. 斜めドラッグ → どちらのオーバーレイも出ない
5. 横ドラッグで元カラムと同じギャップにドロップ → 何も起きない
