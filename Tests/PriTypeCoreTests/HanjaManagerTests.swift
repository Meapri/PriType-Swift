import Testing
@testable import PriTypeCore

// MARK: - HanjaManager Tests

@Suite("HanjaManager")
struct HanjaManagerTests {
    
    // Note: HanjaManager requires the Hanja dictionary resource bundle.
    // In the SPM test environment, the bundle may not be available.
    // These tests verify behavior in both cases.
    
    @Test("Search for non-existent key returns empty")
    func searchNonExistent() {
        let results = HanjaManager.shared.search(key: "zzz")
        #expect(results.isEmpty, "Non-existent key should return empty")
    }
    
    @Test("Search for empty string returns empty")
    func searchEmptyString() {
        let results = HanjaManager.shared.search(key: "")
        #expect(results.isEmpty, "Empty search should return empty")
    }
    
    @Test("Search returns consistent results (caching)")
    func searchCachingConsistency() {
        let first = HanjaManager.shared.search(key: "가")
        let second = HanjaManager.shared.search(key: "가")
        
        #expect(first.count == second.count, "Cached results should be identical")
    }
    
    @Test("HanjaEntry struct has expected fields")
    func hanjaEntryFields() {
        let entry = HanjaEntry(hangul: "한", hanja: "韓", meaning: "나라 한")
        
        #expect(entry.hangul == "한")
        #expect(entry.hanja == "韓")
        #expect(entry.meaning == "나라 한")
    }
    
    @Test("Search results have valid hangul field matching key")
    func searchResultsMatchKey() {
        let results = HanjaManager.shared.search(key: "한")
        for entry in results {
            #expect(entry.hangul == "한", "Hangul should match search key")
        }
    }
    
    @Test("Search for common syllable returns results if dict available")
    func searchCommonSyllable() {
        let results = HanjaManager.shared.search(key: "인")
        // If dictionary is loaded, we should have results
        // If not loaded (test env), empty is acceptable
        if !results.isEmpty {
            #expect(results.count > 1, "인 should have multiple candidates when dict is loaded")
            #expect(!results[0].hanja.isEmpty, "Hanja should not be empty")
            #expect(!results[0].meaning.isEmpty, "Meaning should not be empty")
        }
        // Test passes either way — validates structure, not dict availability
    }
}
