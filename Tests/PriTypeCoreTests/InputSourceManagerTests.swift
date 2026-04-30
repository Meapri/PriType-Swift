import Testing
@testable import PriTypeCore

// MARK: - AboutInfo & App Metadata Tests

@Suite("AboutInfo")
struct AboutInfoTests {
    
    @Test("Version string is non-empty")
    func versionIsNonEmpty() {
        #expect(!AboutInfo.version.isEmpty, "App version should not be empty")
    }
    
    @Test("Version string looks like semantic version")
    func versionFormat() {
        let parts = AboutInfo.version.split(separator: ".")
        #expect(parts.count >= 2, "Version should have at least major.minor")
        for part in parts {
            #expect(Int(part) != nil, "Version part should be numeric")
        }
    }
    
    @Test("App name is non-empty")
    func appNameIsNonEmpty() {
        #expect(!AboutInfo.appName.isEmpty, "App name should not be empty")
    }
    
    @Test("Copyright is non-empty")
    func copyrightIsNonEmpty() {
        #expect(!AboutInfo.copyright.isEmpty, "Copyright should not be empty")
    }
    
    @Test("Description is non-empty")
    func descriptionIsNonEmpty() {
        #expect(!AboutInfo.description.isEmpty, "Description should not be empty")
    }
}
