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

    @Test("Secure input policy does not treat leaked global secure input as this field")
    func secureInputPolicyIgnoresGlobalSecureInputOnNormalFields() {
        #expect(!SecureInputPolicy.shouldPassThrough(SecureInputSignals(
            bundleId: "com.example.messenger",
            hasTextInputCapability: true,
            hasInvalidSelection: false,
            hasGlobalSecureInput: true,
            hasMarkedTextSupport: true
        )))
    }

    @Test("Secure input policy handles invalid selection capability cases")
    func secureInputPolicyHandlesInvalidSelectionCapabilityCases() {
        #expect(SecureInputPolicy.shouldPassThrough(SecureInputSignals(
            bundleId: "com.example.PasswordPanel",
            hasTextInputCapability: false,
            hasInvalidSelection: true,
            hasGlobalSecureInput: false,
            hasMarkedTextSupport: false
        )))

        #expect(!SecureInputPolicy.shouldPassThrough(SecureInputSignals(
            bundleId: "com.example.messenger",
            hasTextInputCapability: true,
            hasInvalidSelection: true,
            hasGlobalSecureInput: false,
            hasMarkedTextSupport: true
        )))

        #expect(!SecureInputPolicy.shouldPassThrough(SecureInputSignals(
            bundleId: "com.google.Chrome",
            hasTextInputCapability: true,
            hasInvalidSelection: true,
            hasGlobalSecureInput: false,
            hasMarkedTextSupport: true
        )))

        #expect(SecureInputPolicy.shouldPassThrough(SecureInputSignals(
            bundleId: "com.google.Chrome",
            hasTextInputCapability: true,
            hasInvalidSelection: true,
            hasGlobalSecureInput: true,
            hasMarkedTextSupport: true
        )))
    }

    @Test("Secure input policy always passes through system secure clients")
    func secureInputPolicyPassesThroughSystemSecureClients() {
        #expect(SecureInputPolicy.shouldPassThrough(SecureInputSignals(
            bundleId: "com.apple.SecurityAgent",
            hasTextInputCapability: true,
            hasInvalidSelection: false,
            hasGlobalSecureInput: false,
            hasMarkedTextSupport: true
        )))
    }

    // Commit-on-app-deactivate is now a host-agnostic behaviour in
    // PriTypeInputController (no per-app policy), so there is no longer a
    // bundle-ID predicate to unit-test here.

    @Test("Client compatibility policy flags GoodNotes for direct-newline Return")
    func goodNotesNeedsDirectNewlineAfterReturnCommit() {
        #expect(ClientCompatibilityPolicy.needsDirectNewlineAfterReturnCommit(bundleId: "com.goodnotesapp.x"))
        #expect(!ClientCompatibilityPolicy.needsDirectNewlineAfterReturnCommit(bundleId: "com.openai.codex"))
    }

    @Test("Client compatibility policy consumes Return after Hangul commit for Hermes")
    func hermesConsumesReturnAfterCompositionCommit() {
        #expect(ClientCompatibilityPolicy.needsReturnConsumedAfterCompositionCommit(bundleId: "com.nousresearch.hermes"))
        #expect(ClientCompatibilityPolicy.needsReturnConsumedAfterCompositionCommit(bundleId: "com.nousresearch.hermes.setup"))
        #expect(!ClientCompatibilityPolicy.needsReturnConsumedAfterCompositionCommit(bundleId: "com.openai.codex"))
    }

    @Test("Client compatibility policy prefers direct insertion for Hermes")
    func hermesPrefersDirectInsertionForComposition() {
        #expect(ClientCompatibilityPolicy.prefersDirectInsertionForComposition(bundleId: "com.nousresearch.hermes"))
        #expect(ClientCompatibilityPolicy.prefersDirectInsertionForComposition(bundleId: "com.nousresearch.hermes.setup"))
        #expect(!ClientCompatibilityPolicy.prefersDirectInsertionForComposition(bundleId: "com.openai.codex"))
    }

    @Test("Web content hosts include browsers, Electron, and Atlassian wrappers")
    func webContentHosts() {
        for id in [
            "com.google.Chrome",
            "com.apple.Safari",
            "org.mozilla.firefox",
            "com.anthropic.claudefordesktop",
            "com.atlassian.confluence",
            "com.example.MyElectronApp"
        ] {
            #expect(ClientCompatibilityPolicy.isWebContentHost(bundleId: id), "\(id) should be a web content host")
            #expect(ClientCompatibilityPolicy.prefersRawJamoPreedit(bundleId: id), "\(id) should keep raw jamo")
            #expect(ClientCompatibilityPolicy.prefersCollapsedCompositionReplacement(bundleId: id), "\(id) should start composition without replacing host selection")
        }
    }

    @Test("Native AppKit hosts are not treated as web content")
    func nativeHostsAreNotWebContent() {
        for id in [
            "com.kakao.KakaoTalkMac",
            "com.apple.TextEdit",
            "com.apple.Notes",
            "com.apple.dt.Xcode"
        ] {
            #expect(!ClientCompatibilityPolicy.isWebContentHost(bundleId: id), "\(id) should stay native")
            #expect(!ClientCompatibilityPolicy.prefersRawJamoPreedit(bundleId: id))
            #expect(!ClientCompatibilityPolicy.prefersCollapsedCompositionReplacement(bundleId: id))
        }
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
