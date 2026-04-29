import Foundation
import LibHangul

/// Manages loading and searching the Hanja dictionary
///
/// Uses `HanjaTable` from libhangul-swift with the bundled `hanja.txt` dictionary.
/// The dictionary is loaded lazily on first search to avoid blocking app startup.
public final class HanjaManager: @unchecked Sendable {
    
    public static let shared = HanjaManager()
    
    private var table: HanjaTable?
    private var isLoaded = false
    private let loadLock = NSLock()
    
    private init() {}
    
    /// Load the Hanja dictionary from the app bundle's resources
    /// Called lazily on first search, or can be called explicitly at startup
    public func loadIfNeeded() {
        loadLock.lock()
        defer { loadLock.unlock() }
        
        guard !isLoaded else { return }
        
        let table = HanjaTable()
        
        // Try to find hanja.txt in the resource bundle
        let bundle = Self.resourceBundle
        if let path = bundle.path(forResource: "hanja", ofType: "txt") {
            if table.load(filename: path) {
                self.table = table
                self.isLoaded = true
                DebugLogger.log("HanjaManager: Loaded dictionary from bundle: \(path)")
                return
            }
        }
        
        // Fallback: try HanjaTable.loadDefault() which searches common paths
        if table.load() {
            self.table = table
            self.isLoaded = true
            DebugLogger.log("HanjaManager: Loaded dictionary from default path")
        } else {
            DebugLogger.log("HanjaManager: WARNING - Failed to load hanja dictionary")
        }
    }
    
    /// Simple LRU cache for search results (dictionary doesn't change at runtime)
    private var searchCache: [String: [HanjaEntry]] = [:]
    private var cacheOrder: [String] = []
    private let cacheMaxSize = 32
    
    /// Search for Hanja entries matching the given Hangul key (exact match)
    /// - Parameter key: Hangul text to search for (e.g., "가")
    /// - Returns: Array of Hanja entries, empty if no results
    public func search(key: String) -> [HanjaEntry] {
        // Check cache first
        if let cached = searchCache[key] {
            // Move to end (most recently used)
            if let idx = cacheOrder.firstIndex(of: key) {
                cacheOrder.remove(at: idx)
                cacheOrder.append(key)
            }
            return cached
        }
        
        loadIfNeeded()
        
        guard let table = table else { return [] }
        guard let list = table.matchExact(key: key) else { return [] }
        
        var results: [HanjaEntry] = []
        for i in 0..<list.getSize() {
            if let hanja = list.getNth(i) {
                results.append(HanjaEntry(
                    hangul: hanja.getKey(),
                    hanja: hanja.getValue(),
                    meaning: hanja.getComment()
                ))
            }
        }
        
        // Store in cache
        searchCache[key] = results
        cacheOrder.append(key)
        
        // Evict oldest if over capacity
        if cacheOrder.count > cacheMaxSize {
            let evicted = cacheOrder.removeFirst()
            searchCache.removeValue(forKey: evicted)
        }
        
        return results
    }
    
    /// Resource bundle for loading dictionary data
    private static let resourceBundle: Bundle = {
        if let resourceURL = Bundle.main.resourceURL,
           let resourceBundle = Bundle(url: resourceURL.appendingPathComponent("PriType_PriTypeCore.bundle")) {
            return resourceBundle
        }
        return Bundle.main
    }()
}

/// A simple value type for Hanja search results
public struct HanjaEntry: Sendable {
    public let hangul: String   // 한글 (e.g., "가")
    public let hanja: String    // 한자 (e.g., "可")
    public let meaning: String  // 뜻 (e.g., "옳을 가")
}
