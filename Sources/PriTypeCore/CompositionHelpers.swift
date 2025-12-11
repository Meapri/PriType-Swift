import Foundation
import LibHangul

/// Helper functions for Hangul composition string conversion and normalization
///
/// This struct provides static utility methods extracted from `HangulComposer`
/// to improve code organization and reusability.
public struct CompositionHelpers: Sendable {
    
    // MARK: - String Conversion
    
    /// Convert UCSChar array (from libhangul) to Swift String
    /// - Parameter codePoints: Array of UInt32 Unicode code points (UCSChar)
    /// - Returns: String representation of the code points
    public static func convertToString(_ codePoints: [UInt32]) -> String {
        return String(codePoints.compactMap { UnicodeScalar($0) }.map { Character($0) })
    }
    
    // MARK: - Jamo Normalization
    
    /// Normalize Jamo characters to Compatibility Jamo for display
    ///
    /// Converts internal Jamo representations (Choseong/Jungseong/Jongseong)
    /// to Compatibility Jamo for better visual display in marked text.
    ///
    /// - Parameter preedit: Array of UInt32 code points from libhangul
    /// - Returns: Normalized string suitable for display
    public static func normalizeJamoForDisplay(_ preedit: [UInt32]) -> String {
        let scalars = preedit.compactMap { UnicodeScalar($0) }
        let mapped = scalars.map { scalar -> UnicodeScalar in
            let val = scalar.value
            
            // 1. Try standard helper (covers Choseong/Jungseong)
            let stdMapped = HangulCharacter.jamoToCJamo(val)
            if stdMapped != val {
                return UnicodeScalar(stdMapped) ?? scalar
            }
            
            // 2. Use unified JamoMapper for all Jamo types
            if let compat = JamoMapper.toCompatibilityJamo(val) {
                return UnicodeScalar(compat) ?? scalar
            }
            
            return scalar
        }
        return String(mapped.map { Character($0) })
    }
}
