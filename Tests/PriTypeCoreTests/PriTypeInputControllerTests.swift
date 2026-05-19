import Foundation
import Testing
@testable import PriTypeCore

@Suite("PriType Input Controller")
struct PriTypeInputControllerTests {
    @Test("insertText targets existing marked range")
    func insertionReplacementUsesMarkedRange() {
        let replacement = PriTypeInputController.BaseClientAdapter.insertionReplacementRange(
            markedRange: NSRange(location: 12, length: 1)
        )

        #expect(replacement.location == 12)
        #expect(replacement.length == 1)
    }

    @Test("insertText defers when no marked range exists")
    func insertionReplacementDefersWithoutMarkedRange() {
        let replacement = PriTypeInputController.BaseClientAdapter.insertionReplacementRange(
            markedRange: NSRange(location: NSNotFound, length: NSNotFound)
        )

        #expect(replacement.location == NSNotFound)
        #expect(replacement.length == NSNotFound)
    }

    @Test("empty marked text only clears non-empty marked range")
    func clearingMarkedTextRequiresNonEmptyMarkedRange() {
        let existing = PriTypeInputController.BaseClientAdapter.markedTextClearingReplacementRange(
            markedRange: NSRange(location: 5, length: 1)
        )
        let empty = PriTypeInputController.BaseClientAdapter.markedTextClearingReplacementRange(
            markedRange: NSRange(location: 5, length: 0)
        )
        let unavailable = PriTypeInputController.BaseClientAdapter.markedTextClearingReplacementRange(
            markedRange: NSRange(location: NSNotFound, length: NSNotFound)
        )

        #expect(existing?.location == 5)
        #expect(existing?.length == 1)
        #expect(empty == nil)
        #expect(unavailable == nil)
    }
}
