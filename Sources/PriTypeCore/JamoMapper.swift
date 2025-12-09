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
    
    /// Jongseong (U+11A8-U+11C2) to Compatibility Jamo mapping
    private static let jongseongToCompatMap: [UInt32: UInt32] = [
        0x11A8: 0x3131, // ㄱ
        0x11A9: 0x3132, // ㄲ
        0x11AA: 0x3133, // ㄳ
        0x11AB: 0x3134, // ㄴ
        0x11AC: 0x3135, // ㄵ
        0x11AD: 0x3136, // ㄶ
        0x11AE: 0x3137, // ㄷ
        0x11AF: 0x3139, // ㄹ
        0x11B0: 0x313A, // ㄺ
        0x11B1: 0x313B, // ㄻ
        0x11B2: 0x313C, // ㄼ
        0x11B3: 0x313D, // ㄽ
        0x11B4: 0x313E, // ㄾ
        0x11B5: 0x313F, // ㄿ
        0x11B6: 0x3140, // ㅀ
        0x11B7: 0x3141, // ㅁ
        0x11B8: 0x3142, // ㅂ
        0x11B9: 0x3144, // ㅄ
        0x11BA: 0x3145, // ㅅ
        0x11BB: 0x3146, // ㅆ
        0x11BC: 0x3147, // ㅇ
        0x11BD: 0x3148, // ㅈ
        0x11BE: 0x314A, // ㅊ
        0x11BF: 0x314B, // ㅋ
        0x11C0: 0x314C, // ㅌ
        0x11C1: 0x314D, // ㅍ
        0x11C2: 0x314E, // ㅎ
    ]
    
    /// Choseong (U+1100-U+1112) to Compatibility Jamo mapping
    private static let choseongToCompatMap: [UInt32: UInt32] = [
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
    
    /// Jungseong (U+1161-U+1175) to Compatibility Jamo mapping
    private static let jungseongToCompatMap: [UInt32: UInt32] = [
        0x1161: 0x314F, // ㅏ
        0x1162: 0x3150, // ㅐ
        0x1163: 0x3151, // ㅑ
        0x1164: 0x3152, // ㅒ
        0x1165: 0x3153, // ㅓ
        0x1166: 0x3154, // ㅔ
        0x1167: 0x3155, // ㅕ
        0x1168: 0x3156, // ㅖ
        0x1169: 0x3157, // ㅗ
        0x116A: 0x3158, // ㅘ
        0x116B: 0x3159, // ㅙ
        0x116C: 0x315A, // ㅚ
        0x116D: 0x315B, // ㅛ
        0x116E: 0x315C, // ㅜ
        0x116F: 0x315D, // ㅝ
        0x1170: 0x315E, // ㅞ
        0x1171: 0x315F, // ㅟ
        0x1172: 0x3160, // ㅠ
        0x1173: 0x3161, // ㅡ
        0x1174: 0x3162, // ㅢ
        0x1175: 0x3163, // ㅣ
    ]
    
    // MARK: - Public API
    
    /// Convert any Jamo codepoint to its Compatibility Jamo equivalent
    /// - Parameter codepoint: Unicode codepoint of Jamo character
    /// - Returns: Compatibility Jamo codepoint, or nil if not a mappable Jamo
    public static func toCompatibilityJamo(_ codepoint: UInt32) -> UInt32? {
        // Check Jongseong range first (most common in preedit)
        if let compat = jongseongToCompatMap[codepoint] {
            return compat
        }
        
        // Check Choseong range
        if let compat = choseongToCompatMap[codepoint] {
            return compat
        }
        
        // Check Jungseong range
        if let compat = jungseongToCompatMap[codepoint] {
            return compat
        }
        
        return nil
    }
    
    /// Map Jongseong (U+11xx) to Compatibility Jamo (U+31xx)
    /// - Parameter c: Jongseong codepoint
    /// - Returns: Compatibility Jamo codepoint, or nil if not a Jongseong
    /// - Note: Deprecated. Use `toCompatibilityJamo(_:)` instead.
    @available(*, deprecated, renamed: "toCompatibilityJamo(_:)")
    public static func mapJongseongToCompat(_ c: UInt32) -> UInt32? {
        return jongseongToCompatMap[c]
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
