import Foundation
import LibHangul

public struct JamoMapper {
    /// Map Jongseong (U+11xx) to Compatibility Jamo (U+31xx)
    /// This is used for better visual rendering on macOS
    public static func mapJongseongToCompat(_ c: UInt32) -> UInt32? {
        switch c {
        case 0x11A8: return 0x3131 // ㄱ
        case 0x11A9: return 0x3132 // ㄲ
        case 0x11AA: return 0x3133 // ㄳ
        case 0x11AB: return 0x3134 // ㄴ
        case 0x11AC: return 0x3135 // ㄵ
        case 0x11AD: return 0x3136 // ㄶ
        case 0x11AE: return 0x3137 // ㄷ
        case 0x11AF: return 0x3139 // ㄹ
        case 0x11B0: return 0x313A // ㄺ
        case 0x11B1: return 0x313B // ㄻ
        case 0x11B2: return 0x313C // ㄼ
        case 0x11B3: return 0x313D // ㄽ
        case 0x11B4: return 0x313E // ㄾ
        case 0x11B5: return 0x313F // ㄿ
        case 0x11B6: return 0x3140 // ㅀ
        case 0x11B7: return 0x3141 // ㅁ
        case 0x11B8: return 0x3142 // ㅂ
        case 0x11B9: return 0x3144 // ㅄ (Note: 0x3144 is BS, 0x11B9 is BS)
        case 0x11BA: return 0x3145 // ㅅ
        case 0x11BB: return 0x3146 // ㅆ
        case 0x11BC: return 0x3147 // ㅇ
        case 0x11BD: return 0x3148 // ㅈ
        case 0x11BE: return 0x314A // ㅊ
        case 0x11BF: return 0x314B // ㅋ
        case 0x11C0: return 0x314C // ㅌ
        case 0x11C1: return 0x314D // ㅍ
        case 0x11C2: return 0x314E // ㅎ
        default: return nil
        }
    }
}
