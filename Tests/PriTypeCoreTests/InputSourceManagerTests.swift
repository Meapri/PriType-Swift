import Testing
@testable import PriTypeCore

@Suite("InputSourceManager")
struct InputSourceManagerTests {
    @Test("Keeps PriType parent and unified mode in enabled sources")
    func keepsPriTypeParentAndUnifiedModeInEnabledSources() {
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

        #expect(sanitized.count == 2)
        #expect(sanitized.contains { $0["Input Mode"] == nil })
        #expect(sanitized.contains { ($0["Input Mode"] as? String) == "com.pritype.inputmethod.v2" })
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
