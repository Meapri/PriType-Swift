import XCTest
@testable import PriTypeCore

final class ConfigurationManagerTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private let testDefaults = UserDefaults.standard
    private let testKeys = [
        "com.pritype.keyboardId",
        "com.pritype.toggleKey",
        "com.pritype.autoCapitalize",
        "com.pritype.doubleSpacePeriod"
    ]
    
    // MARK: - Setup/Teardown
    
    override func setUp() {
        super.setUp()
        // Clean up test keys before each test
        for key in testKeys {
            testDefaults.removeObject(forKey: key)
        }
    }
    
    override func tearDown() {
        // Clean up after tests
        for key in testKeys {
            testDefaults.removeObject(forKey: key)
        }
        super.tearDown()
    }
    
    // MARK: - Keyboard Layout Tests
    
    func testDefaultKeyboardId() {
        // Default should be "2" (Dubeolsik)
        XCTAssertEqual(ConfigurationManager.shared.keyboardId, "2")
    }
    
    func testKeyboardIdPersistence() {
        // Change layout
        ConfigurationManager.shared.keyboardId = "3"
        XCTAssertEqual(ConfigurationManager.shared.keyboardId, "3")
        
        // Verify persistence
        XCTAssertEqual(testDefaults.string(forKey: "com.pritype.keyboardId"), "3")
        
        // Reset
        ConfigurationManager.shared.keyboardId = "2"
    }
    
    func testKeyboardIdNotificationPosted() {
        let expectation = expectation(forNotification: Notification.Name("PriTypeKeyboardLayoutChanged"), object: nil)
        
        // Change layout
        ConfigurationManager.shared.keyboardId = "3y"
        
        wait(for: [expectation], timeout: 1.0)
        
        // Reset
        ConfigurationManager.shared.keyboardId = "2"
    }
    
    // MARK: - Toggle Key Tests
    
    func testDefaultToggleKey() {
        // Default should be rightCommand
        XCTAssertEqual(ConfigurationManager.shared.toggleKey, .rightCommand)
    }
    
    func testToggleKeyPersistence() {
        ConfigurationManager.shared.toggleKey = .controlSpace
        XCTAssertEqual(ConfigurationManager.shared.toggleKey, .controlSpace)
        XCTAssertTrue(ConfigurationManager.shared.controlSpaceAsToggle)
        XCTAssertFalse(ConfigurationManager.shared.rightCommandAsToggle)
        
        // Reset
        ConfigurationManager.shared.toggleKey = .rightCommand
    }
    
    func testToggleKeyConvenienceProperties() {
        ConfigurationManager.shared.toggleKey = .rightCommand
        XCTAssertTrue(ConfigurationManager.shared.rightCommandAsToggle)
        XCTAssertFalse(ConfigurationManager.shared.controlSpaceAsToggle)
        
        ConfigurationManager.shared.toggleKey = .controlSpace
        XCTAssertFalse(ConfigurationManager.shared.rightCommandAsToggle)
        XCTAssertTrue(ConfigurationManager.shared.controlSpaceAsToggle)
        
        // Reset
        ConfigurationManager.shared.toggleKey = .rightCommand
    }
    
    // MARK: - Text Input Feature Tests
    
    func testDefaultAutoCapitalize() {
        // Default should be enabled
        XCTAssertTrue(ConfigurationManager.shared.autoCapitalizeEnabled)
    }
    
    func testAutoCapitalizePersistence() {
        ConfigurationManager.shared.autoCapitalizeEnabled = false
        XCTAssertFalse(ConfigurationManager.shared.autoCapitalizeEnabled)
        
        ConfigurationManager.shared.autoCapitalizeEnabled = true
        XCTAssertTrue(ConfigurationManager.shared.autoCapitalizeEnabled)
    }
    
    func testDefaultDoubleSpacePeriod() {
        // Default should be enabled
        XCTAssertTrue(ConfigurationManager.shared.doubleSpacePeriodEnabled)
    }
    
    func testDoubleSpacePeriodPersistence() {
        ConfigurationManager.shared.doubleSpacePeriodEnabled = false
        XCTAssertFalse(ConfigurationManager.shared.doubleSpacePeriodEnabled)
        
        ConfigurationManager.shared.doubleSpacePeriodEnabled = true
        XCTAssertTrue(ConfigurationManager.shared.doubleSpacePeriodEnabled)
    }
}
