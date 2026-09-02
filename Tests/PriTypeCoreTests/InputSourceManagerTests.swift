import Testing
@testable import PriTypeCore

@Suite("InputSourceManager")
struct InputSourceManagerTests {
    @Test("Keeps PriType parent and BOTH Korean + English modes in enabled sources")
    func keepsPriTypeParentAndBothModesInEnabledSources() {
        let sources: [[String: Any]] = [
            [
                "Bundle ID": "com.pritype.inputmethod.v2",
                "InputSourceKind": "Keyboard Input Method"
            ],
            [
                "Bundle ID": "com.pritype.inputmethod.v2",
                "InputSourceKind": "Input Mode",
                "Input Mode": "com.pritype.inputmethod.v2.korean"
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
        #expect(sanitized.contains { ($0["Input Mode"] as? String) == "com.pritype.inputmethod.v2.korean" })
        #expect(sanitized.contains { ($0["Input Mode"] as? String) == "com.pritype.inputmethod.v2.english" })
    }

    @Test("Migrates legacy Korean mode id that collided with the bundle id")
    func migratesLegacyKoreanModeIdEqualToBundle() {
        // Old Info.plist used the bundle id as the Korean mode key. TIS then
        // minted com.pritype.inputmethod.v2.v2 and every Settings row said PriType.
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
        #expect(sanitized.contains { ($0["Bundle ID"] as? String) == "com.pritype.inputmethod.v2" && $0["Input Mode"] == nil })
        #expect(sanitized.contains { ($0["Input Mode"] as? String) == "com.pritype.inputmethod.v2.korean" })
        #expect(!sanitized.contains { ($0["Input Mode"] as? String) == "com.pritype.inputmethod.v2" })
        #expect(sanitized.contains { ($0["Input Mode"] as? String) == "com.pritype.inputmethod.v2.english" })
    }

    @Test("Keeps PriType parent and removes unknown stale child modes")
    func keepsPriTypeParentAndRemovesStaleChildModesFromSelectedAndHistorySources() {
        let sources: [[String: Any]] = [
            [
                "Bundle ID": "com.pritype.inputmethod.v2",
                "InputSourceKind": "Keyboard Input Method"
            ],
            [
                "Bundle ID": "com.pritype.inputmethod.v2",
                "InputSourceKind": "Input Mode",
                "Input Mode": "com.pritype.inputmethod.v2.korean"
            ],
            [
                "Bundle ID": "com.pritype.inputmethod.v2",
                "InputSourceKind": "Input Mode",
                "Input Mode": "com.pritype.inputmethod.v2.legacy"
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
        #expect(sanitized.contains { ($0["Input Mode"] as? String) == "com.pritype.inputmethod.v2.korean" })
        #expect(!sanitized.contains { ($0["Input Mode"] as? String) == "com.pritype.inputmethod.v2.legacy" })
        #expect(sanitized.contains { ($0["Bundle ID"] as? String) == "com.apple.PressAndHold" })
    }

    @Test("Identifies ABC sources by layout id and name")
    func isDefaultABCSource() {
        #expect(InputSourceManager.isDefaultABCSource([
            "InputSourceKind": "Keyboard Layout",
            "KeyboardLayout ID": 252,
            "KeyboardLayout Name": "ABC"
        ]))
        #expect(InputSourceManager.isDefaultABCSource([
            "KeyboardLayout Name": "ABC"
        ]))
        #expect(!InputSourceManager.isDefaultABCSource([
            "InputSourceKind": "Keyboard Layout",
            "KeyboardLayout ID": 0,
            "KeyboardLayout Name": "U.S."
        ]))
        #expect(!InputSourceManager.isDefaultABCSource([
            "Bundle ID": "com.pritype.inputmethod.v2",
            "InputSourceKind": "Keyboard Input Method"
        ]))
    }

    @Test("Migrating a legacy Korean mode that is already present as .korean does not duplicate")
    func migrateThenDedupKoreanModes() {
        let sources: [[String: Any]] = [
            [
                "Bundle ID": "com.pritype.inputmethod.v2",
                "InputSourceKind": "Input Mode",
                "Input Mode": "com.pritype.inputmethod.v2"
            ],
            [
                "Bundle ID": "com.pritype.inputmethod.v2",
                "InputSourceKind": "Input Mode",
                "Input Mode": "com.pritype.inputmethod.v2.korean"
            ]
        ]
        let sanitized = InputSourceManager.sanitizedInputSources(
            sources,
            removeAppleKoreanInputModes: false,
            allowsPriTypeParentEntry: true
        )
        #expect(sanitized.count == 1)
        #expect((sanitized[0]["Input Mode"] as? String) == "com.pritype.inputmethod.v2.korean")
    }

    @Test("PatchType identity strips leftover official PriType rows")
    func patchTypeStripsOfficialPriTypeRows() {
        let sources: [[String: Any]] = [
            [
                "Bundle ID": Brand.officialBundleID,
                "InputSourceKind": "Keyboard Input Method"
            ],
            [
                "Bundle ID": Brand.officialBundleID,
                "InputSourceKind": "Input Mode",
                "Input Mode": Brand.officialKoreanModeID
            ],
            [
                "Bundle ID": Brand.patchBundleID,
                "InputSourceKind": "Keyboard Input Method"
            ],
            [
                "Bundle ID": Brand.patchBundleID,
                "InputSourceKind": "Input Mode",
                "Input Mode": Brand.patchKoreanModeID
            ],
            [
                "Bundle ID": "com.apple.inputmethod.Korean",
                "InputSourceKind": "Keyboard Input Method"
            ]
        ]

        let sanitized = InputSourceManager.sanitizedInputSources(
            sources,
            removeAppleKoreanInputModes: false,
            allowsPriTypeParentEntry: true,
            activeBundleID: Brand.patchBundleID
        )

        #expect(!sanitized.contains { ($0["Bundle ID"] as? String) == Brand.officialBundleID })
        #expect(sanitized.contains { ($0["Bundle ID"] as? String) == Brand.patchBundleID && $0["Input Mode"] == nil })
        #expect(sanitized.contains { ($0["Input Mode"] as? String) == Brand.patchKoreanModeID })
        #expect(sanitized.contains { ($0["Bundle ID"] as? String) == "com.apple.inputmethod.Korean" })
    }
}
