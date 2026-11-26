import AppKit

@MainActor
final class TestClock { var instant = ContinuousClock.now }

/// Stands in for the system's Secure Event Input calls, so the tests check that every hold is
/// released without switching secure input on for the whole machine.
@MainActor
final class SecureInputLog { var enables = 0; var net = 0; var peak = 0 }

@main
struct MacOSTests {
    @MainActor static func descendant(in view: NSView, identifier: String) -> NSView? {
        if view.identifier?.rawValue == identifier { return view }
        for child in view.subviews {
            if let match = descendant(in: child, identifier: identifier) { return match }
        }
        return nil
    }

    static func text(_ value: Any?) -> String? {
        switch value {
        case let value as String: return value
        case let value as NSAttributedString: return value.string
        case let value as Data: return String(decoding: value, as: UTF8.self)
        case let value as [Any]: return value.compactMap(text).joined(separator: "\n")
        default: return nil
        }
    }

    /// Every way an accessibility client can ask `object` for text: the modern getters, each
    /// attribute the object advertises through the older protocol, and the range readers.
    @MainActor static func exposures(of needle: String, by object: NSObject) -> [String] {
        var found: [String] = []
        let range = NSRange(location: 0, length: needle.utf16.count)
        func check(_ name: String, _ value: Any?) { if text(value)?.contains(needle) == true { found.append(name) } }
        if let element = object as? NSAccessibilityProtocol {
            check("accessibilityValue", element.accessibilityValue())
            check("accessibilitySelectedText", element.accessibilitySelectedText())
            check("accessibilityString(for:)", element.accessibilityString(for: range))
            check("accessibilityAttributedString(for:)", element.accessibilityAttributedString(for: range))
            check("accessibilityRTF(for:)", element.accessibilityRTF(for: range))
            check("accessibilityTitle", element.accessibilityTitle())
            check("accessibilityLabel", element.accessibilityLabel())
            check("accessibilityHelp", element.accessibilityHelp())
            check("accessibilityValueDescription", element.accessibilityValueDescription())
            check("accessibilityPlaceholderValue", element.accessibilityPlaceholderValue())
        }
        let reader = NSSelectorFromString("accessibilityAttributeValue:")
        if object.responds(to: reader) {
            var attributes = ["AXValue", "AXSelectedText", "AXValueDescription", "AXTitle", "AXDescription", "AXHelp", "AXPlaceholderValue"]
            let names = NSSelectorFromString("accessibilityAttributeNames")
            if object.responds(to: names), let advertised = object.perform(names)?.takeUnretainedValue() as? [String] { attributes += advertised }
            for attribute in Set(attributes).sorted() { check("AX attribute \(attribute)", object.perform(reader, with: attribute)?.takeUnretainedValue()) }
        }
        let rangeReader = NSSelectorFromString("accessibilityAttributeValue:forParameter:")
        if object.responds(to: rangeReader) {
            for attribute in ["AXStringForRange", "AXAttributedStringForRange", "AXRTFForRange"] {
                check("AX attribute \(attribute)", object.perform(rangeReader, with: attribute, with: NSValue(range: range))?.takeUnretainedValue())
            }
        }
        return found
    }

    /// What AppKit can hand to an accessibility client for this window. A client holds only the
    /// elements an app returns to it, so this starts from the window, the focused element and the
    /// element under `field`, then follows children and every other attribute that names an element.
    /// Every cell and every view that reports itself as an element is added as well. A view AppKit
    /// keeps out of the tree is represented by the ancestor a client is given in its place.
    @MainActor static func accessibilityObjects(in window: NSWindow, at field: NSView) -> (all: [NSObject], focused: NSObject?, hit: NSObject?) {
        let names = NSSelectorFromString("accessibilityAttributeNames"), reader = NSSelectorFromString("accessibilityAttributeValue:")
        let focusedElement = NSSelectorFromString("accessibilityFocusedUIElement")
        var seen = Set<ObjectIdentifier>(), all: [NSObject] = [], next = 0
        func add(_ candidate: Any?) {
            guard let object = candidate as? NSObject, object is NSAccessibilityProtocol,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            all.append(object)
        }
        func addViews(_ view: NSView) {
            add(view.isAccessibilityElement() ? view : NSAccessibility.unignoredAncestor(of: view))
            add((view as? NSControl)?.cell)
            view.subviews.forEach(addViews)
        }
        var focusAnswers: [Any?] = [
            NSApp.perform(reader, with: "AXFocusedUIElement")?.takeUnretainedValue(),
            NSApp.accessibilityApplicationFocusedUIElement()
        ]
        for owner: NSObject in [NSApp, window] where owner.responds(to: focusedElement) {
            focusAnswers.append(owner.perform(focusedElement)?.takeUnretainedValue())
        }
        let centre = window.convertPoint(toScreen: field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil))
        let hitAnswers: [Any?] = [NSApp.accessibilityHitTest(centre), window.accessibilityHitTest(centre)]
        add(window); focusAnswers.forEach(add); hitAnswers.forEach(add)
        if let root = window.contentView?.superview ?? window.contentView { addViews(root) }
        while next < all.count, all.count < 4000 {
            let element = all[next]; next += 1
            (element as? NSAccessibilityProtocol)?.accessibilityChildren()?.forEach(add)
            guard element.responds(to: names), element.responds(to: reader),
                  let attributes = element.perform(names)?.takeUnretainedValue() as? [String] else { continue }
            for attribute in attributes {
                let value = element.perform(reader, with: attribute)?.takeUnretainedValue()
                if let several = value as? [Any] { several.forEach(add) } else { add(value) }
            }
        }
        return (all, focusAnswers.compactMap { $0 as? NSObject }.first, hitAnswers.compactMap { $0 as? NSObject }.first)
    }

    @MainActor static func label(of element: NSObject?) -> String? { (element as? NSAccessibilityProtocol)?.accessibilityLabel() }

    /// Nothing AppKit can hand to an accessibility client answers with `needle`. The label checks
    /// prove the scan reached the field itself and not only its surroundings.
    @MainActor static func checkWithheld(_ needle: String, in window: NSWindow, at field: NSView, label: String, hasFocus: Bool, what: String) {
        let objects = accessibilityObjects(in: window, at: field)
        precondition(objects.all.count > 20, "The accessibility scan did not reach the window")
        precondition(Self.label(of: objects.hit) == label, "The element under the field is not the field")
        precondition(!hasFocus || Self.label(of: objects.focused) == label, "The focused element is not the field")
        var readable: [String] = []
        for object in objects.all {
            let found = exposures(of: needle, by: object)
            if !found.isEmpty { readable.append("\(type(of: object)) through \(found.joined(separator: ", "))") }
        }
        precondition(readable.isEmpty, "\(what) is readable from \(readable.joined(separator: "; "))")
    }

    /// The protections must already be in place when a field takes focus, before anything is typed.
    @MainActor static func checkHardenedEditor(_ editor: NSTextView) {
        precondition(!editor.allowsUndo && !editor.smartInsertDeleteEnabled)
        precondition(!editor.isAutomaticSpellingCorrectionEnabled && !editor.isAutomaticTextReplacementEnabled)
        precondition(!editor.isContinuousSpellCheckingEnabled && !editor.isGrammarCheckingEnabled)
        precondition(!editor.isAutomaticTextCompletionEnabled && !editor.isAutomaticQuoteSubstitutionEnabled)
        precondition(!editor.isAutomaticDashSubstitutionEnabled && !editor.isAutomaticDataDetectionEnabled)
        precondition(!editor.isAutomaticLinkDetectionEnabled)
        if #available(macOS 14.0, *) { precondition(editor.inlinePredictionType == .no) }
        if #available(macOS 15.0, *) { precondition(editor.writingToolsBehavior == .none && editor.mathExpressionCompletionType == .no) }
    }

    @MainActor static func checkPrivateAccessibility(_ view: NSObject & NSAccessibilityProtocol, label: String, length: Int) {
        let range = NSRange(location: 0, length: length)
        precondition(view.accessibilityLabel() == label)
        precondition(view.isAccessibilitySelectorAllowed(#selector(NSAccessibilityProtocol.accessibilityLabel)))
        precondition(view.isAccessibilitySelectorAllowed(#selector(NSAccessibilityProtocol.isAccessibilityFocused)))
        precondition(view.accessibilityValue() == nil && view.accessibilitySelectedText() == nil)
        precondition(view.accessibilityString(for: range) == nil)
        precondition(view.accessibilityAttributedString(for: range) == nil)
        precondition(view.accessibilityRTF(for: range) == nil)
        precondition(!view.isAccessibilitySelectorAllowed(#selector(NSAccessibilityProtocol.accessibilityValue)))
        precondition(!view.isAccessibilitySelectorAllowed(#selector(NSAccessibilityProtocol.accessibilityString(for:))))

        // Exercise the two older Objective-C dispatch paths as well as the modern methods.
        let legacyValueReader = NSSelectorFromString("accessibilityAttributeValue:")
        precondition(view.responds(to: legacyValueReader))
        for attribute: NSAccessibility.Attribute in [.value, .selectedText, .valueDescription] {
            precondition(view.perform(legacyValueReader, with: attribute.rawValue) == nil)
        }
        let legacyReader = NSSelectorFromString("accessibilityAttributeValue:forParameter:")
        precondition(view.responds(to: legacyReader))
        for attribute: NSAccessibility.ParameterizedAttribute in [.stringForRange, .attributedStringForRange, .rtfForRange] {
            precondition(view.perform(legacyReader, with: attribute.rawValue, with: NSValue(range: range)) == nil)
        }
    }

    @MainActor static func checkPrivateTextExport(_ editor: NSTextView, event: NSEvent) {
        let clipboard = NSPasteboard.withUniqueName()
        let stringTypes: [NSPasteboard.PasteboardType] = [
            .string,
            NSPasteboard.PasteboardType("NSStringPboardType")
        ]
        defer { clipboard.clearContents() }

        precondition(editor.writablePasteboardTypes.isEmpty)
        for type in stringTypes {
            precondition(!editor.writeSelection(to: clipboard, type: type))
            precondition(editor.validRequestor(forSendType: type, returnType: nil) == nil)
        }
        precondition(!editor.writeSelection(to: clipboard, types: stringTypes))
        precondition(!editor.dragSelection(with: event, offset: .zero, slideBack: false))
        precondition(clipboard.types?.isEmpty != false)

        // Menu commands are allowed by name. Anything else, including commands a later system adds, is off.
        for action in [
            #selector(NSText.copy(_:)),
            #selector(NSText.cut(_:)),
            #selector(NSTextView.startSpeaking(_:)),
            #selector(NSTextView.performFindPanelAction(_:)),
            #selector(NSResponder.quickLookPreviewItems(_:)),
            #selector(NSTextView.orderFrontSubstitutionsPanel(_:)),
            #selector(NSTextView.toggleContinuousSpellChecking(_:)),
            #selector(NSTextView.toggleAutomaticSpellingCorrection(_:)),
            #selector(NSResponder.uppercaseWord(_:)),
            NSSelectorFromString("showWritingTools:"),
            NSSelectorFromString("syntheticCommandFromALaterSystem:")
        ] {
            let item = NSMenuItem()
            item.action = action
            precondition(!editor.validateUserInterfaceItem(item) && !editor.validateMenuItem(item))
        }
        let selectAll = NSMenuItem()
        selectAll.action = #selector(NSText.selectAll(_:))
        precondition(editor.validateUserInterfaceItem(selectAll) && editor.validateMenuItem(selectAll))

        // Input methods and Look Up read text through this call, not through the pasteboard.
        let whole = NSRange(location: 0, length: editor.string.utf16.count)
        precondition(whole.length > 0 && editor.attributedSubstring(forProposedRange: whole, actualRange: nil) == nil)
    }

    @MainActor static func main() throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let secureInput = SecureInputLog()
        SecureKeyboardEntry.enable = {
            secureInput.enables += 1; secureInput.net += 1
            secureInput.peak = max(secureInput.peak, secureInput.net)
        }
        SecureKeyboardEntry.disable = { secureInput.net -= 1 }
        SecureKeyboardEntry.isAppActive = { true }
        let clipboard = NSPasteboard.withUniqueName()
        let clock = TestClock()
        let screen = PasswordViewController(clipboard: clipboard, now: { clock.instant })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 750), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.isRestorable = false
        window.alphaValue = 0
        window.contentViewController = screen; window.delegate = screen
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        defer { screen.clearSession(reason: .manual); clipboard.clearContents(); window.close() }
        precondition(screen.password.plain.isHidden && !screen.password.secure.isHidden)
        precondition(screen.output.plain.isHidden && !screen.copyButton.isEnabled)
        precondition(screen.address.frame.height > 60 && screen.generateButton.frame.height >= 38)
        for field in [screen.address.plain, screen.password.secure, screen.password.plain] {
            precondition(field.focusRingType == .exterior && !field.focusRingMaskBounds.isEmpty)
        }

        screen.address.focus()
        guard let addressEditor = screen.address.plain.currentEditor() as? NSTextView else { preconditionFailure("No address field editor") }
        checkHardenedEditor(addressEditor)
        screen.address.value = "https://login.example.com/path"
        precondition(screen.address.plain.accessibilityValue() == screen.address.value)
        // The address is meant to be readable. Finding it through the focused element and the element
        // under the field proves the scan would also find a password exposed the same way.
        screen.address.focus()
        let readable = accessibilityObjects(in: window, at: screen.address.plain)
        for path in [readable.focused, readable.hit] {
            precondition(label(of: path) == "Site Address")
            precondition(path.map { !exposures(of: screen.address.value, by: $0).isEmpty } == true)
        }
        screen.address.onEdit?()
        screen.password.value = "SyntheticPassword9!"
        screen.password.onEdit?()
        screen.generateButton.performClick(nil)
        let expected = try LegacyPwdHash.generate(address: screen.address.value, password: screen.password.value)
        precondition(screen.output.value == expected)
        precondition(screen.copyButton.isEnabled)
        screen.address.value = "different.example.org"
        screen.address.onEdit?()
        precondition(screen.password.value == "SyntheticPassword9!")
        precondition(screen.output.value.isEmpty && !screen.copyButton.isEnabled)
        print("PASS: macOS generation, input reuse, and stale-result invalidation")

        screen.password.focus()
        guard let editor = screen.password.secure.currentEditor() as? NSTextView else { preconditionFailure("No secure field editor") }
        checkHardenedEditor(editor)
        precondition(secureInput.net == 0 && !SecureKeyboardEntry.isHeld)
        checkWithheld("SyntheticPassword9!", in: window, at: screen.password.secure, label: "Site Password", hasFocus: true, what: "The hidden site password")
        // The hidden field's editor is a system class this app cannot subclass, and asked directly it
        // answers a range request with the typed text. AppKit must therefore never return it to a client.
        precondition(!editor.isAccessibilityElement())
        precondition(!accessibilityObjects(in: window, at: screen.password.secure).all.contains { $0 === editor })
        precondition(editor.writablePasteboardTypes.isEmpty)
        precondition(screen.password.secure.isAccessibilityElement())
        precondition(screen.password.secure.accessibilityLabel() == "Site Password")
        precondition(screen.password.secure.accessibilityValue() != screen.password.value)
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
        screen.password.eye.mouseDown(with: down)
        precondition(!screen.password.plain.isHidden && screen.password.secure.isHidden)
        precondition(screen.password.value == "SyntheticPassword9!")
        guard let visibleEditor = screen.password.plain.currentEditor() as? NSTextView else { preconditionFailure("No revealed field editor") }
        precondition(visibleEditor is PrivateFieldEditor)
        checkHardenedEditor(visibleEditor)
        precondition(secureInput.net == 1 && SecureKeyboardEntry.isHeld)
        precondition(visibleEditor.selectedRange().location == 4)
        let passwordLength = screen.password.value.utf16.count
        visibleEditor.setSelectedRange(NSRange(location: 0, length: passwordLength))
        checkPrivateAccessibility(screen.password.plain, label: "Site Password", length: passwordLength)
        checkPrivateAccessibility(visibleEditor, label: "Site Password", length: passwordLength)
        // AppKit hands the field's cell, not the field, to accessibility clients.
        guard let visibleCell = screen.password.plain.cell else { preconditionFailure("No revealed field cell") }
        checkPrivateAccessibility(visibleCell, label: "Site Password", length: passwordLength)
        checkWithheld("SyntheticPassword9!", in: window, at: screen.password.plain, label: "Site Password", hasFocus: true, what: "The revealed site password")
        checkPrivateTextExport(visibleEditor, event: down)
        visibleEditor.setSelectedRange(NSRange(location: 4, length: 0))
        visibleEditor.insertText("X", replacementRange: visibleEditor.selectedRange())
        screen.password.eye.mouseUp(with: up)
        precondition(secureInput.net == 0 && !SecureKeyboardEntry.isHeld)
        precondition(screen.password.plain.isHidden && !screen.password.secure.isHidden)
        precondition(screen.password.value == "SyntXheticPassword9!")
        guard let hiddenEditor = screen.password.secure.currentEditor() as? NSTextView else { preconditionFailure("No restored secure editor") }
        precondition(!hiddenEditor.isAccessibilityElement())
        hiddenEditor.insertText("Y", replacementRange: hiddenEditor.selectedRange())
        precondition(screen.password.value == "SyntXYheticPassword9!")
        print("PASS: macOS hold/release reveal, caret preservation, and continued editing in both modes")

        screen.generateButton.performClick(nil)
        let result = screen.output.value
        screen.output.eye.mouseDown(with: down)
        precondition(!screen.output.plain.isHidden && screen.output.value == result)
        checkPrivateAccessibility(screen.output.plain, label: "Hashed Password", length: result.utf16.count)
        guard let resultCell = screen.output.plain.cell else { preconditionFailure("No revealed result cell") }
        checkPrivateAccessibility(resultCell, label: "Hashed Password", length: result.utf16.count)
        checkWithheld(result, in: window, at: screen.output.plain, label: "Hashed Password", hasFocus: false, what: "The revealed hashed password")
        screen.output.eye.mouseUp(with: up)
        precondition(screen.output.plain.isHidden && screen.output.value == result)
        print("PASS: revealed passwords withheld from accessibility, pasteboard, drag, and Services export")
        screen.copyButton.performClick(nil)
        precondition(clipboard.string(forType: .string) == result)
        precondition(clipboard.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) == true)
        precondition(clipboard.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) == true)
        clock.instant = clock.instant.advanced(by: .seconds(61))
        precondition(screen.acceptInteraction())
        precondition(clipboard.string(forType: .string) == nil)
        precondition(screen.output.value == result)
        screen.copyButton.performClick(nil)
        clipboard.clearContents(); clipboard.setString("Synthetic newer copy", forType: .string)
        screen.clearSession(reason: .manual)
        precondition(clipboard.string(forType: .string) == "Synthetic newer copy")
        print("PASS: macOS private clipboard copy, privacy markers, expiration, and newer-copy preservation")

        func populate() {
            screen.address.value = "example.com"; screen.address.onEdit?()
            screen.password.value = "SyntheticPassword9!"; screen.password.onEdit?()
            screen.generateButton.performClick(nil)
        }
        populate(); screen.copyButton.performClick(nil)
        let copied = clipboard.string(forType: .string)
        screen.enteredBackground()
        precondition(screen.address.value.isEmpty && screen.password.value.isEmpty && screen.output.value.isEmpty)
        precondition(clipboard.string(forType: .string) == copied)
        screen.becameActive()
        screen.backgroundSwitch.state = .off; screen.backgroundSettingChanged(nil)
        populate(); screen.password.setRevealed(true); screen.enteredBackground()
        precondition(screen.password.value == "SyntheticPassword9!" && screen.password.plain.isHidden)
        screen.becameActive()
        clock.instant = clock.instant.advanced(by: .seconds(301))
        precondition(!screen.acceptInteraction())
        precondition(screen.password.value.isEmpty && screen.address.value.isEmpty)
        populate(); screen.copyButton.performClick(nil); screen.clearSession(reason: .sleep)
        precondition(screen.password.value.isEmpty && clipboard.string(forType: .string) == nil)
        print("PASS: macOS background modes, expired-action rejection, and sleep cleanup")

        // Ctrl-K, Cmd-Delete and similar commands normally move the removed text into a buffer AppKit
        // keeps for the whole app, and Ctrl-Y pastes it back, even after Clear. The marker shows
        // whether a command replaced the buffer's contents.
        let scratch = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        let marker = "SyntheticMarker"
        func kill(_ text: String) {
            scratch.string = text; scratch.setSelectedRange(NSRange(location: 0, length: 0))
            scratch.deleteToEndOfParagraph(nil)
        }
        func killBuffer() -> String { scratch.string = ""; scratch.yank(nil); return scratch.string }
        kill("SyntheticOther"); precondition(killBuffer() == "SyntheticOther")
        kill(marker); precondition(killBuffer() == marker)
        let removals: [(command: Selector, fromStart: Bool, removesAll: Bool)] = [
            (#selector(NSResponder.deleteToEndOfParagraph(_:)), true, true),
            (#selector(NSResponder.deleteToEndOfLine(_:)), true, true),
            (#selector(NSResponder.deleteToBeginningOfLine(_:)), false, true),
            (#selector(NSResponder.deleteToBeginningOfParagraph(_:)), false, true),
            (#selector(NSResponder.deleteToMark(_:)), false, true),
            (#selector(NSResponder.deleteWordBackward(_:)), false, false),
            (#selector(NSResponder.deleteWordForward(_:)), true, false),
            (#selector(NSResponder.deleteBackward(_:)), false, false)
        ]
        for mode in ["address", "hidden password", "revealed password"] {
            for removal in removals {
                let field = mode == "address" ? screen.address : screen.password
                let original = mode == "address" ? "private.example-REALM" : "SyntheticPassword9!"
                let length = (original as NSString).length
                field.value = original; field.focus()
                if mode == "revealed password" { field.setRevealed(true) }
                guard let editor = (field.plain.currentEditor() ?? field.secure.currentEditor()) as? NSTextView else { preconditionFailure("No editor for the \(mode)") }
                if removal.command == #selector(NSResponder.deleteToMark(_:)) {
                    editor.setSelectedRange(NSRange(location: 0, length: 0))
                    editor.doCommand(by: #selector(NSResponder.setMark(_:)))
                }
                editor.setSelectedRange(NSRange(location: removal.fromStart ? 0 : length, length: 0))
                editor.doCommand(by: removal.command)
                precondition((field.value as NSString).length < length, "\(removal.command) removed nothing from the \(mode)")
                precondition(!removal.removesAll || field.value.isEmpty, "\(removal.command) left text in the \(mode)")
                screen.clearSession(reason: .manual)
                precondition(killBuffer() == marker, "\(removal.command) left \(mode) text in the kill buffer")
            }
        }

        // A word copied by double-click is marked so that pasting it next to other text adds a space,
        // which would silently change an address or a password.
        let smart = NSPasteboard.withUniqueName()
        let smartType = NSPasteboard.PasteboardType("NeXT smart paste pasteboard type")
        smart.declareTypes([.string, smartType], owner: nil)
        smart.setString("def", forType: .string); smart.setData(Data(), forType: smartType)
        func pasted(into editor: NSTextView) -> String {
            editor.setSelectedRange(NSRange(location: 3, length: 0))
            precondition(editor.readSelection(from: smart))
            return editor.string
        }
        scratch.smartInsertDeleteEnabled = true; scratch.string = "abc"
        precondition(pasted(into: scratch) == "abc def")
        screen.address.value = "abc"; screen.address.focus()
        guard let addressPaste = screen.address.plain.currentEditor() as? NSTextView else { preconditionFailure("No address editor") }
        precondition(pasted(into: addressPaste) == "abcdef" && screen.address.value == "abcdef")
        screen.password.value = "abc"; screen.password.focus()
        guard let hiddenPaste = screen.password.secure.currentEditor() as? NSTextView else { preconditionFailure("No secure editor") }
        precondition(pasted(into: hiddenPaste) == "abcdef" && screen.password.value == "abcdef")
        screen.password.value = "abc"; screen.password.focus(); screen.password.setRevealed(true)
        guard let revealedPaste = screen.password.plain.currentEditor() as? NSTextView else { preconditionFailure("No revealed editor") }
        precondition(pasted(into: revealedPaste) == "abcdef" && screen.password.value == "abcdef")
        screen.password.setRevealed(false)
        precondition(screen.password.value == "abcdef")
        smart.clearContents(); screen.clearSession(reason: .manual)
        print("PASS: macOS editor protections before the first keystroke, kill-buffer and smart-paste handling")

        // Secure keyboard entry is counted per process and applies to the whole Mac, so every hold
        // must be released: on hide, when focus leaves, and whenever the app is not in front.
        precondition(secureInput.enables > 0 && secureInput.net == 0 && !SecureKeyboardEntry.isHeld)
        func revealWhileEditing() {
            screen.password.value = "SyntheticPassword9!"; screen.password.focus(); screen.password.setRevealed(true)
        }
        screen.password.value = "SyntheticPassword9!"; screen.password.focus()
        precondition(secureInput.net == 0)
        // Keyboard focus passes from the hidden editor to the revealed one and back. A second, short
        // hold spans each move, so the two overlap and no keystroke falls between them.
        secureInput.peak = 0
        screen.password.setRevealed(true)
        precondition(secureInput.net == 1 && secureInput.peak == 2 && SecureKeyboardEntry.isHeld)
        secureInput.peak = 0
        screen.password.setRevealed(false)
        precondition(secureInput.net == 0 && secureInput.peak == 2 && !SecureKeyboardEntry.isHeld)
        revealWhileEditing(); precondition(secureInput.net == 1)
        screen.address.focus()
        precondition(secureInput.net == 0 && !SecureKeyboardEntry.isHeld)
        revealWhileEditing(); precondition(secureInput.net == 1)
        screen.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        precondition(screen.password.plain.isHidden && secureInput.net == 0 && !SecureKeyboardEntry.isHeld)
        precondition(screen.password.value == "SyntheticPassword9!")
        // "Clear when leaving app" is off here, so the password being edited is hidden and kept.
        precondition(screen.backgroundSwitch.state == .off)
        revealWhileEditing(); precondition(secureInput.net == 1)
        screen.enteredBackground()
        precondition(screen.password.plain.isHidden && secureInput.net == 0 && !SecureKeyboardEntry.isHeld)
        precondition(screen.password.value == "SyntheticPassword9!" && screen.password.plain.stringValue.isEmpty)
        screen.becameActive()
        precondition(secureInput.net == 0 && !SecureKeyboardEntry.isHeld)
        precondition(screen.password.value == "SyntheticPassword9!" && screen.password.plain.isHidden)
        revealWhileEditing(); precondition(secureInput.net == 1)
        screen.clearSession(reason: .manual)
        precondition(secureInput.net == 0 && !SecureKeyboardEntry.isHeld)
        // A reveal while another app is in front takes no hold, so that app's keyboard is unaffected.
        SecureKeyboardEntry.isAppActive = { false }
        let enablesWhileInactive = secureInput.enables
        revealWhileEditing()
        precondition(screen.password.plain.currentEditor() is PrivateFieldEditor)
        precondition(secureInput.enables == enablesWhileInactive && secureInput.net == 0 && !SecureKeyboardEntry.isHeld)
        SecureKeyboardEntry.isAppActive = { true }
        screen.becameActive()
        precondition(screen.password.plain.isHidden && secureInput.net == 0 && !SecureKeyboardEntry.isHeld)
        screen.clearSession(reason: .manual)
        precondition(secureInput.net == 0 && !SecureKeyboardEntry.isHeld)
        print("PASS: macOS secure keyboard entry held only while a revealed password is edited")

        // The caution never blocks or changes a result, and a plain name, in any letter case,
        // never shows one.
        guard let hint = descendant(in: screen.view, identifier: "domainHint") as? NSTextField else { preconditionFailure("No domain hint") }
        func shownHint(for address: String) -> String {
            screen.address.value = address; screen.address.onEdit?()
            return hint.stringValue
        }
        precondition(hint.stringValue == PasswordViewController.domainRulesHint)
        let silent = [
            "example.com": "example.com", "example.ABCD": "example.ABCD", "Mail.Example-Site_1.QwErTy9": "Example-Site_1.QwErTy9",
            "https://login.example.com/path": "example.com", "http://www.example.co.uk/a/b": "example.co.uk", "localhost": "localhost"
        ]
        for (address, domain) in silent {
            precondition(shownHint(for: address) == "Hashing domain: \(domain)", "Unexpected notice for \(address)")
            precondition(AddressCaution.message(for: address) == nil && hint.textColor == .secondaryLabelColor)
        }
        let cautioned: [(address: String, domain: String, mentions: [String])] = [
            ("https://evil.example#.bank.example", "bank.example", ["contains “#”", "may not be the site a link opens"]),
            ("https://evil.example?next=www.bank.example", "bank.example", ["contains “?”"]),
            ("https://evil.example\\.bank.example/login", "bank.example", ["contains “\\”"]),
            ("https://user@example.com/", "user@example.com", ["contains “@”", "user name"]),
            ("example.com:8443", "example.com:8443", ["contains “:”", "port"]),
            ("www.example.com:8443", "example.com:8443", ["contains “:”", "port"]),
            ("HTTPS://www.example.com/", "HTTPS:", ["only lowercase", "“HTTPS:”"]),
            ("example%2ecom", "example%2ecom", ["contains “%”"]),
            (" example.com", " example.com", ["contains a space", "Nothing is trimmed"]),
            ("example.com\t", "example.com\t", ["contains a tab"]),
            ("b\u{161}nk.example", "b\u{161}nk.example", ["“\u{161}” (U+0161)", "different names can give the same password"]),
            ("exam\u{200B}ple.com", "exam\u{200B}ple.com", ["may be invisible (U+200B)"])
        ]
        for entry in cautioned {
            let shown = shownHint(for: entry.address)
            precondition(shown.hasPrefix("Hashing domain: \(entry.domain)\nCaution: "), "No caution for \(entry.address.debugDescription)")
            for phrase in entry.mentions { precondition(shown.contains(phrase), "The caution for \(entry.address.debugDescription) does not mention \(phrase)") }
            precondition(hint.textColor == .labelColor)
            screen.password.value = "SyntheticPassword9!"; screen.password.onEdit?()
            screen.generateButton.performClick(nil)
            let unchanged = try LegacyPwdHash.generate(address: entry.address, password: "SyntheticPassword9!")
            precondition(screen.output.value == unchanged, "The caution changed the result for \(entry.address.debugDescription)")
            precondition(screen.copyButton.isEnabled && hint.stringValue == shown)
        }
        precondition(shownHint(for: "") == PasswordViewController.domainRulesHint && hint.textColor == .secondaryLabelColor)
        // The caution reads the same site part the algorithm does, or it would describe another address.
        for address in silent.keys + cautioned.map(\.address) + ["", "/", "//", "http://", "https://http://a.example/b", "a/b.example", "www.a.b.example./"] {
            let site = AddressCaution.sitePart(of: address), domain = try? LegacyPwdHash.domain(for: address)
            precondition((site == nil) == (domain == nil), "Site part and hashing domain disagree for \(address.debugDescription)")
            if let site, let domain {
                precondition(site.unicodeScalars.reversed().starts(with: domain.unicodeScalars.reversed()), "Hashing domain is not the end of the site part for \(address.debugDescription)")
            }
        }
        screen.clearSession(reason: .manual)
        print("PASS: macOS address cautions without blocking or changing results")

        // A private notification centre stands in for the system one, so nothing is posted to other apps.
        precondition(AppDelegate.screenLockedNotification.rawValue == "com.apple.screenIsLocked")
        guard let statusLine = descendant(in: screen.view, identifier: "status") as? NSTextField else { preconditionFailure("No status line") }
        let delegate = AppDelegate(screen: screen), lockCentre = NotificationCenter()
        delegate.observeScreenLock(on: lockCentre)
        populate(); screen.copyButton.performClick(nil)
        precondition(clipboard.string(forType: .string) != nil)
        lockCentre.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        precondition(screen.password.value == "SyntheticPassword9!" && clipboard.string(forType: .string) != nil)
        lockCentre.post(name: AppDelegate.screenLockedNotification, object: nil)
        precondition(screen.address.value.isEmpty && screen.password.value.isEmpty && screen.output.value.isEmpty)
        precondition(clipboard.string(forType: .string) == nil)
        precondition(statusLine.stringValue == "Fields and copied password cleared when the screen locked.")
        withExtendedLifetime(delegate) {}
        print("PASS: macOS screen-lock cleanup")

        screen.toggleAbout(nil); window.contentView?.layoutSubtreeIfNeeded()
        precondition(screen.aboutButton.title == "Hide about & credits")
        precondition(descendant(in: screen.view, identifier: "supportWebsite") is NSButton)
        precondition(descendant(in: screen.view, identifier: "privacyPolicy") is NSButton)
        precondition(PasswordViewController.supportURL == "https://nmic.app/pwdhash/macos")
        precondition(PasswordViewController.privacyPolicyURL == "https://nmic.app/pwdhash/macos/privacy")
        screen.toggleAbout(nil); window.contentView?.layoutSubtreeIfNeeded()
        precondition(screen.aboutButton.title == "About & credits")
        screen.backgroundSwitch.state = .on; screen.backgroundSettingChanged(nil)
        screen.becameActive(); populate(); window.contentView?.layoutSubtreeIfNeeded()
        window.alphaValue = 1
        app.activate(ignoringOtherApps: true)
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        func invalidate(_ view: NSView) {
            view.needsDisplay = true
            for child in view.subviews { invalidate(child) }
        }
        invalidate(screen.view)
        guard let bitmap = screen.view.bitmapImageRepForCachingDisplay(in: screen.view.bounds) else { preconditionFailure("No desktop preview") }
        screen.view.cacheDisplay(in: screen.view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) {
            let path = URL(fileURLWithPath: CommandLine.arguments[1])
            try data.write(to: path)
        }
        print("PASS: macOS inline credits and desktop rendering with synthetic inputs")
    }
}
