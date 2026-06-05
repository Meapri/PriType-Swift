import Testing
import Foundation
@testable import PriTypeCore

/// Guards the IMK input-source registration in the source-tree `Info.plist`.
///
/// A malformed registration (e.g. a top-level `TISInputSourceID` duplicating a
/// child input-mode id, or per-mode `TISInputSourceID`/`tsInputModeDefaultStateKey`)
/// silently breaks Korean composition system-wide with no error — this happened in
/// commit 030a035 and was fixed in fd72334. These tests catch such regressions at
/// unit-test time (no device / re-login needed).
///
/// Dual-mode design: PriType registers exactly two modes — Korean (smKorean) and a
/// pass-through English (smRoman) — plus `TICapsLockLanguageSwitchCapable` so macOS
/// can switch between them natively (Caps Lock / input-source shortcut).
@Suite("Registration Contract (Info.plist)")
struct RegistrationContractTests {

    enum ContractError: Error { case notADict }

    /// Loads the repo-root `Info.plist` (the one the build copies into the bundle).
    /// `#filePath` → Tests/PriTypeCoreTests/<thisFile>; repo root is three levels up.
    private func loadInfoPlist() throws -> [String: Any] {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PriTypeCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("Info.plist"))
        guard let dict = try PropertyListSerialization
            .propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw ContractError.notADict
        }
        return dict
    }

    private func modes(_ info: [String: Any]) -> [String: Any] {
        let comp = info["ComponentInputModeDict"] as? [String: Any]
        return (comp?["tsInputModeListKey"] as? [String: Any]) ?? [:]
    }

    @Test("Registers exactly two modes: korean(smKorean) + english(smRoman)")
    func twoModes() throws {
        let info = try loadInfoPlist()
        let list = modes(info)
        #expect(list.count == 2, "expected exactly 2 input modes, got \(list.count)")

        let korean = list["com.pritype.inputmethod.v2"] as? [String: Any]
        let english = list["com.pritype.inputmethod.v2.english"] as? [String: Any]
        #expect(korean?["tsInputModeScriptKey"] as? String == "smKorean")
        #expect(english?["tsInputModeScriptKey"] as? String == "smRoman")

        let comp = info["ComponentInputModeDict"] as? [String: Any]
        let visible = comp?["tsVisibleInputModeOrderedArrayKey"] as? [String]
        #expect(visible == ["com.pritype.inputmethod.v2", "com.pritype.inputmethod.v2.english"])
    }

    @Test("Declares Caps Lock language-switch capability")
    func capsLockCapable() throws {
        let info = try loadInfoPlist()
        #expect(info["TICapsLockLanguageSwitchCapable"] as? Bool == true)
    }

    @Test("Forbidden registration keys are absent (regression guard)")
    func noForbiddenKeys() throws {
        let info = try loadInfoPlist()
        // The 030a035 regression: a top-level TISInputSourceID equal to a child mode id.
        #expect(info["TISInputSourceID"] == nil, "top-level TISInputSourceID must NOT be present")

        for (id, value) in modes(info) {
            let mode = value as? [String: Any] ?? [:]
            #expect(mode["TISInputSourceID"] == nil, "per-mode TISInputSourceID must be absent (\(id))")
            #expect(mode["tsInputModeDefaultStateKey"] == nil, "tsInputModeDefaultStateKey must be absent (\(id))")
        }
    }

    @Test("Core identity keys are correct")
    func coreIdentity() throws {
        let info = try loadInfoPlist()
        #expect(info["CFBundleIdentifier"] as? String == "com.pritype.inputmethod.v2")
        #expect(info["InputMethodConnectionName"] as? String == "PriType_InputString_v2")
        #expect(info["InputMethodServerControllerClass"] as? String == "PriTypeInputController")
        let repertoire = info["tsInputMethodCharacterRepertoireKey"] as? [String]
        #expect(repertoire?.contains("Hang") == true, "must declare Hangul repertoire")
    }
}
