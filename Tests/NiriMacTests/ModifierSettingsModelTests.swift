import Testing
import AppKit
@testable import NiriMac

@Suite("ModifierSettingsModel Tests")
struct ModifierSettingsModelTests {

    @Test func currentMetaReflectsToggles() {
        let model = ModifierSettingsModel(
            meta: [.control, .option],
            scrollLayout: [.control],
            scrollFocus: [.control, .option]
        )
        #expect(model.currentMeta == [.control, .option])
        model.metaCommand = true
        #expect(model.currentMeta == [.control, .option, .command])
    }

    @Test func hasChangesWhenMetaDiffers() {
        let model = ModifierSettingsModel(
            meta: [.control, .option],
            scrollLayout: [.control],
            scrollFocus: [.control, .option]
        )
        #expect(model.hasChanges == false)
        model.metaShift = true
        #expect(model.hasChanges == true)
    }

    @Test func hasChangesWhenScrollLayoutDiffers() {
        let model = ModifierSettingsModel(
            meta: [.control, .option],
            scrollLayout: [.control],
            scrollFocus: [.control, .option]
        )
        model.layoutOption = true
        #expect(model.hasChanges == true)
    }

    @Test func anyEmptyWhenMetaAllUnchecked() {
        let model = ModifierSettingsModel(
            meta: [.control],
            scrollLayout: [.control],
            scrollFocus: [.control, .option]
        )
        model.metaControl = false
        #expect(model.anyEmpty == true)
    }

    @Test func metaHasCommandReflectsState() {
        let model = ModifierSettingsModel(
            meta: [.control, .option],
            scrollLayout: [.control],
            scrollFocus: [.control, .option]
        )
        #expect(model.metaHasCommand == false)
        model.metaCommand = true
        #expect(model.metaHasCommand == true)
    }
}
