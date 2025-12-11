import Foundation
import LibHangul

/// Comprehensive Jamo mapper for converting between Unicode Jamo ranges
///
/// Supports mapping between:
/// - Jongseong (U+11A8-U+11C2) → Compatibility Jamo (U+3131-U+314E)
/// - Choseong (U+1100-U+1112) → Compatibility Jamo (U+3131-U+314E)
/// - Jungseong (U+1161-U+1175) → Compatibility Jamo (U+314F-U+3163)
///
/// ## Usage
/// ```swift
/// let compat = JamoMapper.toCompatibilityJamo(0x11A8) // Returns 0x3131 (ㄱ)
/// ```
public struct JamoMapper: Sendable {
    
    // MARK: - Static Mapping Tables (O(1) lookup)
    
    /// Unified Jamo to Compatibility Jamo mapping
    /// Merged from Jongseong, Choseong, and Jungseong maps for single O(1) lookup
    private static let unifiedCompatMap: [UInt32: UInt32] = {
        var map = [UInt32: UInt32]()
        
        // Jongseong (U+11A8-U+11C2)
        map[0x11A8] = 0x3131 // ㄱ
        map[0x11A9] = 0x3132 // ㄲ
        map[0x11AA] = 0x3133 // ㄳ
        map[0x11AB] = 0x3134 // ㄴ
        map[0x11AC] = 0x3135 // ㄵ
        map[0x11AD] = 0x3136 // ㄶ
        map[0x11AE] = 0x3137 // ㄷ
        map[0x11AF] = 0x3139 // ㄹ
        map[0x11B0] = 0x313A // ㄺ
        map[0x11B1] = 0x313B // ㄻ
        map[0x11B2] = 0x313C // ㄼ
        map[0x11B3] = 0x313D // ㄽ
        map[0x11B4] = 0x313E // ㄾ
        map[0x11B5] = 0x313F // ㄿ
        map[0x11B6] = 0x3140 // ㅀ
        map[0x11B7] = 0x3141 // ㅁ
        map[0x11B8] = 0x3142 // ㅂ
        map[0x11B9] = 0x3144 // ㅄ
        map[0x11BA] = 0x3145 // ㅅ
        map[0x11BB] = 0x3146 // ㅆ
        map[0x11BC] = 0x3147 // ㅇ
        map[0x11BD] = 0x3148 // ㅈ
        map[0x11BE] = 0x314A // ㅊ
        map[0x11BF] = 0x314B // ㅋ
        map[0x11C0] = 0x314C // ㅌ
        map[0x11C1] = 0x314D // ㅍ
        map[0x11C2] = 0x314E // ㅎ
        
        // Choseong (U+1100-U+1112)
        map[0x1100] = 0x3131 // ㄱ
        map[0x1101] = 0x3132 // ㄲ
        map[0x1102] = 0x3134 // ㄴ
        map[0x1103] = 0x3137 // ㄷ
        map[0x1104] = 0x3138 // ㄸ
        map[0x1105] = 0x3139 // ㄹ
        map[0x1106] = 0x3141 // ㅁ
        map[0x1107] = 0x3142 // ㅂ
        map[0x1108] = 0x3143 // ㅃ
        map[0x1109] = 0x3145 // ㅅ
        map[0x110A] = 0x3146 // ㅆ
        map[0x110B] = 0x3147 // ㅇ
        map[0x110C] = 0x3148 // ㅈ
        map[0x110D] = 0x3149 // ㅉ
        map[0x110E] = 0x314A // ㅊ
        map[0x110F] = 0x314B // ㅋ
        map[0x1110] = 0x314C // ㅌ
        map[0x1111] = 0x314D // ㅍ
        map[0x1112] = 0x314E // ㅎ
        
        // Jungseong (U+1161-U+1175)
        map[0x1161] = 0x314F // ㅏ
        map[0x1162] = 0x3150 // ㅐ
        map[0x1163] = 0x3151 // ㅑ
        map[0x1164] = 0x3152 // ㅒ
        map[0x1165] = 0x3153 // ㅓ
        map[0x1166] = 0x3154 // ㅔ
        map[0x1167] = 0x3155 // ㅕ
        map[0x1168] = 0x3156 // ㅖ
        map[0x1169] = 0x3157 // ㅗ
        map[0x116A] = 0x3158 // ㅘ
        map[0x116B] = 0x3159 // ㅙ
        map[0x116C] = 0x315A // ㅚ
        map[0x116D] = 0x315B // ㅛ
        map[0x116E] = 0x315C // ㅜ
        map[0x116F] = 0x315D // ㅝ
        map[0x1170] = 0x315E // ㅞ
        map[0x1171] = 0x315F // ㅟ
        map[0x1172] = 0x3160 // ㅠ
        map[0x1173] = 0x3161 // ㅡ
        map[0x1174] = 0x3162 // ㅢ
        map[0x1175] = 0x3163 // ㅣ
        
        return map
    }()
    
    // MARK: - Public API
    
    /// Convert any Jamo codepoint to its Compatibility Jamo equivalent
    /// - Parameter codepoint: Unicode codepoint of Jamo character
    /// - Returns: Compatibility Jamo codepoint, or nil if not a mappable Jamo
    public static func toCompatibilityJamo(_ codepoint: UInt32) -> UInt32? {
        return unifiedCompatMap[codepoint]
    }
    
    // MARK: - Range Checking
    
    /// Check if codepoint is in Choseong range
    public static func isChoseong(_ codepoint: UInt32) -> Bool {
        return codepoint >= 0x1100 && codepoint <= 0x1112
    }
    
    /// Check if codepoint is in Jungseong range
    public static func isJungseong(_ codepoint: UInt32) -> Bool {
        return codepoint >= 0x1161 && codepoint <= 0x1175
    }
    
    /// Check if codepoint is in Jongseong range
    public static func isJongseong(_ codepoint: UInt32) -> Bool {
        return codepoint >= 0x11A8 && codepoint <= 0x11C2
    }
    
    /// Check if codepoint is any type of Jamo
    public static func isJamo(_ codepoint: UInt32) -> Bool {
        return isChoseong(codepoint) || isJungseong(codepoint) || isJongseong(codepoint)
    }
}
