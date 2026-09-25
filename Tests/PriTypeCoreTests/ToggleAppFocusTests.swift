import Testing
@testable import PriTypeCore

@Suite("Toggle app keyboard focus")
struct ToggleAppFocusTests {
    private let remote = "com.microsoft.rdc.macos"
    private let spotlight = "com.apple.Spotlight"

    @Test("Spotlight can toggle over an excluded app, which regains exclusion after dismissal")
    func overlayFocusLifecycle() {
        let decisions = [remote, spotlight, remote].map { focused in
            ToggleAppFocus.isExcluded(
                bundleIDs: [remote], frontmostBundleID: remote, focusedBundleID: focused
            )
        }
        #expect(decisions == [true, false, true])
    }

    @Test("A running excluded app does not exclude another focused app")
    func backgroundApp() {
        #expect(!ToggleAppFocus.isExcluded(
            bundleIDs: [remote], frontmostBundleID: "com.apple.TextEdit",
            focusedBundleID: "com.apple.TextEdit"
        ))
    }

    @Test("An explicitly excluded overlay still passes the toggle through")
    func excludedOverlay() {
        #expect(ToggleAppFocus.isExcluded(
            bundleIDs: [spotlight], frontmostBundleID: remote, focusedBundleID: spotlight
        ))
    }

    @Test("Unavailable accessibility falls back to the frontmost app")
    func missingFocus() {
        #expect(ToggleAppFocus.isExcluded(
            bundleIDs: [remote], frontmostBundleID: remote, focusedBundleID: nil
        ))
        #expect(!ToggleAppFocus.isExcluded(
            bundleIDs: [remote], frontmostBundleID: spotlight, focusedBundleID: nil
        ))
        #expect(!ToggleAppFocus.isExcluded(
            bundleIDs: [remote], frontmostBundleID: nil, focusedBundleID: nil
        ))
    }

    @Test("Removing an exclusion immediately restores toggling")
    func noExclusions() {
        #expect(!ToggleAppFocus.isExcluded(
            bundleIDs: [], frontmostBundleID: remote, focusedBundleID: remote
        ))
    }
}
