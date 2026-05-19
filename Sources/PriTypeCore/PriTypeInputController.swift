import Cocoa
import InputMethodKit
import LibHangul
import Carbon.HIToolbox

@objc(PriTypeInputController)
public class PriTypeInputController: IMKInputController, @unchecked Sendable {
    private static let priTypeInputSourceID = "com.pritype.inputmethod.v2"
    private static let priTypeKoreanInputModeID = "com.pritype.inputmethod.v2.korean"
    private static let priTypeEnglishInputModeID = "com.pritype.inputmethod.v2.english"
    private static let romanKeyboardLayoutID = "com.apple.keylayout.US"
    nonisolated(unsafe) public static var lastInputModePropertyUpdateTime: CFAbsoluteTime = 0
    
    // MARK: - Shared State
    //
    // THREAD SAFETY INVARIANTS:
    // These static properties use `nonisolated(unsafe)` for Swift 6 strict concurrency compliance.
    //
    // WHY NOT @MainActor?
    // IMKInputController callbacks (handle, activateServer, etc.) are NOT @MainActor-isolated.
    // Swift 6 compiler would reject @MainActor property access from these callbacks.
    //
    // IMK guarantees main thread execution by design:
    // 1. `sharedComposer`: Created once at startup, accessed only via IMK callbacks
    // 2. `sharedController`: Read/written only in activateServer/deactivateServer
    //
    // This is a documented limitation of integrating Swift 6 strict concurrency with
    // legacy Objective-C frameworks like InputMethodKit.
    
    /// Shared composer instance for toggle key handler access
    /// - Warning: Access from main thread only (guaranteed by IMK, not compiler-enforced)
    public static let sharedComposer = HangulComposer()
    private var composer: HangulComposer { Self.sharedComposer }
    
    /// Last active controller reference for external toggle access
    /// - Warning: Access from main thread only (guaranteed by IMK, not compiler-enforced)
    nonisolated(unsafe) public static weak var sharedController: PriTypeInputController?
    nonisolated(unsafe) private static var activationSerial: UInt64 = 0
    nonisolated(unsafe) private static var forcedMarkedTextBundleIDs: Set<String> = []
    nonisolated(unsafe) private static var directCompositionBundleIDs: Set<String> = []
    // Strong reference to prevent client being released during rapid switching
    private var lastClient: IMKTextInput?
    private var lastKnownInputClient: IMKTextInput?
    private var pendingMarkedReplacementRanges: [ObjectIdentifier: NSRange] = [:]

    #if DEBUG
    private var debugHandleLogCount = 0
    private var debugHandleSnapshotCount = 0
    #endif
    private var lastKeyboardOverrideClientID: ObjectIdentifier?
    private var lastKeyboardOverrideTime: CFAbsoluteTime = 0
    private var lastMarkedKeystrokeBundleId = ""
    private var lastBackspaceCompositionEndTime: CFAbsoluteTime = 0
    private let backspaceRepeatSuppressionInterval: CFAbsoluteTime = 0.02
    
    // Keep adapter alive for external toggle calls
    public private(set) var currentAdapter: (any HangulComposerDelegate)?
    
    // MARK: - Adapter Classes
    
    /// Base adapter class with common IMKTextInput operations
    /// Subclasses override setMarkedText for different behaviors
    class BaseClientAdapter: NSObject, HangulComposerDelegate {
        let client: IMKTextInput
        
        init(client: IMKTextInput) {
            self.client = client
        }

        #if DEBUG
        private func formatRange(_ range: NSRange) -> String {
            if range.location == NSNotFound {
                return "NSNotFound,len=\(range.length)"
            }
            return "loc=\(range.location),len=\(range.length)"
        }

        func debugClientSnapshot(_ label: String) {
            let object = client as AnyObject
            let selected = client.selectedRange()
            let marked = client.markedRange()
            DebugLogger.log("ClientAdapter[\(label)]: class=\(type(of: client)) object=\(ObjectIdentifier(object)) selected={\(formatRange(selected))} marked={\(formatRange(marked))}")
        }
        #endif
        
        static func insertionReplacementRange(markedRange: NSRange) -> NSRange {
            if markedRange.location != NSNotFound,
               markedRange.length > 0 {
                return markedRange
            }
            return NSRange(location: NSNotFound, length: NSNotFound)
        }

        static func insertionReplacementRange(selectedRange: NSRange, markedRange: NSRange) -> NSRange {
            insertionReplacementRange(markedRange: markedRange)
        }

        static func markedTextClearingReplacementRange(markedRange: NSRange) -> NSRange? {
            guard markedRange.location != NSNotFound, markedRange.length > 0 else {
                return nil
            }
            return markedRange
        }

        static func isUsableInsertionSelection(_ range: NSRange) -> Bool {
            range.location != NSNotFound && range.location < 10_000_000 && range.length == 0
        }

        static func hasNoHostMarkedRange(_ range: NSRange) -> Bool {
            range.location == NSNotFound
        }

        static func hasHostMarkedSession(_ range: NSRange) -> Bool {
            range.location != NSNotFound
        }

        static func hasHostMarkedRange(_ range: NSRange) -> Bool {
            range.location != NSNotFound && range.length > 0
        }

        static func directCompositionReplacementRange(compositionRange: NSRange, selectedRange: NSRange) -> NSRange {
            if compositionRange.location != NSNotFound {
                return compositionRange
            }
            if isUsableInsertionSelection(selectedRange) {
                return NSRange(location: selectedRange.location, length: 0)
            }
            return NSRange(location: NSNotFound, length: NSNotFound)
        }

        @discardableResult
        func clearClientMarkedTextIfNeeded(reason: String) -> Bool {
            let markedRange = client.markedRange()
            guard let replacementRange = Self.markedTextClearingReplacementRange(markedRange: markedRange) else {
                DebugLogger.log("ClientAdapter.clearMarked skipped reason=\(reason); no non-empty marked range")
                return false
            }

            DebugLogger.log("ClientAdapter.clearMarked reason=\(reason) loc=\(replacementRange.location) len=\(replacementRange.length)")
            let attributed = NSAttributedString(string: "", attributes: [:])
            client.setMarkedText(
                attributed,
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: replacementRange
            )
            #if DEBUG
            debugClientSnapshot("clearMarked.after reason=\(reason)")
            #endif
            return true
        }

        @discardableResult
        func finishMarkedText(reason: String) -> Bool {
            DebugLogger.log("ClientAdapter.finishMarkedText reason=\(reason)")
            #if DEBUG
            debugClientSnapshot("finishMarkedText.before reason=\(reason)")
            #endif
            unmarkClientText(reason: reason)
            #if DEBUG
            debugClientSnapshot("finishMarkedText.after reason=\(reason)")
            #endif
            return true
        }

        func finishMarkedTextAfterDirectCommit(reason: String) {
            DebugLogger.log("ClientAdapter.finishMarkedTextAfterDirectCommit reason=\(reason)")
            #if DEBUG
            debugClientSnapshot("finishAfterDirectCommit.before reason=\(reason)")
            #endif
            unmarkClientText(reason: reason)
            #if DEBUG
            debugClientSnapshot("finishAfterDirectCommit.after reason=\(reason)")
            #endif
        }

        func unmarkClientText(reason: String) {
            let object = client as AnyObject
            let selector = NSSelectorFromString("unmarkText")
            guard object.responds(to: selector) else {
                DebugLogger.log("ClientAdapter.unmarkText unavailable reason=\(reason)")
                return
            }
            DebugLogger.log("ClientAdapter.unmarkText reason=\(reason)")
            _ = object.perform(selector)
        }

        func insertText(_ text: String) {
            guard !text.isEmpty else { return }
            #if DEBUG
            debugClientSnapshot("insertText.before len=\(text.utf16.count)")
            #endif
            let replacementRange = Self.insertionReplacementRange(
                markedRange: client.markedRange()
            )
            if replacementRange.location != NSNotFound {
                DebugLogger.log("ClientAdapter.insertText using marked replacement range loc=\(replacementRange.location) len=\(replacementRange.length)")
            }
            client.insertText(text, replacementRange: replacementRange)
            #if DEBUG
            debugClientSnapshot("insertText.after len=\(text.utf16.count)")
            #endif
        }
        
        func setMarkedText(_ text: String) {
            // Default: no-op, subclasses override
        }
        
        func textBeforeCursor(length: Int) -> String? {
            let selRange = client.selectedRange()
            guard selRange.location != NSNotFound, selRange.location < 10000000 else { return nil } // Protect against Chromium garbage values
            
            let location = max(0, selRange.location - length)
            let actualLength = selRange.location - location
            guard actualLength > 0 else { return nil }
            
            let charRange = NSRange(location: location, length: actualLength)
            return client.attributedSubstring(from: charRange)?.string
        }
        
        func replaceTextBeforeCursor(length: Int, with text: String) {
            let selRange = client.selectedRange()
            guard selRange.location != NSNotFound, selRange.location < 10000000, selRange.location >= length else { return }
            
            let replacementRange = NSRange(location: selRange.location - length, length: length)
            client.insertText(text, replacementRange: replacementRange)
        }
    }
    
    /// Standard IMK marked-text adapter.
    class ClientAdapter: BaseClientAdapter {
        private var initialReplacementRange: NSRange?

        init(client: IMKTextInput, initialReplacementRange: NSRange? = nil) {
            self.initialReplacementRange = initialReplacementRange
            super.init(client: client)
        }

        private func takeInitialReplacementRange() -> NSRange {
            defer { initialReplacementRange = nil }
            return initialReplacementRange ?? NSRange(location: NSNotFound, length: NSNotFound)
        }

        override func setMarkedText(_ text: String) {
            #if DEBUG
            debugClientSnapshot("setMarkedText.before len=\(text.utf16.count)")
            #endif
            guard !text.isEmpty else {
                let replacementRange = takeInitialReplacementRange()
                let attributed = NSAttributedString(string: "", attributes: [:])
                if replacementRange.location != NSNotFound {
                    client.setMarkedText(
                        attributed,
                        selectionRange: NSRange(location: 0, length: 0),
                        replacementRange: replacementRange
                    )
                    DebugLogger.log("ClientAdapter.setMarkedText cleared initial replacement range loc=\(replacementRange.location) len=\(replacementRange.length)")
                } else {
                    client.setMarkedText(
                        attributed,
                        selectionRange: NSRange(location: 0, length: 0),
                        replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
                    )
                    DebugLogger.log("ClientAdapter.setMarkedText cleared empty text without range query")
                }
                #if DEBUG
                debugClientSnapshot("setMarkedText.after len=0")
                #endif
                return
            }
            let attributed = NSAttributedString(
                string: text,
                attributes: [:]
            )
            let replacementRange = takeInitialReplacementRange()
            if replacementRange.location != NSNotFound {
                DebugLogger.log("ClientAdapter.setMarkedText using initial replacement range loc=\(replacementRange.location) len=\(replacementRange.length)")
            }
            client.setMarkedText(
                attributed,
                selectionRange: NSRange(location: text.utf16.count, length: 0),
                replacementRange: replacementRange
            )
            #if DEBUG
            debugClientSnapshot("setMarkedText.after len=\(text.utf16.count)")
            #endif
        }
    }

    /// Immediate mode adapter for non-text contexts (e.g., Finder desktop)
    /// Skips setMarkedText to prevent floating composition window
    final class ImmediateModeAdapter: BaseClientAdapter {
        // Inherits no-op setMarkedText from base class
        override func finishMarkedText(reason: String) -> Bool {
            DebugLogger.log("ImmediateModeAdapter.finishMarkedText skipped reason=\(reason)")
            return false
        }
    }

    /// Direct composition adapter for clients that do not reliably render or clear
    /// IMK marked text attributes but do support normal replacement ranges.
    final class DirectCompositionAdapter: BaseClientAdapter, DirectCompositionDelegate {
        private var directCompositionRange = NSRange(location: NSNotFound, length: 0)
        private var shouldPassThroughBackspaceAfterFailedClear = false
        private var unchangedCursorCount = 0
        private let bundleId: String
        private let forceMarkedText: (String, NSRange?) -> Void

        init(
            client: IMKTextInput,
            bundleId: String,
            forceMarkedText: @escaping (String, NSRange?) -> Void
        ) {
            self.bundleId = bundleId
            self.forceMarkedText = forceMarkedText
            super.init(client: client)
        }

        private func setHostMarkedText(_ text: String) {
            let attributed = NSAttributedString(string: text, attributes: [:])
            client.setMarkedText(
                attributed,
                selectionRange: NSRange(location: text.utf16.count, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
            )
        }

        private func validateCursorAfterDirectInsert(
            startLocation: Int,
            insertedLength: Int,
            reason: String
        ) {
            guard startLocation != NSNotFound else { return }
            guard insertedLength > 0 else { return }
            let expectedLocation = startLocation + insertedLength
            let selectedRange = client.selectedRange()
            guard selectedRange.location != NSNotFound else {
                DebugLogger.log("DirectCompositionAdapter: cursor unavailable bundle=\(bundleId) reason=\(reason) expected=\(expectedLocation) selected=\(selectedRange)")
                return
            }
            guard selectedRange.location != startLocation || selectedRange.length != 0 else {
                unchangedCursorCount += 1
                DebugLogger.log("DirectCompositionAdapter: cursor unchanged after direct insert bundle=\(bundleId) reason=\(reason) start=\(startLocation) expected=\(expectedLocation) count=\(unchangedCursorCount)")
                if unchangedCursorCount >= 2 {
                    forceMarkedText(reason, directCompositionRange)
                }
                return
            }
            unchangedCursorCount = 0
            guard selectedRange.location == expectedLocation, selectedRange.length == 0 else {
                DebugLogger.log("DirectCompositionAdapter: cursor mismatch bundle=\(bundleId) reason=\(reason) expected=\(expectedLocation) selected=\(selectedRange)")
                forceMarkedText(reason, directCompositionRange)
                return
            }
        }

        func consumeBackspacePassThroughAfterFailedDirectClear() -> Bool {
            defer { shouldPassThroughBackspaceAfterFailedClear = false }
            return shouldPassThroughBackspaceAfterFailedClear
        }

        func updateDirectComposition(commit: String, preedit: String) {
            #if DEBUG
            debugClientSnapshot("direct.update.before commitLen=\(commit.utf16.count) preeditLen=\(preedit.utf16.count)")
            #endif
            let replacement = commit + preedit
            if replacement.isEmpty {
                shouldPassThroughBackspaceAfterFailedClear = false
            }
            let replacementRange = Self.directCompositionReplacementRange(
                compositionRange: directCompositionRange,
                selectedRange: client.selectedRange()
            )
            let isClearingDirectPreedit = replacement.isEmpty
                && replacementRange.location != NSNotFound
            guard !replacement.isEmpty || replacementRange.location != NSNotFound else {
                directCompositionRange = NSRange(location: NSNotFound, length: 0)
                return
            }
            guard replacementRange.location != NSNotFound else {
                forceMarkedText("direct update invalid selection", nil)
                if !commit.isEmpty {
                    client.insertText(commit, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                }
                if !preedit.isEmpty {
                    setHostMarkedText(preedit)
                }
                directCompositionRange = NSRange(location: NSNotFound, length: 0)
                return
            }

            let startLocation = replacementRange.location
            client.insertText(replacement, replacementRange: replacementRange)
            let selectedRange = client.selectedRange()
            if isClearingDirectPreedit,
               selectedRange.location != NSNotFound,
               (selectedRange.location != startLocation || selectedRange.length != 0) {
                shouldPassThroughBackspaceAfterFailedClear = true
                DebugLogger.log("DirectCompositionAdapter: direct clear did not move cursor; will pass through Backspace bundle=\(bundleId) expected=\(startLocation) selected=\(selectedRange)")
            }
            if Self.isUsableInsertionSelection(selectedRange),
               selectedRange.location == startLocation + replacement.utf16.count,
               !preedit.isEmpty {
                directCompositionRange = NSRange(
                    location: max(0, selectedRange.location - preedit.utf16.count),
                    length: preedit.utf16.count
                )
            } else if startLocation != NSNotFound, !preedit.isEmpty {
                directCompositionRange = NSRange(
                    location: startLocation + commit.utf16.count,
                    length: preedit.utf16.count
                )
            } else {
                directCompositionRange = NSRange(location: NSNotFound, length: 0)
            }
            validateCursorAfterDirectInsert(
                startLocation: startLocation,
                insertedLength: replacement.utf16.count,
                reason: "direct update"
            )
            #if DEBUG
            debugClientSnapshot("direct.update.after commitLen=\(commit.utf16.count) preeditLen=\(preedit.utf16.count)")
            #endif
        }

        func commitDirectComposition(_ text: String) {
            guard !text.isEmpty else {
                directCompositionRange = NSRange(location: NSNotFound, length: 0)
                return
            }
            #if DEBUG
            debugClientSnapshot("direct.commit.before len=\(text.utf16.count)")
            #endif
            let replacementRange = Self.directCompositionReplacementRange(
                compositionRange: directCompositionRange,
                selectedRange: client.selectedRange()
            )
            let startLocation = replacementRange.location
            guard startLocation != NSNotFound else {
                client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                directCompositionRange = NSRange(location: NSNotFound, length: 0)
                forceMarkedText("direct commit invalid selection", nil)
                return
            }
            client.insertText(text, replacementRange: replacementRange)
            directCompositionRange = NSRange(location: NSNotFound, length: 0)
            validateCursorAfterDirectInsert(
                startLocation: startLocation,
                insertedLength: text.utf16.count,
                reason: "direct commit"
            )
            #if DEBUG
            debugClientSnapshot("direct.commit.after len=\(text.utf16.count)")
            #endif
        }

        func clearDirectComposition() {
            updateDirectComposition(commit: "", preedit: "")
        }

        override func finishMarkedText(reason: String) -> Bool {
            clearDirectComposition()
            return super.finishMarkedText(reason: reason)
        }

        override func insertText(_ text: String) {
            guard !text.isEmpty else { return }
            #if DEBUG
            debugClientSnapshot("direct.insertText.before len=\(text.utf16.count)")
            #endif
            let replacementRange = Self.directCompositionReplacementRange(
                compositionRange: directCompositionRange,
                selectedRange: client.selectedRange()
            )
            let startLocation = replacementRange.location
            guard startLocation != NSNotFound else {
                client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                directCompositionRange = NSRange(location: NSNotFound, length: 0)
                forceMarkedText("direct insert invalid selection", nil)
                return
            }
            client.insertText(text, replacementRange: replacementRange)
            directCompositionRange = NSRange(location: NSNotFound, length: 0)
            validateCursorAfterDirectInsert(
                startLocation: startLocation,
                insertedLength: text.utf16.count,
                reason: "direct insert"
            )
            #if DEBUG
            debugClientSnapshot("direct.insertText.after len=\(text.utf16.count)")
            #endif
        }

        override func setMarkedText(_ text: String) {
            #if DEBUG
            debugClientSnapshot("direct.setMarkedText.before len=\(text.utf16.count)")
            #endif
            let replacementRange = Self.directCompositionReplacementRange(
                compositionRange: directCompositionRange,
                selectedRange: client.selectedRange()
            )
            guard !text.isEmpty else {
                shouldPassThroughBackspaceAfterFailedClear = false
                if replacementRange.location != NSNotFound {
                    let startLocation = replacementRange.location
                    client.insertText("", replacementRange: replacementRange)
                    let selectedRange = client.selectedRange()
                    if selectedRange.location != NSNotFound,
                       (selectedRange.location != startLocation || selectedRange.length != 0) {
                        shouldPassThroughBackspaceAfterFailedClear = true
                        DebugLogger.log("DirectCompositionAdapter: direct clear preedit failed; will pass through Backspace bundle=\(bundleId) expected=\(startLocation) selected=\(selectedRange)")
                    }
                    validateCursorAfterDirectInsert(
                        startLocation: startLocation,
                        insertedLength: 0,
                        reason: "direct clear"
                    )
                }
                directCompositionRange = NSRange(location: NSNotFound, length: 0)
                #if DEBUG
                debugClientSnapshot("direct.setMarkedText.after len=0")
                #endif
                return
            }

            let startLocation = replacementRange.location
            guard startLocation != NSNotFound else {
                forceMarkedText("direct preedit invalid selection", nil)
                setHostMarkedText(text)
                directCompositionRange = NSRange(location: NSNotFound, length: 0)
                #if DEBUG
                debugClientSnapshot("direct.setMarkedText.fallback len=\(text.utf16.count)")
                #endif
                return
            }
            client.insertText(text, replacementRange: replacementRange)
            if startLocation != NSNotFound {
                directCompositionRange = NSRange(location: startLocation, length: text.utf16.count)
            } else {
                directCompositionRange = NSRange(location: NSNotFound, length: 0)
            }
            validateCursorAfterDirectInsert(
                startLocation: startLocation,
                insertedLength: text.utf16.count,
                reason: "direct preedit"
            )
            #if DEBUG
            debugClientSnapshot("direct.setMarkedText.after len=\(text.utf16.count)")
            #endif
        }
    }

    // MARK: - State Management
    
    /// Cached client context to avoid expensive IPC calls on every keystroke
    /// - Note: Calculated in `activateServer`, used in `handle`, cleared in `deactivateServer`
    private(set) var cachedContext: ClientContext?

    private func makeAdapter(for client: IMKTextInput, context: ClientContext) -> any HangulComposerDelegate {
        if context.shouldUseImmediateMode {
            return ImmediateModeAdapter(client: client)
        }
        if shouldUseDirectComposition(context: context) {
            return DirectCompositionAdapter(
                client: client,
                bundleId: context.bundleId,
                forceMarkedText: { [weak self, weak client] reason, replacementRange in
                    guard let client else { return }
                    self?.forceMarkedText(
                        for: context.bundleId,
                        client: client,
                        reason: reason,
                        replacementRange: replacementRange
                    )
                }
            )
        }
        return ClientAdapter(
            client: client,
            initialReplacementRange: takePendingMarkedReplacementRange(for: client)
        )
    }

    private func shouldUseDirectComposition(context: ClientContext) -> Bool {
        return Self.directCompositionBundleIDs.contains(context.bundleId) &&
            !Self.forcedMarkedTextBundleIDs.contains(context.bundleId)
    }

    private func takePendingMarkedReplacementRange(for client: IMKTextInput) -> NSRange? {
        pendingMarkedReplacementRanges.removeValue(forKey: ObjectIdentifier(client as AnyObject))
    }

    private func rememberPendingMarkedReplacementRange(_ range: NSRange, for client: IMKTextInput) {
        guard range.location != NSNotFound, range.length > 0 else { return }
        pendingMarkedReplacementRanges[ObjectIdentifier(client as AnyObject)] = range
    }

    private func forceMarkedText(
        for bundleId: String,
        client: IMKTextInput,
        reason: String,
        replacementRange: NSRange?
    ) {
        guard !bundleId.isEmpty else { return }
        Self.forcedMarkedTextBundleIDs.insert(bundleId)
        if let replacementRange,
           replacementRange.location != NSNotFound,
           replacementRange.length > 0 {
            rememberPendingMarkedReplacementRange(replacementRange, for: client)
            DebugLogger.log("PriTypeInputController: forcing marked text for bundle=\(bundleId) reason=\(reason) replacementRange={loc=\(replacementRange.location),len=\(replacementRange.length)}")
        } else {
            DebugLogger.log("PriTypeInputController: forcing marked text for bundle=\(bundleId) reason=\(reason)")
        }
    }

    private func forceDirectComposition(for bundleId: String, reason: String) {
        guard !bundleId.isEmpty, !Self.forcedMarkedTextBundleIDs.contains(bundleId) else { return }
        let inserted = Self.directCompositionBundleIDs.insert(bundleId).inserted
        DebugLogger.log("PriTypeInputController: forcing direct composition for bundle=\(bundleId) reason=\(reason) inserted=\(inserted)")
    }

    private func installAdapter(for client: IMKTextInput, context: ClientContext) {
        currentAdapter = makeAdapter(for: client, context: context)
        DebugLogger.log("PriTypeInputController: installed adapter=\(type(of: currentAdapter!)) bundle=\(context.bundleId) lightweight=\(context.isLightweight)")
    }

    private func adapterMatchesContext(_ adapter: (any HangulComposerDelegate)?, context: ClientContext) -> Bool {
        if context.shouldUseImmediateMode {
            return adapter is ImmediateModeAdapter
        }
        guard adapter is BaseClientAdapter else {
            return false
        }
        if shouldUseDirectComposition(context: context) {
            return adapter is DirectCompositionAdapter
        }
        return adapter is ClientAdapter
    }

    private func commitBeforeClientSwitch(to client: IMKTextInput, context: ClientContext) {
        guard lastClient != nil, lastClient !== client, composer.hasActiveComposition else {
            return
        }

        if let adapter = currentAdapter {
            DebugLogger.log("PriTypeInputController: committing composition before client switch bundle=\(context.bundleId)")
            composer.forceCommit(delegate: adapter)
            (adapter as? BaseClientAdapter)?.finishMarkedText(reason: "clientSwitch")
            composer.clearLocalBuffer()
        } else if let previousClient = lastClient {
            DebugLogger.log("PriTypeInputController: committing composition before client switch with temp adapter bundle=\(context.bundleId)")
            let adapter = ClientAdapter(client: previousClient)
            composer.forceCommit(delegate: adapter)
            adapter.finishMarkedText(reason: "clientSwitch.temp")
            composer.clearLocalBuffer()
        }
    }

    private func finalizeEndedCompositionIfNeeded(
        client: IMKTextInput,
        adapter: (any HangulComposerDelegate)?,
        reason: String
    ) {
        guard let baseAdapter = adapter as? BaseClientAdapter else {
            return
        }

        let markedRange = client.markedRange()
        guard BaseClientAdapter.hasHostMarkedRange(markedRange) else {
            return
        }

        DebugLogger.log("PriTypeInputController: finalize ended composition reason=\(reason) marked=\(markedRange)")
        baseAdapter.finishMarkedText(reason: "finalizeEndedComposition.\(reason)")
        super.commitComposition(client)
        #if DEBUG
        baseAdapter.debugClientSnapshot("finalizeEndedComposition.after \(reason)")
        #endif
    }

    private func syncRomanKeyboardLayout(
        for client: IMKTextInput,
        context: ClientContext? = nil,
        force: Bool = false
    ) {
        guard composer.inputMode == .korean else {
            DebugLogger.log("PriTypeInputController: keyboard override skipped mode=\(composer.inputMode)")
            return
        }
        if let context, context.shouldUseImmediateMode || !context.hasTextInputCapability {
            DebugLogger.log("PriTypeInputController: keyboard override skipped non-text context bundle=\(context.bundleId) immediate=\(context.shouldUseImmediateMode) text=\(context.hasTextInputCapability)")
            return
        }

        let clientID = ObjectIdentifier(client as AnyObject)
        let now = CFAbsoluteTimeGetCurrent()
        guard force || lastKeyboardOverrideClientID != clientID || now - lastKeyboardOverrideTime > 0.5 else {
            DebugLogger.log("PriTypeInputController: keyboard override skipped by throttle client=\(clientID)")
            return
        }

        let selector = NSSelectorFromString("overrideKeyboardWithKeyboardNamed:")
        let object = client as AnyObject
        guard object.responds(to: selector) else {
            DebugLogger.log("PriTypeInputController: client does not support keyboard override")
            return
        }

        _ = object.perform(selector, with: Self.romanKeyboardLayoutID)
        lastKeyboardOverrideClientID = clientID
        lastKeyboardOverrideTime = now
        DebugLogger.log("PriTypeInputController: override keyboard layout -> \(Self.romanKeyboardLayoutID)")
    }

    public func selectInputModeForCurrentClient(_ mode: InputMode) {
        let inputModeID: String
        switch mode {
        case .korean:
            inputModeID = Self.priTypeKoreanInputModeID
        case .english:
            inputModeID = "com.apple.keylayout.ABC"
        }

        guard let client = lastClient ?? lastKnownInputClient else {
            DebugLogger.log("PriTypeInputController: no current client for selectInputMode(\(inputModeID))")
            return
        }

        let selector = NSSelectorFromString("selectInputMode:")
        let object = client as AnyObject
        guard object.responds(to: selector) else {
            DebugLogger.log("PriTypeInputController: client does not support selectInputMode:")
            return
        }

        _ = object.perform(selector, with: inputModeID)
        DebugLogger.log("PriTypeInputController: client selectInputMode -> \(inputModeID)")

        if mode == .korean {
            syncRomanKeyboardLayout(for: client, context: cachedContext, force: true)
        }
    }
    
    // 입력기가 활성화될 때 호출 - 새 세션 시작
    override public func activateServer(_ sender: Any!) {
        #if DEBUG
        assert(Thread.isMainThread, "IMK activateServer must run on main thread")
        #endif
        Self.activationSerial &+= 1
        let activationToken = Self.activationSerial
        super.activateServer(sender)

        guard activationToken == Self.activationSerial else {
            DebugLogger.log("PriTypeInputController: ignored stale activateServer before setup token=\(activationToken) current=\(Self.activationSerial)")
            return
        }

        // 클라이언트 저장
        if let client = sender as? IMKTextInput {
            DebugLogger.log("PriTypeInputController: activateServer sender client object=\(ObjectIdentifier(client as AnyObject)) class=\(type(of: client)) bundle=\(client.bundleIdentifier() ?? "unknown")")
            
            // PERFORMANCE: Analyze context ONCE per session and cache it.
            // This avoids heavy IPC calls (bundleId check, coordinate calculation) on every keystroke.
            let context = ClientContextDetector.analyzeForActivation(client: client)

            guard activationToken == Self.activationSerial else {
                DebugLogger.log("PriTypeInputController: ignored stale activateServer after analyze token=\(activationToken) current=\(Self.activationSerial)")
                return
            }

            commitBeforeClientSwitch(to: client, context: context)
            lastClient = client
            lastKnownInputClient = client
            self.cachedContext = context
            installAdapter(for: client, context: context)
            #if DEBUG
            (currentAdapter as? BaseClientAdapter)?.debugClientSnapshot("activateServer.after-adapter")
            #endif

            DebugLogger.log("Activated for client: \(self.cachedContext?.bundleId ?? "unknown") (Lightweight Context)")

            let clientID = ObjectIdentifier(client as AnyObject)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard activationToken == Self.activationSerial,
                      let currentClient = self.lastClient,
                      ObjectIdentifier(currentClient as AnyObject) == clientID else {
                    DebugLogger.log("PriTypeInputController: ignored stale keyboard override token=\(activationToken) current=\(Self.activationSerial)")
                    return
                }
                self.syncRomanKeyboardLayout(for: currentClient, context: self.cachedContext)
            }
        } else {
            // Fallback if sender is not IMKTextInput (rare)
            self.cachedContext = nil
            DebugLogger.log("PriTypeInputController: activateServer without IMKTextInput sender=\(String(describing: sender))")
        }
        
        // Set as active controller for toggle access
        Self.sharedController = self
        
        // Ensure composer has correct layout (in case it changed while inactive)
        let currentLayoutId = ConfigurationManager.shared.keyboardId
        composer.updateKeyboardLayout(id: currentLayoutId)
        
        // Observe layout changes
        NotificationCenter.default.removeObserver(self, name: .keyboardLayoutChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLayoutChange), name: .keyboardLayoutChanged, object: nil)
    }
    
    override public func deactivateServer(_ sender: Any!) {
        #if DEBUG
        assert(Thread.isMainThread, "IMK deactivateServer must run on main thread")
        #endif
        let deactivatingClient = (sender as? IMKTextInput)
            ?? (currentAdapter as? BaseClientAdapter)?.client
            ?? lastClient
        let deactivatingClientID = deactivatingClient.map { ObjectIdentifier($0 as AnyObject) }
        // 반드시 조합 중인 내용을 커밋
        // Use the existing currentAdapter if available (not a stale temp adapter)
        if let adapter = currentAdapter {
            let hadComposition = composer.hasActiveComposition
            let baseAdapter = adapter as? BaseClientAdapter
            let markedRange = baseAdapter?.client.markedRange() ?? NSRange(location: NSNotFound, length: NSNotFound)
            guard hadComposition || BaseClientAdapter.hasHostMarkedRange(markedRange) else {
                DebugLogger.log("PriTypeInputController: deactivateServer no-op active=false marked=\(markedRange) sender=\(String(describing: type(of: sender)))")
                baseAdapter?.finishMarkedText(reason: "deactivateServer.no-op")
                super.deactivateServer(sender)
                if let deactivatingClientID {
                    pendingMarkedReplacementRanges.removeValue(forKey: deactivatingClientID)
                    let currentClientID = lastClient.map { ObjectIdentifier($0 as AnyObject) }
                    if currentClientID == deactivatingClientID {
                        lastClient = nil
                    } else {
                        DebugLogger.log("PriTypeInputController: deactivateServer preserved newer lastClient current=\(String(describing: currentClientID)) deactivating=\(deactivatingClientID)")
                    }
                } else {
                    lastClient = nil
                }
                NotificationCenter.default.removeObserver(self, name: .keyboardLayoutChanged, object: nil)
                return
            }
            DebugLogger.log("PriTypeInputController: deactivateServer forceCommit currentAdapter active=\(hadComposition) sender=\(String(describing: type(of: sender)))")
            #if DEBUG
            (adapter as? BaseClientAdapter)?.debugClientSnapshot("deactivateServer.before-currentAdapter")
            #endif
            if hadComposition,
               let baseAdapter,
               baseAdapter.client.selectedRange().location == NSNotFound,
               BaseClientAdapter.hasHostMarkedRange(baseAdapter.client.markedRange()) {
                let bundleId = cachedContext?.bundleId ?? baseAdapter.client.bundleIdentifier() ?? ""
                forceDirectComposition(for: bundleId, reason: "invalid-selection-live-marked-on-deactivate")
            }
            composer.forceCommit(delegate: adapter)
            if hadComposition {
                (adapter as? BaseClientAdapter)?.finishMarkedTextAfterDirectCommit(reason: "deactivateServer")
            }
            let didFinishMarkedText = (adapter as? BaseClientAdapter)?.finishMarkedText(reason: "deactivateServer") ?? false
            if hadComposition, !didFinishMarkedText {
                DebugLogger.log("PriTypeInputController: deactivateServer skipped unsafe marked finalize after direct commit")
            }
            if hadComposition {
                DebugLogger.log("PriTypeInputController: deactivateServer notifying IMK commit after direct commit")
                super.commitComposition(sender)
                composer.clearLocalBuffer()
                DebugLogger.log("PriTypeInputController: deactivateServer committed active composition")
            }
            #if DEBUG
            (adapter as? BaseClientAdapter)?.debugClientSnapshot("deactivateServer.after-currentAdapter")
            #endif
        } else if let client = sender as? IMKTextInput ?? lastClient {
            let adapter = ClientAdapter(client: client)
            let hadComposition = composer.hasActiveComposition
            DebugLogger.log("PriTypeInputController: deactivateServer forceCommit tempAdapter active=\(hadComposition) client=\(ObjectIdentifier(client as AnyObject)) sender=\(String(describing: type(of: sender)))")
            #if DEBUG
            adapter.debugClientSnapshot("deactivateServer.before-tempAdapter")
            #endif
            composer.forceCommit(delegate: adapter)
            if hadComposition {
                adapter.finishMarkedTextAfterDirectCommit(reason: "deactivateServer.temp")
                let didFinishMarkedText = adapter.finishMarkedText(reason: "deactivateServer.temp")
                if !didFinishMarkedText {
                    DebugLogger.log("PriTypeInputController: deactivateServer temp delegating unsafe marked finalize to IMK")
                    super.commitComposition(sender)
                }
                DebugLogger.log("PriTypeInputController: deactivateServer temp notifying IMK commit after direct commit")
                super.commitComposition(sender)
                composer.clearLocalBuffer()
                DebugLogger.log("PriTypeInputController: deactivateServer committed active composition with temp adapter")
            }
            #if DEBUG
            adapter.debugClientSnapshot("deactivateServer.after-tempAdapter")
            #endif
        } else {
            DebugLogger.log("PriTypeInputController: deactivateServer no adapter/client active=\(composer.hasActiveComposition) sender=\(String(describing: type(of: sender)))")
        }

        // NOTE: Do NOT clear localTextBuffer here.
        // Cross-app hanja leaking is prevented by bundleId matching in handleHanjaLookup(),
        // not by clearing the buffer. Clearing would make same-app hanja lookup impossible.
        super.deactivateServer(sender)
        // Do NOT clear currentAdapter here.
        // CGEventTap triggerHanjaLookup() is dispatched async and needs a valid adapter.
        // The next activateServer() will replace it with the new client's adapter.
        if let deactivatingClientID {
            pendingMarkedReplacementRanges.removeValue(forKey: deactivatingClientID)
            let currentClientID = lastClient.map { ObjectIdentifier($0 as AnyObject) }
            if currentClientID == deactivatingClientID {
                lastClient = nil
            } else {
                DebugLogger.log("PriTypeInputController: deactivateServer preserved newer lastClient current=\(String(describing: currentClientID)) deactivating=\(deactivatingClientID)")
            }
        } else {
            lastClient = nil
        }
        // Keep cachedContext alive — activateServer() will replace it with the new client's context.
        // Clearing it here causes unnecessary slow path if handle() arrives before activateServer().
        NotificationCenter.default.removeObserver(self, name: .keyboardLayoutChanged, object: nil)
    }
    
    @objc private func handleLayoutChange() {
        let newId = ConfigurationManager.shared.keyboardId
        DebugLogger.log("PriTypeInputController: Layout changed to \(newId), updating composer")
        composer.updateKeyboardLayout(id: newId)
    }
    
    // Match the native IMK path used by DINKIssTyle: ask IMK for flagsChanged
    // so TIS can drive Caps Lock language switching, then pass modifier events
    // through without doing any work in handle().
    override public func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    override public func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        if tag == Int(kTextServiceInputModePropertyTag) {
            guard let inputModeID = value as? String, !inputModeID.isEmpty else {
                DebugLogger.log("PriTypeInputController: ignored empty input mode property")
                return
            }

            let isPriTypeMode = Self.isPriTypeInputMode(inputModeID)
            DebugLogger.log("PriTypeInputController: setValue inputMode='\(inputModeID)' priType=\(isPriTypeMode) current=\(composer.inputMode)")
            guard isPriTypeMode else {
                super.setValue(value, forTag: tag, client: sender)
                return
            }

            Self.lastInputModePropertyUpdateTime = CFAbsoluteTimeGetCurrent()
            let mode = Self.inputMode(forPriTypeInputModeID: inputModeID)
            if mode == .korean, let client = sender as? IMKTextInput {
                syncRomanKeyboardLayout(for: client, context: currentContext(for: sender), force: true)
            }

            if composer.inputMode != mode {
                DebugLogger.log("PriTypeInputController: TIS input mode '\(inputModeID)' -> \(mode)")
                composer.setInputMode(mode)
            }
            return
        }

        super.setValue(value, forTag: tag, client: sender)
    }

    private static func isPriTypeInputMode(_ inputModeID: String) -> Bool {
        inputModeID == priTypeInputSourceID || inputModeID.hasPrefix("\(priTypeInputSourceID).")
    }

    private static func inputMode(forPriTypeInputModeID inputModeID: String) -> InputMode {
        if inputModeID == priTypeEnglishInputModeID {
            return .english
        }
        return .korean
    }
    
    override public func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        #if DEBUG
        assert(Thread.isMainThread, "IMK handle must run on main thread")
        #endif
        guard let event = event, let client = sender as? IMKTextInput else { return false }

        guard event.type == .keyDown else {
            return false
        }

        // 1. Resolve context FIRST — all subsequent logic must use fresh bundleId.
        // Context is invalidated when the client object changes (app switch without activateServer).
        // When lastClient is nil (after deactivateServer), always re-analyze to avoid
        // using stale context from a previous app/field.
        var context: ClientContext
        if let cached = self.cachedContext, let last = lastClient, last === client {
            if cached.isLightweight && cached.isFinder {
                context = ClientContextDetector.analyze(client: client)
                self.cachedContext = context
            } else {
                context = cached
            }
        } else {
            DebugLogger.log("cachedContext miss: client changed or nil, analyzing (Slow Path)")
            context = ClientContextDetector.analyze(client: client)
            self.cachedContext = context
            // Do not update self.lastClient here. It must be updated alongside currentAdapter
            // below to ensure the adapter is correctly recreated when the client changes.
        }

        #if DEBUG
        if debugHandleLogCount < 1200 {
            debugHandleLogCount += 1
            DebugLogger.log("PriTypeInputController: handle keyCode=\(event.keyCode) mode=\(composer.inputMode) chars='\(event.characters ?? "")' modifiers=\(event.modifierFlags.rawValue) bundle=\(context.bundleId) lightweight=\(context.isLightweight) immediate=\(context.shouldUseImmediateMode) clientChanged=\(lastClient !== client)")
            if debugHandleSnapshotCount < 120, event.keyCode != KeyCode.backspace {
                debugHandleSnapshotCount += 1
                ClientAdapter(client: client).debugClientSnapshot("handle.before keyCode=\(event.keyCode)")
            }
        }
        #endif
        
        // 2. Mark current app for Hanja validation only when it changes.
        if lastMarkedKeystrokeBundleId != context.bundleId {
            composer.markKeystroke(bundleId: context.bundleId)
            lastMarkedKeystrokeBundleId = context.bundleId
        }

        // Finder-specific handling
        if context.shouldUseImmediateMode {
            DebugLogger.log("Finder: ImmediateMode (context=\(context))")
            // Only recreate adapter if client changed or type mismatch
            if lastClient !== client || !adapterMatchesContext(currentAdapter, context: context) {
                #if DEBUG
                if let currentAdapter = currentAdapter as? BaseClientAdapter {
                    currentAdapter.debugClientSnapshot("handle.immediate.before-adapter-replace")
                }
                #endif
                commitBeforeClientSwitch(to: client, context: context)
                lastClient = client
                syncRomanKeyboardLayout(for: client, context: context)
                installAdapter(for: client, context: context)
                #if DEBUG
                (currentAdapter as? BaseClientAdapter)?.debugClientSnapshot("handle.immediate.after-adapter-replace")
                #endif
            }
            let activeBefore = composer.hasActiveComposition
            if event.keyCode == KeyCode.backspace,
               event.isARepeat,
               !activeBefore,
               CFAbsoluteTimeGetCurrent() - lastBackspaceCompositionEndTime < backspaceRepeatSuppressionInterval {
                DebugLogger.log("PriTypeInputController: swallowed immediate Backspace repeat immediately after composition clear")
                return true
            }
            let handled = composer.handle(event, delegate: currentAdapter!)
            let activeAfter = composer.hasActiveComposition
            if handled && activeBefore && !activeAfter {
                if event.keyCode == KeyCode.backspace {
                    lastBackspaceCompositionEndTime = CFAbsoluteTimeGetCurrent()
                    DebugLogger.log("PriTypeInputController: skipped finalize after Backspace cleared immediate composition")
                    return handled
                }
                finalizeEndedCompositionIfNeeded(
                    client: client,
                    adapter: currentAdapter,
                    reason: "immediate keyCode=\(event.keyCode)"
                )
            }
            DebugLogger.log("PriTypeInputController: handle result immediate handled=\(handled) activeBefore=\(activeBefore) activeAfter=\(activeAfter)")
            #if DEBUG
            (currentAdapter as? BaseClientAdapter)?.debugClientSnapshot("handle.immediate.after keyCode=\(event.keyCode)")
            #endif
            return handled
        }
        
        // Reuse adapter from activateServer if client hasn't changed
        // This avoids ~20 heap allocations/second during fast typing
        if lastClient !== client || currentAdapter == nil || !adapterMatchesContext(currentAdapter, context: context) {
            #if DEBUG
            if let currentAdapter = currentAdapter as? BaseClientAdapter {
                currentAdapter.debugClientSnapshot("handle.standard.before-adapter-replace")
            }
            #endif
            commitBeforeClientSwitch(to: client, context: context)
            lastClient = client
            syncRomanKeyboardLayout(for: client, context: context)
            installAdapter(for: client, context: context)
            #if DEBUG
            (currentAdapter as? BaseClientAdapter)?.debugClientSnapshot("handle.standard.after-adapter-replace")
            #endif
        }
        
        let activeBefore = composer.hasActiveComposition
        if event.keyCode == KeyCode.backspace,
           event.isARepeat,
           !activeBefore,
           CFAbsoluteTimeGetCurrent() - lastBackspaceCompositionEndTime < backspaceRepeatSuppressionInterval {
            DebugLogger.log("PriTypeInputController: swallowed Backspace repeat immediately after composition clear")
            return true
        }
        let handled = composer.handle(event, delegate: currentAdapter!)
        let activeAfter = composer.hasActiveComposition
        if handled,
           event.keyCode == KeyCode.backspace,
           activeBefore,
           !activeAfter,
           (currentAdapter as? DirectCompositionAdapter)?.consumeBackspacePassThroughAfterFailedDirectClear() == true {
            DebugLogger.log("PriTypeInputController: passing through Backspace after failed direct clear")
            return false
        }
        if handled && activeBefore && !activeAfter {
            if event.keyCode == KeyCode.backspace {
                lastBackspaceCompositionEndTime = CFAbsoluteTimeGetCurrent()
                DebugLogger.log("PriTypeInputController: skipped finalize after Backspace cleared standard composition")
                return handled
            }
            finalizeEndedCompositionIfNeeded(
                client: client,
                adapter: currentAdapter,
                reason: "standard keyCode=\(event.keyCode)"
            )
        }
        DebugLogger.log("PriTypeInputController: handle result standard handled=\(handled) activeBefore=\(activeBefore) activeAfter=\(activeAfter)")
        #if DEBUG
        if debugHandleSnapshotCount < 120, event.keyCode != KeyCode.backspace {
            debugHandleSnapshotCount += 1
            (currentAdapter as? BaseClientAdapter)?.debugClientSnapshot("handle.standard.after keyCode=\(event.keyCode)")
        }
        #endif
        return handled
    }

    // 마우스 클릭 등으로 조합 영역 외부 클릭 시 조합 커밋
    override public func commitComposition(_ sender: Any!) {
        #if DEBUG
        assert(Thread.isMainThread, "IMK commitComposition must run on main thread")
        #endif
        if let client = sender as? IMKTextInput ?? lastClient {
            pendingMarkedReplacementRanges.removeValue(forKey: ObjectIdentifier(client as AnyObject))
            let adapter = currentAdapter ?? ClientAdapter(client: client)
            let markedRange = (adapter as? BaseClientAdapter)?.client.markedRange() ?? client.markedRange()
            if !composer.hasActiveComposition,
               !BaseClientAdapter.hasHostMarkedSession(markedRange) {
                DebugLogger.log("PriTypeInputController: commitComposition no-op active=false marked=\(markedRange) client=\(ObjectIdentifier(client as AnyObject))")
                (adapter as? BaseClientAdapter)?.finishMarkedText(reason: "commitComposition.no-op")
                composer.clearLocalBuffer()
                super.commitComposition(sender)
                return
            }
            DebugLogger.log("PriTypeInputController: commitComposition forceCommit active=\(composer.hasActiveComposition) sender=\(String(describing: type(of: sender))) client=\(ObjectIdentifier(client as AnyObject))")
            #if DEBUG
            (adapter as? BaseClientAdapter)?.debugClientSnapshot("commitComposition.before")
            #endif
            if composer.hasActiveComposition,
               let baseAdapter = adapter as? BaseClientAdapter,
               baseAdapter.client.selectedRange().location == NSNotFound,
               BaseClientAdapter.hasHostMarkedRange(markedRange) {
                let bundleId = cachedContext?.bundleId ?? client.bundleIdentifier() ?? ""
                forceDirectComposition(for: bundleId, reason: "invalid-selection-live-marked-on-commit")
            }
            composer.forceCommit(delegate: adapter)
            if composer.hasActiveComposition == false {
                (adapter as? BaseClientAdapter)?.finishMarkedTextAfterDirectCommit(reason: "commitComposition")
            }
            (adapter as? BaseClientAdapter)?.finishMarkedText(reason: "commitComposition")
            #if DEBUG
            (adapter as? BaseClientAdapter)?.debugClientSnapshot("commitComposition.after")
            #endif
        } else {
            DebugLogger.log("PriTypeInputController: commitComposition no client active=\(composer.hasActiveComposition) sender=\(String(describing: type(of: sender)))")
        }
        composer.localTextBuffer = "" // Clear buffer when focus changes or user clicks elsewhere
        super.commitComposition(sender)
    }

    private func currentContext(for sender: Any?) -> ClientContext? {
        if let client = sender as? IMKTextInput {
            if let cachedContext, lastClient === client {
                return cachedContext
            }
            return nil
        }
        return cachedContext
    }
    
    // MARK: - Input Method Menu
    
    /// Returns custom menu for the input method (shown in system input source menu)
    override public func menu() -> NSMenu! {
        let menu = NSMenu()
        
        // Settings
        let settingsItem = NSMenuItem(title: "PriType 설정...", action: #selector(openSettings(_:)), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // About
        let aboutItem = NSMenuItem(title: "PriType 정보", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        return menu
    }
    
    @objc private func openSettings(_ sender: Any?) {
        DebugLogger.log("Opening settings")
        DispatchQueue.main.async {
            SettingsWindowController.shared.showSettings()
        }
    }
    
    @MainActor
    @objc private func showAbout(_ sender: Any?) {
        DebugLogger.log("Showing about")
        AboutInfo.showAlert()
    }
}
