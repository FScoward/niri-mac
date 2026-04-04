import Foundation
import CoreGraphics
import ApplicationServices

private let spaceLogURL = URL(fileURLWithPath: "/tmp/niri-mac.log")
private func spaceLog(_ message: String) {
    let line = message + "\n"
    print(line, terminator: "")
    if let data = line.data(using: .utf8),
       let fh = try? FileHandle(forWritingTo: spaceLogURL) {
        fh.seekToEndOfFile()
        fh.write(data)
        try? fh.close()
    }
}

/// macOS Mission Control スペースを使ったウィンドウ非表示管理。
/// 画面外ウィンドウを「駐車スペース」（最後尾のスペース）に退避させる。
final class SpaceBridge {

    // MARK: - Parking Space Detection

    /// ユーザーが用意した駐車スペースの ID を返す。
    /// 戦略: 全スペースのうち最後尾（インデックス最大）を駐車場とする。
    /// ユーザーは Mission Control で1つ余分なスペースを作っておく必要がある。
    func parkingSpaceID() -> UInt64? {
        let cid = CGSMainConnectionID()
        guard let spaces = CGSCopySpaces(cid, kCGSAllSpacesMask) as? [UInt64] else {
            spaceLog("[space] ⚠️ CGSCopySpaces failed (cid=\(cid))")
            return nil
        }
        spaceLog("[space] allSpaces=\(spaces)")
        guard spaces.count >= 2 else {
            spaceLog("[space] ⚠️ 駐車スペースなし（スペースが1つのみ）")
            return nil
        }
        spaceLog("[space] parkingSpace=\(spaces.last!)")
        return spaces.last
    }

    /// 現在アクティブなスペース（メインスペース）の ID を返す。
    /// kCGSCurrentSpaceMask は空配列を返すことがあるため、
    /// CGSCopyManagedDisplaySpaces から "Current Space" を取得する方式に変更。
    func currentSpaceID() -> UInt64? {
        let cid = CGSMainConnectionID()
        guard let displays = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] else {
            spaceLog("[space] ⚠️ currentSpaceID: CGSCopyManagedDisplaySpaces failed")
            return nil
        }
        for display in displays {
            if let currentSpace = display["Current Space"] as? [String: Any],
               let spaceID = currentSpace["ManagedSpaceID"] as? UInt64 {
                spaceLog("[space] currentSpace=\(spaceID)")
                return spaceID
            }
        }
        spaceLog("[space] ⚠️ currentSpaceID: ManagedSpaceID not found in displays=\(displays.count)")
        return nil
    }

    // MARK: - Window ↔ Space

    /// 指定ウィンドウが属するスペース ID 一覧を返す。
    func spacesForWindow(windowID: CGWindowID) -> [UInt64] {
        let cid = CGSMainConnectionID()
        let windowIDs = [UInt64(windowID)] as CFArray
        guard let spaces = CGSCopySpacesForWindows(cid, kCGSAllSpacesMask, windowIDs) as? [UInt64] else {
            return []
        }
        return spaces
    }

    /// ウィンドウを駐車スペースに退避（非表示化）。
    /// - Returns: 退避に成功したか。駐車スペースがない場合は false。
    @discardableResult
    func park(windowID: CGWindowID) -> Bool {
        guard let parkingSpace = parkingSpaceID() else { return false }
        let currentSpaces = spacesForWindow(windowID: windowID)
        guard !currentSpaces.isEmpty else {
            spaceLog("[space] park win=\(windowID) ⚠️ spacesForWindow 空")
            return false
        }

        // すでに駐車済みならスキップ
        if currentSpaces.contains(parkingSpace) {
            spaceLog("[space] park win=\(windowID) already parked")
            return true
        }

        let cid = CGSMainConnectionID()
        let windows = [UInt64(windowID)] as CFArray
        let target = [parkingSpace] as CFArray

        // Add → Remove の順序が重要
        CGSAddWindowsToSpaces(cid, windows, target)
        for spaceID in currentSpaces {
            CGSRemoveWindowsFromSpaces(cid, windows, [spaceID] as CFArray)
        }
        // park後に実際のスペースを確認
        let afterSpaces = spacesForWindow(windowID: windowID)
        spaceLog("[space] ✅ park win=\(windowID) \(currentSpaces) → [\(parkingSpace)] (actual after: \(afterSpaces))")
        return true
    }

    /// 駐車スペースから現在のスペースに復帰。
    @discardableResult
    func unpark(windowID: CGWindowID) -> Bool {
        guard let parkingSpace = parkingSpaceID() else { return false }
        guard let currentSpace = currentSpaceID() else {
            spaceLog("[space] ⚠️ unpark win=\(windowID): currentSpaceID取得失敗 → unpark不可")
            return false
        }
        let currentSpaces = spacesForWindow(windowID: windowID)
        spaceLog("[space] unpark win=\(windowID) currentSpaces=\(currentSpaces) parkingSpace=\(parkingSpace) currentSpace=\(currentSpace)")

        // 駐車中でなければスキップ
        guard currentSpaces.contains(parkingSpace) else {
            spaceLog("[space] unpark win=\(windowID) not in parkingSpace → skip (already in \(currentSpaces))")
            return true
        }

        let cid = CGSMainConnectionID()
        let windows = [UInt64(windowID)] as CFArray

        CGSAddWindowsToSpaces(cid, windows, [currentSpace] as CFArray)
        CGSRemoveWindowsFromSpaces(cid, windows, [parkingSpace] as CFArray)
        spaceLog("[space] ✅ unpark win=\(windowID) [\(parkingSpace)] → \(currentSpace)")
        return true
    }

    /// 現在のスペースにあるかチェック。
    func isParked(windowID: CGWindowID) -> Bool {
        guard let parkingSpace = parkingSpaceID() else { return false }
        return spacesForWindow(windowID: windowID).contains(parkingSpace)
    }
}
