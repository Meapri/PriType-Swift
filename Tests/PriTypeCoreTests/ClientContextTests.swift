import Testing
@testable import PriTypeCore

// MARK: - ClientContext Tests

@Suite("ClientContext Struct")
struct ClientContextTests {
    
    @Test("Finder detection by bundle ID")
    func finderDetection() {
        let finderCtx = ClientContext(
            bundleId: "com.apple.finder",
            hasTextInputCapability: true,
            isLikelyDesktopArea: false
        )
        
        #expect(finderCtx.isFinder)
        #expect(!finderCtx.shouldUseImmediateMode, "Finder with text capability and non-desktop should use normal mode")
    }
    
    @Test("Finder desktop uses immediate mode")
    func finderDesktopShouldUseImmediateMode() {
        let desktopCtx = ClientContext(
            bundleId: "com.apple.finder",
            hasTextInputCapability: true,
            isLikelyDesktopArea: true
        )
        
        #expect(desktopCtx.isFinder)
        #expect(desktopCtx.shouldUseImmediateMode)
    }
    
    @Test("Finder without text capability uses immediate mode")
    func finderNoTextCapabilityShouldUseImmediateMode() {
        let noTextCtx = ClientContext(
            bundleId: "com.apple.finder",
            hasTextInputCapability: false,
            isLikelyDesktopArea: false
        )
        
        #expect(noTextCtx.shouldUseImmediateMode)
    }
    
    @Test("Non-Finder apps never use immediate mode")
    func nonFinderAppNeverUsesImmediateMode() {
        let safariCtx = ClientContext(
            bundleId: "com.apple.Safari",
            hasTextInputCapability: true,
            isLikelyDesktopArea: true
        )
        
        #expect(!safariCtx.isFinder)
        #expect(!safariCtx.shouldUseImmediateMode)
    }
    
    @Test("Empty bundle ID is not Finder")
    func unknownBundleId() {
        let unknownCtx = ClientContext(
            bundleId: "",
            hasTextInputCapability: false,
            isLikelyDesktopArea: false
        )
        
        #expect(!unknownCtx.isFinder)
        #expect(!unknownCtx.shouldUseImmediateMode)
    }
    
    // MARK: - Resolution / Desktop Detection (migrated from ResolutionTests.swift)
    
    @Test("Desktop detection — standard resolution")
    func desktopDetectionStandard() {
        #expect(isDesktopArea(x: 5.0, y: 20.0), "Should detect Desktop at (5, 20)")
        #expect(!isDesktopArea(x: 800.0, y: 600.0), "Should NOT detect Search Bar at (800, 600)")
    }
    
    @Test("Desktop detection — 5K Retina")
    func desktopDetection5K() {
        #expect(isDesktopArea(x: 5.0, y: 20.0), "5K: Desktop coords remain small in Points")
        #expect(!isDesktopArea(x: 2400.0, y: 1350.0), "5K: Search Bar at (2400, 1350)")
    }
    
    @Test("Desktop detection — multi-monitor with negative coords")
    func desktopDetectionMultiMonitor() {
        #expect(!isDesktopArea(x: -1000.0, y: 500.0), "Multi-mon: Left monitor")
        #expect(!isDesktopArea(x: 500.0, y: -1000.0), "Multi-mon: Bottom monitor")
    }
    
    private func isDesktopArea(x: Double, y: Double) -> Bool {
        return x < Double(PriTypeConfig.finderDesktopThreshold) && y < Double(PriTypeConfig.finderDesktopThreshold)
    }
}
