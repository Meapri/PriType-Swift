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
    
    /// Jamo → special symbol mapping (Windows-style)
    private var jamoSymbols: [String: [HanjaEntry]] = [:]
    private var jamoSymbolsLoaded = false
    
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
    
    /// Load jamo symbol mapping from bundled JSON
    private func loadJamoSymbolsIfNeeded() {
        guard !jamoSymbolsLoaded else { return }
        
        let bundle = Self.resourceBundle
        guard let url = bundle.url(forResource: "jamo_symbols", withExtension: "json") else {
            DebugLogger.log("HanjaManager: jamo_symbols.json not found in bundle")
            jamoSymbolsLoaded = true
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let raw = try JSONDecoder().decode([String: [JamoSymbolRaw]].self, from: data)
            for (jamo, symbols) in raw {
                jamoSymbols[jamo] = symbols.map { HanjaEntry(hangul: jamo, hanja: $0.char, meaning: $0.desc) }
            }
            DebugLogger.log("HanjaManager: Loaded jamo symbols (\(jamoSymbols.count) keys, \(jamoSymbols.values.map(\.count).reduce(0, +)) entries)")
        } catch {
            DebugLogger.log("HanjaManager: Failed to load jamo_symbols.json: \(error)")
        }
        jamoSymbolsLoaded = true
    }
    
    /// Simple LRU cache for search results (dictionary doesn't change at runtime)
    private var searchCache: [String: [HanjaEntry]] = [:]
    private var cacheOrder: [String] = []
    private let cacheMaxSize = 32
    
    /// Search for Hanja entries matching the given Hangul key (exact match)
    /// - Parameter key: Hangul text to search for (e.g., "가") or a jamo consonant (e.g., "ㅁ")
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
        
        // Jamo consonant → search symbol table instead of hanja dictionary
        // Normalize: libhangul preedit uses Choseong Jamo (U+1100~), but our
        // JSON keys use Compatibility Jamo (U+3131~). Convert before lookup.
        let normalizedKey: String
        if key.count == 1, let char = key.first, char.isJamoConsonant {
            normalizedKey = key
        } else if key.count == 1, let char = key.first, char.isChoseongJamo {
            normalizedKey = String(char.choseongToCompatibility)
        } else {
            normalizedKey = ""
        }
        
        if !normalizedKey.isEmpty {
            loadJamoSymbolsIfNeeded()
            let results = jamoSymbols[normalizedKey] ?? []
            // Cache with original key
            searchCache[key] = results
            cacheOrder.append(key)
            if cacheOrder.count > cacheMaxSize {
                let evicted = cacheOrder.removeFirst()
                searchCache.removeValue(forKey: evicted)
            }
            return results
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

/// Raw JSON structure for jamo_symbols.json
private struct JamoSymbolRaw: Decodable {
    let char: String
    let desc: String
}

/// A simple value type for Hanja search results
public struct HanjaEntry: Sendable {
    public let hangul: String   // 한글 (e.g., "가") or jamo (e.g., "ㅁ")
    public let hanja: String    // 한자 (e.g., "可") or symbol (e.g., "♥")
    public let meaning: String  // 뜻 (e.g., "옳을 가") or description (e.g., "검은 하트")
}

// MARK: - Character Extension for Jamo detection
extension Character {
    /// Returns true if this character is a Hangul Compatibility Jamo consonant (ㄱ-ㅎ, U+3131-U+314E)
    var isJamoConsonant: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        let v = scalar.value
        return v >= 0x3131 && v <= 0x314E
    }
    
    /// Returns true if this character is a Hangul Jamo Choseong (initial consonant, U+1100-U+1112)
    /// These are the "first/last/middle" jamo used internally by libhangul
    var isChoseongJamo: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        let v = scalar.value
        return v >= 0x1100 && v <= 0x1112
    }
    
    /// Convert a Choseong Jamo (U+1100~) to Compatibility Jamo (U+3131~)
    var choseongToCompatibility: Character {
        guard let scalar = unicodeScalars.first else { return self }
        let v = scalar.value
        guard v >= 0x1100 && v <= 0x1112 else { return self }
        // Mapping: U+1100 ㄱ→U+3131, U+1101 ㄲ→U+3132, ...
        let mapping: [UInt32: UInt32] = [
            0x1100: 0x3131, // ㄱ
            0x1101: 0x3132, // ㄲ
            0x1102: 0x3134, // ㄴ
            0x1103: 0x3137, // ㄷ
            0x1104: 0x3138, // ㄸ
            0x1105: 0x3139, // ㄹ
            0x1106: 0x3141, // ㅁ
            0x1107: 0x3142, // ㅂ
            0x1108: 0x3143, // ㅃ
            0x1109: 0x3145, // ㅅ
            0x110A: 0x3146, // ㅆ
            0x110B: 0x3147, // ㅇ
            0x110C: 0x3148, // ㅈ
            0x110D: 0x3149, // ㅉ
            0x110E: 0x314A, // ㅊ
            0x110F: 0x314B, // ㅋ
            0x1110: 0x314C, // ㅌ
            0x1111: 0x314D, // ㅍ
            0x1112: 0x314E, // ㅎ
        ]
        if let compat = mapping[v], let scalar = UnicodeScalar(compat) {
            return Character(scalar)
        }
        return self
    }
}
