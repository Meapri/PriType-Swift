import Testing
@testable import PriTypeCore

@Suite("Brand")
struct BrandTests {
    @Test("Unpackaged test host falls back to official PriType identity")
    func officialFallbackOutsideIME() {
        #expect(Brand.bundleID == Brand.officialBundleID)
        #expect(Brand.displayName == Brand.officialDisplayName)
        #expect(Brand.koreanModeID == Brand.officialKoreanModeID)
        #expect(Brand.englishModeID == Brand.officialEnglishModeID)
        #expect(Brand.tracksUpstreamUpdates)
    }

    @Test("Minted collision mode id uses the bundle's last component")
    func mintedCollisionModeID() {
        #expect(Brand.mintedCollisionModeID(forBundleID: Brand.officialBundleID) == "com.pritype.inputmethod.v2.v2")
        #expect(Brand.mintedCollisionModeID(forBundleID: Brand.patchBundleID) == "com.calvinjkim.patchtype.patchtype")
    }
}
