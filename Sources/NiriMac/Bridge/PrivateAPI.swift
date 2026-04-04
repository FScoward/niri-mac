import ApplicationServices
import CoreGraphics

/// macOS プライベート AX API の宣言。
/// これらは公開 API ではないが、ウィンドウマネージャーに必要。
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: inout CGWindowID) -> AXError

// MARK: - CGS Space API (SkyLight private framework, SIP 不要)

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> UInt32

/// 全スペースの ID 一覧を返す
@_silgen_name("CGSCopySpaces")
func CGSCopySpaces(_ cid: UInt32, _ mask: UInt32) -> CFArray

/// 指定ウィンドウが属するスペース ID 一覧を返す
@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(_ cid: UInt32, _ mask: UInt32, _ windowIDs: CFArray) -> CFArray

/// ウィンドウを指定スペースに追加（Add → Remove の順で呼ぶこと）
@_silgen_name("CGSAddWindowsToSpaces")
func CGSAddWindowsToSpaces(_ cid: UInt32, _ windows: CFArray, _ spaces: CFArray)

/// ウィンドウを指定スペースから削除
@_silgen_name("CGSRemoveWindowsFromSpaces")
func CGSRemoveWindowsFromSpaces(_ cid: UInt32, _ windows: CFArray, _ spaces: CFArray)

/// ディスプレイごとのスペース情報を返す（各要素に "Current Space" キーあり）
@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: UInt32) -> CFArray

let kCGSAllSpacesMask: UInt32 = 0x0F
let kCGSCurrentSpaceMask: UInt32 = 0x01
