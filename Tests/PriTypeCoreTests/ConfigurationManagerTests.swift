import Testing
import Foundation
@testable import PriTypeCore

// MARK: - ConfigurationManager Tests

@Suite("ConfigurationManager", .serialized)
struct ConfigurationManagerTests {
    
    // MARK: - Keyboard Layout Tests
    
    @Test("Default keyboard ID is Dubeolsik (2)")
    func defaultKeyboardId() {
        #expect(ConfigurationManager.shared.keyboardId == "2")
    }
    
    @Test("Keyboard ID persists to UserDefaults")
    func keyboardIdPersistence() {
        let original = ConfigurationManager.shared.keyboardId
        defer { ConfigurationManager.shared.keyboardId = original }
        
        ConfigurationManager.shared.keyboardId = "3"
        #expect(ConfigurationManager.shared.keyboardId == "3")
        
        let stored = UserDefaults.standard.string(forKey: "com.pritype.keyboardId")
        #expect(stored == "3")
    }
    
    // MARK: - Toggle Key Tests
    
    @Test("Default toggle key is rightCommand")
    func defaultToggleKey() {
        #expect(ConfigurationManager.shared.toggleKey == .rightCommand)
    }
    
    @Test("Toggle key persists correctly")
    func toggleKeyPersistence() {
        let original = ConfigurationManager.shared.toggleKey
        defer { ConfigurationManager.shared.toggleKey = original }
        
        ConfigurationManager.shared.toggleKey = .controlSpace
        #expect(ConfigurationManager.shared.toggleKey == .controlSpace)
        #expect(ConfigurationManager.shared.controlSpaceAsToggle)
        #expect(!ConfigurationManager.shared.rightCommandAsToggle)
    }
    
    @Test("Toggle key convenience properties")
    func toggleKeyConvenienceProperties() {
        let original = ConfigurationManager.shared.toggleKey
        defer { ConfigurationManager.shared.toggleKey = original }
        
        ConfigurationManager.shared.toggleKey = .rightCommand
        #expect(ConfigurationManager.shared.rightCommandAsToggle)
        #expect(!ConfigurationManager.shared.controlSpaceAsToggle)
        
        ConfigurationManager.shared.toggleKey = .controlSpace
        #expect(!ConfigurationManager.shared.rightCommandAsToggle)
        #expect(ConfigurationManager.shared.controlSpaceAsToggle)
    }
    
    // MARK: - Text Input Feature Tests
    
    @Test("Default auto-capitalize is enabled")
    func defaultAutoCapitalize() {
        #expect(ConfigurationManager.shared.autoCapitalizeEnabled)
    }
    
    @Test("Auto-capitalize persists")
    func autoCapitalizePersistence() {
        let original = ConfigurationManager.shared.autoCapitalizeEnabled
        defer { ConfigurationManager.shared.autoCapitalizeEnabled = original }
        
        ConfigurationManager.shared.autoCapitalizeEnabled = false
        #expect(!ConfigurationManager.shared.autoCapitalizeEnabled)
        
        ConfigurationManager.shared.autoCapitalizeEnabled = true
        #expect(ConfigurationManager.shared.autoCapitalizeEnabled)
    }
    
    @Test("Default double-space-period is enabled")
    func defaultDoubleSpacePeriod() {
        #expect(ConfigurationManager.shared.doubleSpacePeriodEnabled)
    }
    
    @Test("Double-space-period persists")
    func doubleSpacePeriodPersistence() {
        let original = ConfigurationManager.shared.doubleSpacePeriodEnabled
        defer { ConfigurationManager.shared.doubleSpacePeriodEnabled = original }
        
        ConfigurationManager.shared.doubleSpacePeriodEnabled = false
        #expect(!ConfigurationManager.shared.doubleSpacePeriodEnabled)
        
        ConfigurationManager.shared.doubleSpacePeriodEnabled = true
        #expect(ConfigurationManager.shared.doubleSpacePeriodEnabled)
    }
}
