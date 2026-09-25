import AppKit
import ApplicationServices

/// Keyboard focus can belong to a nonactivating panel (for example Spotlight)
/// while NSWorkspace still reports the app underneath it as frontmost.
enum ToggleAppFocus {
    static func isExcluded(bundleIDs: [String]) -> Bool {
        guard !bundleIDs.isEmpty else { return false }
        return isExcluded(
            bundleIDs: bundleIDs,
            frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            focusedBundleID: focusedBundleID()
        )
    }

    static func isExcluded(
        bundleIDs: [String],
        frontmostBundleID: String?,
        focusedBundleID: String?
    ) -> Bool {
        guard let target = focusedBundleID ?? frontmostBundleID else { return false }
        return bundleIDs.contains(target)
    }

    private static func focusedBundleID() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        // Called on the main run loop by both key monitors and the coordinator.
        // Bound IPC so an unresponsive app cannot stall the event tap. A timeout
        // on the system-wide element is process-wide; restore the default when
        // finished so unrelated AX caret queries retain their usual timeout.
        AXUIElementSetMessagingTimeout(systemWide, 0.02)
        defer { AXUIElementSetMessagingTimeout(systemWide, 0) }

        // The element owner is more precise than the frontmost application for
        // panels that take keyboard focus without activating their application.
        // If an app does not expose its element, try the focused application.
        for attribute in [kAXFocusedUIElementAttribute, kAXFocusedApplicationAttribute] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(systemWide, attribute as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { continue }
            let element = value as! AXUIElement
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success, pid > 0,
                  let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { continue }
            return bundleID
        }
        // Preserve exclusions if accessibility is unavailable or times out.
        return nil
    }
}
