# niri-mac タイリングウィンドウマネージャー 仕様書

## 概要

niri-mac は macOS 向けの無限水平スクロール型タイリング WM（ウィンドウマネージャー）である。
Linux 向けの [niri](https://github.com/YaLTeR/niri) にインスパイアされた設計で、ウィンドウを「カラム（列）」に整理し、
水平スクロールで移動できる無限の仮想デスクトップを提供する。

---

## 0. 要件（Requirements）

ユーザーが期待する振る舞いの約束。実装の詳細に依存しない。

---

### R-01 workingArea の外に完全に出たウィンドウは非表示にする

> スクロール位置によって画面端に近いウィンドウが部分的に見えること（見切れ）は正常な動作である。
> ただし、アニメーション完了後に workingArea と一切交差しなくなったウィンドウは非表示でなければならない。

**Scenario 1: キーボードフォーカス移動後、完全に画面外のカラムが非表示になる**

```
Given  5つのカラムが並んでおり、左から3番目（中央）にフォーカスがある
And    左から1番目のカラムは workingArea と全く交差していない（完全に左外）
And    左から5番目のカラムは workingArea と全く交差していない（完全に右外）
When   アニメーションが完了した
Then   1番目のカラムのウィンドウは非表示になっている
And    5番目のカラムのウィンドウは非表示になっている
And    2〜4番目のカラムのウィンドウは表示されている（一部見切れも含む）
```

**Example:**

workingArea = x: 0〜2560px、各カラム幅 = 800px、gap = 16px とする

| カラム | frame.minX | frame.maxX | workingArea との交差 | 期待状態 |
|--------|-----------|-----------|-------------------|---------|
| col1 | -832 | -32 | なし（完全に左外） | **非表示** |
| col2 | -16 | 800 | あり（一部見切れ） | 表示中 |
| col3 | 816 | 1616 | あり（完全に画面内） | 表示中 |
| col4 | 1632 | 2432 | あり（一部見切れ） | 表示中 |
| col5 | 2448 | 3248 | なし（完全に右外） | **非表示** |

---

### R-02 フォーカス移動後のアクティブカラム表示

> キーボードでフォーカスを移動したとき、アクティブカラムは画面内に完全に収まっていなければならない。

**Scenario 2: フォーカス移動後、アクティブカラムが画面に収まる**

```
Given  複数カラムが存在する
When   Ctrl+Opt+← / → でフォーカスを移動し、アニメーションが完了した
Then   アクティブカラム全体が workingArea 内に表示されている
```

---

### R-03 連続スクロール中のちらつき禁止

> トラックパッドの連続スクロール中（慣性スクロール含む）、workingArea と交差しているウィンドウが不意に消えてはならない。

**Scenario 3: スクロール中に画面と交差しているウィンドウが消えない**

```
Given  ウィンドウが workingArea と交差して表示されている
When   トラックパッドで連続スクロールしており、ViewOffset がアニメーション中である
Then   そのウィンドウは表示され続ける（パークされない）
```

**Example:**

workingArea = x: 0〜2560px、ウィンドウ幅 = 800px とする

| frame.minX | frame.maxX | workingArea との交差 | アニメーション中の期待 |
|-----------|-----------|-------------------|------------------|
| -100 | 700 | あり（左から100pxはみ出し） | **表示継続** |
| 1900 | 2700 | あり（右から140pxはみ出し） | **表示継続** |
| -820 | -20 | なし（完全に左外） | 非表示 |
| 2580 | 3380 | なし（完全に右外） | 非表示 |

---

### R-04 カラム幅の変更

> ユーザーはキーボードまたはマウスでアクティブカラムの幅を変更できる。

**Scenario 5: キーボードでカラム幅がサイクルする**

```
Given  アクティブカラムの幅が screenWidth の 33% である
When   Ctrl+Opt+T を押す
Then   カラム幅が screenWidth の 50% になる

Given  アクティブカラムの幅が screenWidth の 50% である
When   Ctrl+Opt+T を押す
Then   カラム幅が screenWidth の 67% になる

Given  アクティブカラムの幅が screenWidth の 67% 以上である
When   Ctrl+Opt+T を押す
Then   カラム幅が screenWidth の 33% に戻る
```

**Scenario 6: カラム境界線のドラッグで幅を自由に変更できる**

```
Given  隣接する2つのカラムが表示されている
When   カラムの境界線をマウスでドラッグする
Then   ドラッグ量に応じてカラム幅が 1% 単位で変化する
And    幅は screenWidth の 1% 〜 99% の範囲に制限される
And    ドラッグ中もレイアウトがリアルタイムに更新される
And    ドラッグを離した時点の幅が確定する
```

**Example:**

| スクリーン幅 | ドラッグ前幅 | ドラッグ量 | ドラッグ後幅 |
|------------|------------|-----------|------------|
| 2560px | 853px (33%) | +128px | 981px (38%) |
| 2560px | 853px (33%) | -128px | 725px (28%) |
| 2560px | 2534px (99%) | +100px | 2534px (99%、上限クランプ) |

---

### R-05 ワークスペース分離

> ワークスペースを切り替えたとき、前のワークスペースのウィンドウは表示されない。

**Scenario 6: ワークスペース切り替え後の分離**

```
Given  ワークスペース A にウィンドウが3つあり、ワークスペース B は空である
When   Ctrl+Opt+Cmd+↓ でワークスペース B に切り替えた
Then   ワークスペース A のウィンドウは画面に表示されていない
And    ワークスペース B の画面は空である
```

---

### R-06 新規ウィンドウの自動取り込み

> 新しいウィンドウが開いたとき、自動でレイアウトに取り込まれ、フォーカスが移る。

**Scenario 7: 新規ウィンドウが追加される**

```
Given  2カラムのレイアウトが表示されている
When   新しいアプリのウィンドウが開く
Then   そのウィンドウが新規カラムとしてレイアウトに追加される
And    新規ウィンドウにフォーカスが移る
And    新規カラムが画面内に収まるようスクロール位置が調整される
```

---

### R-07 ウィンドウ破棄後のレイアウト再整合

> ウィンドウを閉じたとき、残りのウィンドウのレイアウトとフォーカスが自動で再整合される。

**Scenario 8: ウィンドウを閉じた後のフォーカス**

```
Given  3カラムのレイアウトで中央カラムにフォーカスがある
When   中央カラムのウィンドウを閉じる
Then   中央カラムが削除される
And    残りのカラムのいずれかにフォーカスが移る
And    フォーカスされたカラムが画面内に収まるようスクロール位置が調整される
```

---

## 1. データモデル

### 階層構造

```
Screen（物理モニター）
└── Workspace（仮想デスクトップ）[複数]
    ├── ViewOffset（スクロール位置）
    ├── workingArea: CGRect（メニューバー・Dock除き）
    └── Column（縦積みウィンドウ列）[複数]
        ├── windows: [WindowID]
        ├── activeWindowIndex: Int
        ├── width: CGFloat
        └── heightDistribution: .equal | .proportional([CGFloat])
```

### Screen

- 管理対象はメインスクリーン（メニューバーのある画面）のみ
- サブモニター上のウィンドウはスキップ（ただし仮想スクロール空間は screen[0] に割り当て）
- `frame`: NSScreen.frame を Quartz 変換した物理スクリーン全体
- `workspaces`: 動的に追加可能（下方向で末尾超えたとき自動生成）
- `activeWorkspaceIndex`: 現在表示中のワークスペース

### Workspace

- `columns`: カラムの配列
- `activeColumnIndex`: フォーカス中のカラム
- `viewOffset`: スクロール位置（状態機械 → セクション 4 参照）
- `workingArea`: メニューバー・Dock を除いた作業領域（Quartz 座標）

### Column

- `windows`: ウィンドウ ID の配列（縦方向に積まれる）
- `activeWindowIndex`: カラム内フォーカスウィンドウ
- `width`: カラム幅（px）。デフォルトはスクリーン幅の 1/3
- `heightDistribution`:
  - `.equal`: 全ウィンドウ均等分割
  - `.proportional([CGFloat])`: 比率配列で分割（正規化される）

### WindowID

`CGWindowID`（`UInt32`）のエイリアス。

---

## 2. 座標系

### Quartz 座標系（統一基準）

```
原点: メインスクリーン左上
X: 右向き正
Y: 下向き正
```

- コード内はすべて Quartz 座標に統一されている
- `setupScreens()` でのみ Cocoa→Quartz 変換を行う（1 回限り）
- AX API (`AXUIElement`) も Quartz 座標を使用

### 変換式

```swift
// Cocoa (左下原点・Y上向き) → Quartz (左上原点・Y下向き)
CGRect(x: rect.origin.x,
       y: mainH - rect.origin.y - rect.height,
       width: rect.width,
       height: rect.height)
```

### workingArea vs screen.frame

| 用途 | 使用する矩形 |
|------|-------------|
| ウィンドウの配置計算 | `workingArea`（メニューバー・Dock 除き） |
| 画面外判定（アニメーション中・静止後とも） | `workingArea`（R-01・R-03 に基づき統一） |
| パーク座標（非表示退避先） | `screen.frame.maxX + gap`（スクリーン右外） |

---

## 3. レイアウト計算

### computeWindowFrames（LayoutEngine.swift）

純粋関数。副作用なし。

```
screenX = workingArea.minX + gapWidth + colX + scrollOffset
screenY = workingArea.minY + winY
```

- `colX`: `columnXPositions()` で累積計算（`gap` 間隔）
- `scrollOffset`: `workspace.viewOffset.current`（アニメーション補間済み）
- `winY`: `distributeColumnHeight()` で計算したカラム内の Y オフセット

### distributeColumnHeight

- `.equal`: 各ウィンドウ高さ = `(availableHeight - totalGap) / count`（最小 50px）
- `.proportional`: 比率に応じて分割（最小 50px）
- `totalGap = gapHeight * (count - 1)`

### LayoutConfig デフォルト値

| 設定 | 値 |
|------|----|
| gapWidth | 16px |
| gapHeight | 16px |
| defaultColumnWidth | screenWidth × 1/3 |
| animationDuration | 0.25s |

---

## 4. ViewOffset（スクロール状態機械）

### 状態

```swift
enum ViewOffset {
    case static(offset: CGFloat)       // 静止
    case animating(from:to:startTime:duration:)  // アニメーション中
}
```

### `current`

- `.static`: offset をそのまま返す
- `.animating`: `CACurrentMediaTime()` で経過時間を計算し **easeOutCubic** 補間

### easeOutCubic

```swift
1 - pow(1 - t, 3)    // t ∈ [0,1]
```

### `isSettled`

- `.static`: 常に `true`
- `.animating`: `elapsed >= duration` のとき `true`

### `animateTo(_:duration:)`

- 差分が 0.5px 未満なら即 `.static` に変換（微小変化の空アニメを防ぐ）
- それ以外は `.animating` に遷移（デフォルト 0.25s）

### `settle()`

- `current` を計算し `.static` に変換

---

## 5. adjustViewOffset（ビュー位置調整）

R-02 に基づく動作：アクティブカラムが既に workingArea 内に収まっているならスクロールしない。収まっていない場合のみ最小限スクロールして画面内に収める。

### アルゴリズム

```
1. アクティブカラムの現在のスクリーン上の位置を計算
   screenLeft  = activeX + currentOffset
   screenRight = screenLeft + activeWidth

2. 既に完全に workingArea 内に収まっている → 何もしない
   条件: screenLeft >= 0 && screenRight <= effectiveWidth

3. 左にはみ出している → 右へ最小限スクロール
   newOffset = -activeX + gap  （左端に gap 分の余白）

4. 右にはみ出している → 左へ最小限スクロール
   newOffset = -(activeX + activeWidth - effectiveWidth + gap)  （右端に gap 分の余白）

5. クランプ（左壁・右壁を超えないよう制限）
   minOffset     = min(0, effectiveWidth - gap * 2 - lastColumnRight)
   clampedOffset = max(minOffset, min(0, newOffset))
```

### Example

workingArea 幅 = 2560px、gap = 16px、各カラム幅 = 800px とする

| 状況 | screenLeft | screenRight | 操作 | newOffset |
|------|-----------|------------|------|-----------|
| 左カラムが左外 | -200 | 600 | 右へスクロール | +216（左端に16px余白） |
| 右カラムが右外 | 1900 | 2700 | 左へスクロール | -156（右端に16px余白） |
| カラムが画面内 | 400 | 1200 | 何もしない | 変化なし |

### クランプの意味

| クランプ | 値 | 説明 |
|---------|----|------|
| 左端 | `min(0, newOffset)` | 先頭カラムが左壁より左に行かない |
| 右端 | `max(minOffset, ...)` | 末尾カラムが右壁より右に飛び出さない |

---

## 6. ウィンドウ可視性制御

### 基本方針

macOS の CGS Space API（`CGSAddWindowsToSpaces`）は実際にウィンドウを別スペースに移動できないため不使用。
代わりに **画面外座標への移動**で非表示を実現する。

```
パーク座標:
  X = screen.frame.maxX + gapWidth  （右外）
  Y = screen.frame.minY + i * (height + gap)  （複数ウィンドウを縦に並べる）
```

### parkedWindowIDs キャッシュ

- パーク済みウィンドウを `Set<WindowID>` でキャッシュ
- 既にパーク済みのウィンドウは毎フレームの AX API 呼び出しをスキップ
- ウィンドウ破棄時に `parkedWindowIDs.remove(id)` でクリーンアップ

### isWindowOffScreen（あるべき判定ロジック）

要件 R-01・R-03 に基づく正しい判定：

```swift
private func isWindowOffScreen(_ frame: CGRect, workingArea: CGRect) -> Bool {
    // workingArea と一切交差しなくなったら off-screen
    return frame.maxX <= workingArea.minX || frame.minX >= workingArea.maxX
}
```

- アニメーション中・静止後を問わず同一ロジックで判定する
- 一部でも workingArea と交差していれば「表示中」とみなす（見切れは正常動作）
- 完全に左外（`frame.maxX <= workingArea.minX`）または完全に右外（`frame.minX >= workingArea.maxX`）のみ非表示

### 過去の失敗記録

| アプローチ | 問題 |
|-----------|------|
| `midX` が画面内なら表示 | midX が画面内でもウィンドウが大きくはみ出したまま残る |
| `frame.maxX > workingArea.maxX`（厳格 1px、要件通り） | マウス連続スクロール停止後に座標がレイアウト上の正しい位置からずれるため、表示中のウィンドウが誤って非表示になる |
| `max(overshoot) > width * 0.10`（10%閾値） | 要件（完全に外 = 非表示）と乖離。閾値の根拠が脆く、カラム幅によって挙動が変わる |

> **根本原因**: 厳格判定の失敗はマウス連続スクロール停止後に `viewOffset` が正確な静止位置に収束しないことが原因。
> 判定ロジックの問題ではなく、**スクロール停止後の座標スナップ**が未実装であることが本質的な課題。

---

## 7. displayLinkTick（レンダーループ）

CVDisplayLink（60fps）から呼ばれる。メインスレッドに委譲。

```
1. アニメーション中かチェック（hasAnimation）
2. isSettled になったら settle()（animating → static）
3. hasAnimation || needsLayout なら applyLayout()
4. needsLayout = false
```

### needsLayout フラグ

- アクション処理後に `needsLayout = true` をセット
- displayLinkTick が次フレームで `applyLayout()` を呼ぶ
- `start()` 時の初期配置のみ `applyLayout(animated: false)` を直接呼ぶ

---

## 8. キーボードショートカット

### フォーカス移動

| ショートカット | アクション |
|--------------|-----------|
| `Ctrl+Opt+←` | フォーカスを左カラムへ |
| `Ctrl+Opt+→` | フォーカスを右カラムへ |
| `Ctrl+Opt+↑` | カラム内で前のウィンドウへ |
| `Ctrl+Opt+↓` | カラム内で次のウィンドウへ |

### カラム操作

| ショートカット | アクション |
|--------------|-----------|
| `Ctrl+Opt+Shift+←` | アクティブカラムを左へ移動 |
| `Ctrl+Opt+Shift+→` | アクティブカラムを右へ移動 |
| `Ctrl+Opt+Return` | 左カラムのウィンドウをこのカラムに取り込む |
| `Ctrl+Opt+Shift+Return` | アクティブウィンドウを新規カラムとして分離 |
| `Ctrl+Opt+T` (keyCode=15) | カラム幅サイクル（1/3 → 1/2 → 2/3 → 1/3） |

### ワークスペース

| ショートカット | アクション |
|--------------|-----------|
| `Ctrl+Opt+Cmd+↑` | 前のワークスペースへ |
| `Ctrl+Opt+Cmd+↓` | 次のワークスペースへ（末尾で新規作成） |
| `Ctrl+Opt+Cmd+Shift+↑` | アクティブウィンドウを前のワークスペースへ移動 |
| `Ctrl+Opt+Cmd+Shift+↓` | アクティブウィンドウを次のワークスペースへ移動 |

### その他

| ショートカット | アクション |
|--------------|-----------|
| `Ctrl+Opt+Q` | アプリ終了 |

### キー検出方式

1. **CGEventTap**（優先）: `kIOHIDRequestTypeListenEvent` 権限があれば使用。全アプリ（iTerm2 等）で動作。
2. **NSEvent globalMonitor**（フォールバック）: CGEventTap 失敗時に使用。
3. **NSEvent localMonitor**: アプリ自身にフォーカスがある場合も処理。

### カラム幅サイクルの閾値

```
現在幅 < 40% → 次: 50%
現在幅 < 60% → 次: 66.7%
それ以外      → 次: 33.3%
```

---

## 9. マウス操作

### クリックフォーカス

- 画面上のクリック位置を `lastComputedFrames` と照合
- 対応するウィンドウにフォーカス移動 + `recenterViewOffset`

### スクロール

- `NSEvent` の scrollWheel イベントを監視
- `isContinuous=true`（トラックパッド連続スクロール）: `viewOffset` を直接更新
- `isContinuous=false`（マウスホイール離散スクロール）: カラムフォーカス移動（0.3 秒クールダウン）

### カラム境界線ドラッグ（未実装・R-04）

- `NSEvent` の mouseDragged イベントを監視
- ヒットテスト: クリック位置がカラム境界線（右端 ±4px 程度）に当たったらドラッグ開始
- ドラッグ中: `deltaX` を累積し、`column.width` を 1% 単位（`screenWidth * 0.01`）で更新
- 幅の範囲: `screenWidth * 0.01` 〜 `screenWidth * 0.99`（1%〜99%）
- ドラッグ中も `needsLayout = true` を立てリアルタイムにレイアウト再計算
- mouseUp でドラッグ確定、幅を `column.width` に保存

### アプリアクティベーション追従

- `NSWorkspace.shared.frontmostApplication` 変更を検知してフォーカス同期
- `setWindowFrame` が誤発火させる連続通知を **0.3 秒 debounce** で間引く
- PID が変わっていない場合はスキップ

---

## 10. ウィンドウライフサイクル

### 起動時

```
setupScreens()
  → Cocoa→Quartz変換・workingArea 設定
discoverExistingWindows()
  → allWindows() で全ウィンドウ検出
  → assignWindowToScreen() で各ウィンドウを適切なカラムに配置
  → recenterViewOffset(animated: false) で初期位置確定
applyLayout(animated: false)
```

### ウィンドウ作成

1. `windowRegistry` に追加
2. サブモニター判定（スキップ or 割り当て）
3. 新規カラム作成 → `addColumn()` → `recenterViewOffset()`
4. `applyLayout()` + `focusWindow()`

### ウィンドウ破棄

1. `windowRegistry` から削除
2. `parkedWindowIDs` からも削除
3. 全ワークスペースから `removeWindow(id)` → 空カラムも削除
4. `applyLayout()` + `focusActiveWindow()`

---

## 11. ログ

全ログは `/tmp/niri-mac.log` に出力。

| プレフィックス | 内容 |
|--------------|------|
| `[niri-mac]` | 起動・バージョン・権限情報 |
| `[layout]` | フレーム計算・適用（`🅿️ hide`=パーク、`↩️ show`=復帰） |
| `[action]` | キーボードアクション処理 |
| `[mouse]` | マウスクリック・スクロール・アプリ切り替え |
| `[assign]` | ウィンドウのスクリーン割り当て |
| `[tick]` | displayLinkTick のトリガー情報 |
| `[window]` | ウィンドウ作成・破棄イベント |
| `[niri-mac] 🔑` | キーイベント（CGEvent / NSEvent） |
| `[niri-mac] 🎹` | マッチしたキーバインド |

---

## 12. 既知の制約・設計上の注意

| 項目 | 内容 |
|------|------|
| Space API 非使用 | `CGSAddWindowsToSpaces` は現環境（macOS 14+）で実質不動作のため画面外退避方式を採用 |
| メインスクリーンのみ管理 | サブモニターのウィンドウはレイアウト対象外 |
| `onAppActivated` debounce | `setWindowFrame` 呼び出しが自身の通知を誤発火させるため 0.3s debounce 必須 |
| `applyLayout` 直接呼び出し | `start()` の初期化時のみ直接呼び出し可。それ以外は `needsLayout = true` 経由 |
| 最小ウィンドウ高さ | 50px（`distributeColumnHeight` のガード値） |

---

## 13. ビルド・動作確認手順

```bash
# ビルド
swift build

# .app バンドル作成 & 署名（アクセシビリティ権限のため必須）
bash make-app.sh

# 起動
open NiriMac.app

# ログ監視
tail -f /tmp/niri-mac.log
```

初回起動後: システム設定 → プライバシーとセキュリティ → **アクセシビリティ** と **入力監視** に NiriMac.app を追加。
