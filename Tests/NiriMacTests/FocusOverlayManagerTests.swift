import Testing
import CoreGraphics
@testable import NiriMac

@Suite("FocusOverlayManager Tests")
struct FocusOverlayManagerTests {

    @Test func quartzToCocoaConversion() {
        let screenHeight: CGFloat = 900
        let quartzFrame = CGRect(x: 100, y: 50, width: 400, height: 300)
        // Cocoa Y = screenHeight - quartzY - height = 900 - 50 - 300 = 550
        let cocoaFrame = FocusOverlayManager.quartzToCocoa(quartzFrame, screenHeight: screenHeight)
        #expect(abs(cocoaFrame.origin.x - 100) < 0.001)
        #expect(abs(cocoaFrame.origin.y - 550) < 0.001)
        #expect(abs(cocoaFrame.width - 400) < 0.001)
        #expect(abs(cocoaFrame.height - 300) < 0.001)
    }

    @Test func expandedBorderFrame() {
        let base = CGRect(x: 100, y: 100, width: 400, height: 300)
        let expanded = base.insetBy(dx: -4, dy: -4)
        #expect(abs(expanded.origin.x - 96) < 0.001)
        #expect(abs(expanded.origin.y - 96) < 0.001)
        #expect(abs(expanded.width - 408) < 0.001)
        #expect(abs(expanded.height - 308) < 0.001)
    }
}
