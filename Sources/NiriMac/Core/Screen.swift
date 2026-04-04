import CoreGraphics
import Foundation

/// 物理モニター1台分の状態。niri の Monitor に相当。
struct Screen: Identifiable {
    let id: CGDirectDisplayID
    var workspaces: [Workspace]
    var activeWorkspaceIndex: Int
    var frame: CGRect

    /// - Parameter frame: NSScreen.frame (Cocoa座標)
    /// - Parameter visibleFrame: NSScreen.visibleFrame (メニューバー・Dock除き、Cocoa座標)
    init(id: CGDirectDisplayID, frame: CGRect, visibleFrame: CGRect) {
        self.id = id
        self.frame = frame
        // visibleFrame を作業エリアとして使う（メニューバー・Dock を除外済み）
        self.workspaces = [Workspace(workingArea: visibleFrame)]
        self.activeWorkspaceIndex = 0
    }

    var activeWorkspace: Workspace {
        get {
            guard activeWorkspaceIndex < workspaces.count else { return workspaces[0] }
            return workspaces[activeWorkspaceIndex]
        }
        set {
            guard activeWorkspaceIndex < workspaces.count else { return }
            workspaces[activeWorkspaceIndex] = newValue
        }
    }

    /// visibleFrame からワークスペース作業エリアを作る（NSScreen.visibleFrame を渡すこと）
    static func workingArea(for visibleFrame: CGRect) -> CGRect {
        return visibleFrame
    }

    /// 全ワークスペースのウィンドウIDを収集
    var allWindowIDs: [WindowID] {
        workspaces.flatMap { ws in
            ws.columns.flatMap { $0.windows }
        }
    }

    mutating func addWorkspace(visibleFrame: CGRect) {
        workspaces.append(Workspace(workingArea: visibleFrame))
    }

    mutating func switchToNextWorkspace() {
        if activeWorkspaceIndex < workspaces.count - 1 {
            activeWorkspaceIndex += 1
        }
    }

    mutating func switchToPreviousWorkspace() {
        if activeWorkspaceIndex > 0 {
            activeWorkspaceIndex -= 1
        }
    }
}
