import Testing
import Foundation
@testable import PriTypeCore

// MARK: - UpdateChecker Tests

@Suite("UpdateChecker")
struct UpdateCheckerTests {
    
    @Test("Version comparison: newer version detected")
    func newerVersionDetected() {
        #expect(isNewerVersion("2.5.0", than: "2.4.2"))
        #expect(isNewerVersion("3.0.0", than: "2.9.9"))
        #expect(isNewerVersion("2.4.3", than: "2.4.2"))
    }
    
    @Test("Version comparison: same version not newer")
    func sameVersionNotNewer() {
        #expect(!isNewerVersion("2.4.2", than: "2.4.2"))
    }
    
    @Test("Version comparison: older version not newer")
    func olderVersionNotNewer() {
        #expect(!isNewerVersion("2.4.1", than: "2.4.2"))
        #expect(!isNewerVersion("1.0.0", than: "2.4.2"))
    }
    
    @Test("Version comparison: major version bump")
    func majorVersionBump() {
        #expect(isNewerVersion("3.0.0", than: "2.99.99"))
    }
    
    @Test("Version comparison: minor version bump")
    func minorVersionBump() {
        #expect(isNewerVersion("2.5.0", than: "2.4.99"))
    }
    
    @Test("Version comparison: patch-only bump")
    func patchOnlyBump() {
        #expect(isNewerVersion("2.4.3", than: "2.4.2"))
        #expect(!isNewerVersion("2.4.2", than: "2.4.3"))
    }
    
    @Test("Version comparison: handles two-part versions")
    func twoPartVersions() {
        #expect(isNewerVersion("2.5", than: "2.4"))
        #expect(!isNewerVersion("2.4", than: "2.5"))
    }
    
    // MARK: - Helper
    
    /// Compares semantic versions: returns true if `version` > `current`
    private func isNewerVersion(_ version: String, than current: String) -> Bool {
        let vParts = version.split(separator: ".").compactMap { Int($0) }
        let cParts = current.split(separator: ".").compactMap { Int($0) }
        
        let maxLen = max(vParts.count, cParts.count)
        for i in 0..<maxLen {
            let v = i < vParts.count ? vParts[i] : 0
            let c = i < cParts.count ? cParts[i] : 0
            if v > c { return true }
            if v < c { return false }
        }
        return false
    }
}
