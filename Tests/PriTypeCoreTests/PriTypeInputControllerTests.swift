import Foundation
import Testing
@testable import PriTypeCore

@Suite("PriType Input Controller")
struct PriTypeInputControllerTests {
    @Test("insertText targets marked range when selection is unavailable")
    func insertionReplacementUsesMarkedRangeWhenSelectionIsUnavailable() {
        let selected = NSRange(location: NSNotFound, length: NSNotFound)
        let marked = NSRange(location: 2, length: 1)

        let replacement = PriTypeInputController.BaseClientAdapter.insertionReplacementRange(
            selectedRange: selected,
            markedRange: marked
        )

        #expect(replacement.location == 2)
        #expect(replacement.length == 1)
    }

    @Test("insertText targets marked range even when selection is available")
    func insertionReplacementUsesMarkedRangeWhenSelectionIsAvailable() {
        let selected = NSRange(location: 3, length: 0)
        let marked = NSRange(location: 2, length: 1)

        let replacement = PriTypeInputController.BaseClientAdapter.insertionReplacementRange(
            selectedRange: selected,
            markedRange: marked
        )

        #expect(replacement.location == 2)
        #expect(replacement.length == 1)
    }

    @Test("insertText lets IMK choose replacement when marked range is unavailable")
    func insertionReplacementDefersWhenMarkedRangeIsUnavailable() {
        let selected = NSRange(location: NSNotFound, length: NSNotFound)
        let marked = NSRange(location: NSNotFound, length: NSNotFound)

        let replacement = PriTypeInputController.BaseClientAdapter.insertionReplacementRange(
            selectedRange: selected,
            markedRange: marked
        )

        #expect(replacement.location == NSNotFound)
        #expect(replacement.length == NSNotFound)
    }

    @Test("clearing marked text targets only an existing non-empty marked range")
    func clearingMarkedTextUsesOnlyNonEmptyMarkedRange() {
        let replacement = PriTypeInputController.BaseClientAdapter.markedTextClearingReplacementRange(
            markedRange: NSRange(location: 12, length: 1)
        )

        #expect(replacement?.location == 12)
        #expect(replacement?.length == 1)
    }

    @Test("clearing marked text does not create a zero-length marked range")
    func clearingMarkedTextSkipsUnavailableOrEmptyMarkedRanges() {
        let unavailable = PriTypeInputController.BaseClientAdapter.markedTextClearingReplacementRange(
            markedRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
        let empty = PriTypeInputController.BaseClientAdapter.markedTextClearingReplacementRange(
            markedRange: NSRange(location: 12, length: 0)
        )

        #expect(unavailable == nil)
        #expect(empty == nil)
    }

    @Test("direct composition requires no host marked range")
    func directCompositionRequiresNoHostMarkedRange() {
        #expect(PriTypeInputController.BaseClientAdapter.hasNoHostMarkedRange(
            NSRange(location: NSNotFound, length: NSNotFound)
        ))
        #expect(!PriTypeInputController.BaseClientAdapter.hasNoHostMarkedRange(
            NSRange(location: 12, length: 0)
        ))
        #expect(!PriTypeInputController.BaseClientAdapter.hasNoHostMarkedRange(
            NSRange(location: 12, length: 1)
        ))
    }

    @Test("host marked session treats zero length as still owned by host")
    func hostMarkedSessionIncludesZeroLengthResidue() {
        #expect(!PriTypeInputController.BaseClientAdapter.hasHostMarkedRange(
            NSRange(location: NSNotFound, length: NSNotFound)
        ))
        #expect(!PriTypeInputController.BaseClientAdapter.hasHostMarkedRange(
            NSRange(location: 12, length: 0)
        ))
        #expect(PriTypeInputController.BaseClientAdapter.hasHostMarkedRange(
            NSRange(location: 12, length: 1)
        ))
        #expect(PriTypeInputController.BaseClientAdapter.hasHostMarkedSession(
            NSRange(location: 12, length: 0)
        ))
    }

    @Test("direct composition reuses the active direct range")
    func directCompositionUsesActiveCompositionRange() {
        let replacement = PriTypeInputController.BaseClientAdapter.directCompositionReplacementRange(
            compositionRange: NSRange(location: 4, length: 1),
            selectedRange: NSRange(location: 99, length: 0)
        )

        #expect(replacement.location == 4)
        #expect(replacement.length == 1)
    }

    @Test("direct composition starts at a valid insertion selection")
    func directCompositionStartsAtSelection() {
        let replacement = PriTypeInputController.BaseClientAdapter.directCompositionReplacementRange(
            compositionRange: NSRange(location: NSNotFound, length: 0),
            selectedRange: NSRange(location: 7, length: 0)
        )

        #expect(replacement.location == 7)
        #expect(replacement.length == 0)
    }

    @Test("direct composition defers when selection is not an insertion point")
    func directCompositionDefersForInvalidSelection() {
        let selectedRange = NSRange(location: 7, length: 2)
        let replacement = PriTypeInputController.BaseClientAdapter.directCompositionReplacementRange(
            compositionRange: NSRange(location: NSNotFound, length: 0),
            selectedRange: selectedRange
        )

        #expect(PriTypeInputController.BaseClientAdapter.isUsableInsertionSelection(selectedRange) == false)
        #expect(replacement.location == NSNotFound)
        #expect(replacement.length == NSNotFound)
    }
}
