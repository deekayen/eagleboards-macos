import Foundation
import Testing

@testable import EagleBoardsCore

@Suite("Keep awake")
struct KeepAwakeTests {
    /// Counts the activities begun and ended.
    final class Ledger {
        var begun = 0
        var ended = 0
        var openCount: Int { begun - ended }

        func keepAwake() -> KeepAwake {
            KeepAwake(
                begin: {
                    self.begun += 1
                    return NSObject()
                },
                end: { _ in self.ended += 1 })
        }
    }

    @Test func holdOpensOneActivityAndReleaseEndsIt() {
        let ledger = Ledger()
        let keepAwake = ledger.keepAwake()
        #expect(!keepAwake.isHeld)
        keepAwake.hold()
        #expect(keepAwake.isHeld)
        #expect(ledger.openCount == 1)
        keepAwake.release()
        #expect(!keepAwake.isHeld)
        #expect(ledger.openCount == 0)
    }

    @Test func holdingTwiceLeavesNoActivityUnended() {
        let ledger = Ledger()
        let keepAwake = ledger.keepAwake()
        keepAwake.hold()
        keepAwake.hold()
        #expect(ledger.begun == 1)
        keepAwake.release()
        #expect(ledger.openCount == 0)
    }

    @Test func holdingAgainAfterReleaseBeginsANewActivity() {
        let ledger = Ledger()
        let keepAwake = ledger.keepAwake()
        keepAwake.hold()
        keepAwake.release()
        keepAwake.hold()
        #expect(ledger.begun == 2)
        #expect(ledger.openCount == 1)
        #expect(keepAwake.isHeld)
    }

    @Test func releasingWhenNotHeldDoesNothing() {
        let ledger = Ledger()
        let keepAwake = ledger.keepAwake()
        keepAwake.release()
        #expect(ledger.ended == 0)
        keepAwake.hold()
        keepAwake.release()
        keepAwake.release()
        #expect(ledger.ended == 1)
    }

    @Test func theSystemActivityCanBeHeldAndReleased() {
        let keepAwake = KeepAwake.processActivity(reason: "Testing the keep-awake type")
        keepAwake.hold()
        #expect(keepAwake.isHeld)
        keepAwake.release()
        #expect(!keepAwake.isHeld)
    }
}
