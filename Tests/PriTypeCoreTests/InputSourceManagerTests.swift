import Testing
@testable import PriTypeCore

@Suite("InputSourceManager")
struct InputSourceManagerTests {
    @Test("Keeps PriType parent and BOTH Korean + English modes in enabled sources")
    func keepsPriTypeParentAndBothModesInEnabledSources() {
        // Dual-mode design: korean (com.pritype.inputmethod.v2) and english
        // (com.pritype.inputmethod.v2.english) are BOTH current — neither is stale.
        let sources: [[String: Any]] = [
            [
                "Bundle ID": "com.pritype.inputmethod.v2",
                "InputSourceKind": "Keyboard Input Method"
            ],
            [
                "Bundle ID": "com.pritype.inputmethod.v2",
                "InputSourceKind": "Input Mode",
                "Input Mode": "com.pritype.inputmethod.v2"
            ],
            [
                "Bundle ID": "com.pritype.inputmethod.v2",
                "InputSourceKind": "Input Mode",
                "Input Mode": "com.pritype.inputmethod.v2.english"
            ]
        ]

        let sanitized = InputSourceManager.sanitizedInputSources(
            sources,
            removeAppleKoreanInputModes: false,
            allowsPriTypeParentEntry: true
        )

        #expect(sanitized.count == 3)
        #expect(sanitized.contains { $0["Input Mode"] == nil })  // parent
        #expect(sanitized.contains { ($0["Input Mode"] as? String) == "com.pritype.inputmethod.v2" })          // korean
        #expect(sanitized.contains { ($0["Input Mode"] as? String) == "com.pritype.inputmethod.v2.english" })  // english (kept)
    }

    @Test("Keeps PriType parent and removes stale child modes from selected and history sources")
    func keepsPriTypeParentAndRemovesStaleChildModesFromSelectedAndHistorySources() {
        let sources: [[String: Any]] = [
            [
                "Bundle ID": "com.pritype.inputmethod.v2",
                "InputSourceKind": "Keyboard Input Method"
            ],
            [
                "Bundle ID": "com.pritype.inputmethod.v2",
                "InputSourceKind": "Input Mode",
                "Input Mode": "com.pritype.inputmethod.v2"
            ],
            [
                "Bundle ID": "com.pritype.inputmethod.v2",
                "InputSourceKind": "Input Mode",
                "Input Mode": "com.pritype.inputmethod.v2.korean"
            ],
            [
                "Bundle ID": "com.apple.PressAndHold",
                "InputSourceKind": "Non Keyboard Input Method"
            ]
        ]

        let sanitized = InputSourceManager.sanitizedInputSources(
            sources,
            removeAppleKoreanInputModes: false,
            allowsPriTypeParentEntry: true
        )

        #expect(sanitized.count == 3)
        #expect(sanitized.contains { ($0["Bundle ID"] as? String) == "com.pritype.inputmethod.v2" && $0["Input Mode"] == nil })
        #expect(sanitized.contains { ($0["Input Mode"] as? String) == "com.pritype.inputmethod.v2" })
        #expect(!sanitized.contains { ($0["Input Mode"] as? String) == "com.pritype.inputmethod.v2.korean" })
        #expect(sanitized.contains { ($0["Bundle ID"] as? String) == "com.apple.PressAndHold" })
    }
}
