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

    @Test("Game compatibility mode does not imply Finder immediate mode")
    func gameCompatibilityDoesNotUseImmediateMode() {
        let gameCtx = ClientContext(
            bundleId: "com.nexon.maplestory.kr.v1",
            hasTextInputCapability: true,
            isLikelyDesktopArea: false,
            usesGameCompatibilityMode: true
        )

        #expect(gameCtx.usesGameCompatibilityMode)
        #expect(!gameCtx.isFinder)
        #expect(!gameCtx.shouldUseImmediateMode)
    }

    @Test("Game compatibility detects known Wine and game runtime markers")
    func gameCompatibilityMarkers() {
        let markerCases: [(bundleId: String, name: String?, bundlePath: String?, executablePath: String?)] = [
            ("com.nexon.maplestory.kr.v1", nil, nil, nil),
            ("com.example.Game", "MapleStory", nil, nil),
            ("com.example.Game", nil, "/Applications/CrossOver.app/Contents/SharedSupport/Bottles/Game.app", nil),
            ("com.example.Game", nil, nil, "/Users/me/Games/Wine/game.exe"),
            ("com.example.Game", nil, "/Applications/Whisky.app/Contents/Resources/game.app", nil)
        ]

        for markerCase in markerCases {
            #expect(ClientContextDetector.usesGameCompatibilityMode(
                bundleId: markerCase.bundleId,
                localizedName: markerCase.name,
                bundlePath: markerCase.bundlePath,
                executablePath: markerCase.executablePath
            ))
        }
    }

    @Test("Game compatibility ignores normal native apps")
    func gameCompatibilityIgnoresNormalApps() {
        #expect(!ClientContextDetector.usesGameCompatibilityMode(
            bundleId: "com.apple.TextEdit",
            localizedName: "TextEdit",
            bundlePath: "/System/Applications/TextEdit.app",
            executablePath: "/System/Applications/TextEdit.app/Contents/MacOS/TextEdit"
        ))

        #expect(!ClientContextDetector.usesGameCompatibilityMode(
            bundleId: "com.google.Chrome",
            localizedName: "Google Chrome",
            bundlePath: "/Applications/Google Chrome.app",
            executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        ))
    }

    @Test("Secure input policy passes through global secure input")
    func secureInputPolicyPassesThroughGlobalSecureInput() {
        #expect(SecureInputPolicy.shouldPassThrough(SecureInputSignals(
            bundleId: "com.kakao.KakaoTalkMac",
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

        #expect(SecureInputPolicy.shouldPassThrough(SecureInputSignals(
            bundleId: "com.kakao.KakaoTalkMac",
            hasTextInputCapability: true,
            hasInvalidSelection: true,
            hasGlobalSecureInput: false,
            hasMarkedTextSupport: true
        )))

        #expect(SecureInputPolicy.shouldPassThrough(SecureInputSignals(
            bundleId: "com.google.Chrome",
            hasTextInputCapability: true,
            hasInvalidSelection: true,
            hasGlobalSecureInput: false,
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
