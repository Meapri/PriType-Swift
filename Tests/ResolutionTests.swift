#!/usr/bin/swift

import Foundation

// Logic under test:
// let isLikelyDesktop = firstRect.origin.x < 50 && firstRect.origin.y < 50

func isFinderDesktop(x: Double, y: Double) -> Bool {
    return x < 50 && y < 50
}

func assert(_ condition: Bool, _ message: String) {
    if condition {
        print("✅ PASS: \(message)")
    } else {
        print("❌ FAIL: \(message)")
        exit(1)
    }
}

print("==== Resolution & Scaling Verification Tests ====")

// 1. Standard Resolution
// Finder Desktop (Fake Window)
assert(isFinderDesktop(x: 5.0, y: 20.0), "Standard: Should detect Desktop at (5, 20)")
// Finder Search Bar (Top Right)
assert(!isFinderDesktop(x: 800.0, y: 600.0), "Standard: Should NOT detect Search Bar at (800, 600)")

// 2. 5K / Retina (Points vs Pixels)
// 5K (5120x2880) scaled to look like 2560x1440. Coordinates are POINTS.
// Scenario 1: Finder Desktop (Logic remains same)
assert(isFinderDesktop(x: 5.0, y: 20.0), "5K: Desktop coords should remain small in Points")

// Scenario 2: Search Bar at top right of 5K screen
// x = 2400 (near right edge), y = 1350 (near top edge)
assert(!isFinderDesktop(x: 2400.0, y: 1350.0), "5K: Search Bar at (2400, 1350) should be active")

// 3. High Scaling (250%)
// 50 points covers more physical screen area, but logical coordinates for standard UI elements scale up too.
// The fake window (internal coord) stays constant.
assert(isFinderDesktop(x: 5.0, y: 5.0), "Scaled: Small coords always desktop")
assert(!isFinderDesktop(x: 100.0, y: 100.0), "Scaled: (100,100) is definitely safe")

// 4. Multi-monitor / Negative Coordinates
// Real text field on secondary monitor at (-1000, 500)
// x = -1000 (< 50) -> True
// y = 500   (< 50) -> False
assert(!isFinderDesktop(x: -1000.0, y: 500.0), "Multi-mon: Search bar on left monitor should be active")

// Real text field on bottom monitor at (500, -1000)
// x = 500   (< 50) -> False
// y = -1000 (< 50) -> True
assert(!isFinderDesktop(x: 500.0, y: -1000.0), "Multi-mon: Search bar on bottom monitor should be active")

print("All tests passed!")
