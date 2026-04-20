import Testing
import CoreGraphics
@testable import NiriMac

@Suite("Screen Change Tests")
struct ScreenChangeTests {

    @Test func reLayoutActionExists() {
        let action = KeyboardShortcutManager.Action.reLayout
        _ = action
    }

    @Test func workspace_workingAreaUpdateInPlace_preservesColumns() {
        // Given: 1440x900 で初期化されたワークスペース（ウィンドウあり）
        var ws = Workspace(workingArea: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ws.columns = [Column(windows: [1], width: 480)]
        #expect(ws.workingArea.width == 1440)
        #expect(ws.columns.count == 1)

        // When: workingArea をインプレース更新（refreshScreenGeometry の動作を模倣）
        ws.workingArea = CGRect(x: 0, y: 0, width: 1280, height: 800)

        // Then: 新サイズが反映され、ウィンドウ配置は保持される
        #expect(ws.workingArea.width == 1280)
        #expect(ws.workingArea.height == 800)
        #expect(ws.columns.count == 1)
        #expect(ws.columns[0].windows == [1])
    }
}
