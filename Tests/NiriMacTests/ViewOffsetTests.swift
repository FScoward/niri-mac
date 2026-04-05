import Testing
import CoreGraphics

@Suite("ViewOffset Tests")
struct ViewOffsetTests {

    @Test func staticCurrent() {
        let vo = ViewOffset.static(offset: 42.0)
        #expect(vo.current == 42.0)
    }

    @Test func staticIsSettled() {
        let vo = ViewOffset.static(offset: 0)
        #expect(vo.isSettled == true)
    }

    @Test func animateToSmallDelta() {
        // delta < 0.5 の場合は static に落ちる
        var vo = ViewOffset.static(offset: 100.0)
        vo.animateTo(100.3)
        if case .static(let offset) = vo {
            #expect(abs(offset - 100.3) < 0.001)
        } else {
            Issue.record("Expected .static for small delta")
        }
    }

    @Test func animateToLargeDelta() {
        // delta >= 0.5 の場合は .animating になる
        var vo = ViewOffset.static(offset: 0)
        vo.animateTo(-200.0)
        if case .animating(let from, let to, _, _) = vo {
            #expect(abs(from - 0) < 0.001)
            #expect(abs(to - (-200.0)) < 0.001)
        } else {
            Issue.record("Expected .animating for large delta")
        }
    }

    @Test func settle() {
        var vo = ViewOffset.static(offset: -50.0)
        vo.settle()
        if case .static(let offset) = vo {
            #expect(abs(offset - (-50.0)) < 0.001)
        } else {
            Issue.record("Expected .static after settle")
        }
    }

    @Test func animatingTarget() {
        let vo = ViewOffset.animating(from: 0, to: -300, startTime: 0, duration: 0.25)
        #expect(abs(vo.target - (-300)) < 0.001)
    }

    @Test func staticTarget() {
        let vo = ViewOffset.static(offset: -100)
        #expect(abs(vo.target - (-100)) < 0.001)
    }
}
