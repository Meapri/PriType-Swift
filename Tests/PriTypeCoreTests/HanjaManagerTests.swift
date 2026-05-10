import Testing
@testable import PriTypeCore

// MARK: - HanjaManager Tests

@Suite("HanjaManager")
struct HanjaManagerTests {
    
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

        #expect(results.count > 1, "인 should have multiple candidates")
        #expect(!results[0].hanja.isEmpty, "Hanja should not be empty")
        #expect(!results[0].meaning.isEmpty, "Meaning should not be empty")
    }

    @Test("Search for common syllable requires bundled dictionary")
    func searchCommonSyllableRequiresBundledDictionary() {
        let results = HanjaManager.shared.search(key: "가")

        #expect(results.count > 10, "Bundled hanja dictionary should be loaded in tests")
        #expect(results.allSatisfy { $0.hangul == "가" }, "All results should match the search key")
    }
}
