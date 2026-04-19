import Foundation

class HangulKeyboard {
    var keyMap: [Int: UInt32] = [:]
    
    init() {
        keyMap[Int(Character("a").asciiValue!)] = 0x1106  // ㅁ
    }
    
    public func mapKey(_ key: Int) -> UInt32 {
        if let mapped = keyMap[key] {
            return mapped
        }
        // 대문자에 매핑이 없으면 소문자로 폴백
        if let scalar = UnicodeScalar(key) {
            let char = Character(scalar)
            if char.isUppercase {
                let lowered = char.lowercased()
                if let lowerChar = lowered.first, let ascii = lowerChar.asciiValue {
                    return keyMap[Int(ascii)] ?? 0
                }
            }
        }
        return 0
    }
}

let k = HangulKeyboard()
print(String(format: "%X", k.mapKey(Int(Character("A").asciiValue!))))
