import AppKit
import Carbon.HIToolbox

/// Secure Event Input keeps keystrokes away from other processes' keyboard event taps.
/// NSSecureTextField holds it while a hidden password is edited. The revealed editor is an
/// ordinary text view, so this holds it for as long as that editor has keyboard focus.
/// The hold is counted per process and must always be released, or other apps' shortcuts stop working.
@MainActor
enum SecureKeyboardEntry {
    static var enable: () -> Void = { _ = EnableSecureEventInput() }
    static var disable: () -> Void = { _ = DisableSecureEventInput() }
    static var isAppActive: () -> Bool = { NSApp.isActive }
    private(set) static var isHeld = false

    static func hold() {
        guard !isHeld, isAppActive() else { return }
        isHeld = true; enable()
    }
    static func release() {
        guard isHeld else { return }
        isHeld = false; disable()
    }
}

/// Turns off the text-system conveniences that could send typed text to spelling, prediction or
/// writing services, alter it silently, or keep it in an undo stack. AppKit applies this when it
/// sets a field editor up, which is before the first keystroke.
@MainActor
private func hardenFieldEditor(_ text: NSText) {
    guard let editor = text as? NSTextView else { return }
    editor.allowsUndo = false
    editor.isAutomaticTextCompletionEnabled = false
    editor.isAutomaticSpellingCorrectionEnabled = false
    editor.isContinuousSpellCheckingEnabled = false
    editor.isGrammarCheckingEnabled = false
    editor.isAutomaticQuoteSubstitutionEnabled = false
    editor.isAutomaticDashSubstitutionEnabled = false
    editor.isAutomaticTextReplacementEnabled = false
    editor.isAutomaticDataDetectionEnabled = false
    editor.isAutomaticLinkDetectionEnabled = false
    // Smart insert adds a space when a word copied by double-click is pasted next to other text.
    editor.smartInsertDeleteEnabled = false
    if #available(macOS 14.0, *) { editor.inlinePredictionType = .no }
    if #available(macOS 15.0, *) {
        editor.mathExpressionCompletionType = .no
        editor.writingToolsBehavior = .none
    }
}

/// AppKit keeps text removed by these commands (Control-K, Command-Delete and relatives) in a
/// process-wide kill buffer that Control-Y inserts again, even after the fields are cleared.
/// Each maps to the selection it would remove, so the fields can delete without keeping the text.
private let killCommands: [Selector: Selector] = [
    #selector(NSResponder.deleteToEndOfParagraph(_:)): #selector(NSResponder.moveToEndOfParagraphAndModifySelection(_:)),
    #selector(NSResponder.deleteToBeginningOfParagraph(_:)): #selector(NSResponder.moveToBeginningOfParagraphAndModifySelection(_:)),
    #selector(NSResponder.deleteToEndOfLine(_:)): #selector(NSResponder.moveToEndOfLineAndModifySelection(_:)),
    #selector(NSResponder.deleteToBeginningOfLine(_:)): #selector(NSResponder.moveToBeginningOfLineAndModifySelection(_:)),
    #selector(NSResponder.deleteToMark(_:)): #selector(NSResponder.selectToMark(_:)),
]

@MainActor
final class CardView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (dark ? NSColor(calibratedWhite: 0.16, alpha: 1) : NSColor.controlBackgroundColor).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16).fill()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

@MainActor
final class HoldButton: NSButton {
    var holding: ((Bool) -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { guard isEnabled else { return }; highlight(true); holding?(true) }
    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        highlight(inside); holding?(inside)
    }
    override func mouseUp(with event: NSEvent) { highlight(false); holding?(false) }
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " { holding?(true) }
        else { super.keyDown(with: event) }
    }
    override func keyUp(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " { holding?(false) }
        else { super.keyUp(with: event) }
    }
    override func resignFirstResponder() -> Bool { holding?(false); return super.resignFirstResponder() }
}

private let accessibleFieldMetadata: Set<Selector> = [
    #selector(NSAccessibilityProtocol.isAccessibilityElement),
    #selector(NSAccessibilityProtocol.accessibilityRole),
    #selector(NSAccessibilityProtocol.accessibilitySubrole),
    #selector(NSAccessibilityProtocol.accessibilityRoleDescription),
    #selector(NSAccessibilityProtocol.accessibilityLabel),
    #selector(NSAccessibilityProtocol.accessibilityIdentifier),
    #selector(NSAccessibilityProtocol.accessibilityHelp),
    #selector(NSAccessibilityProtocol.accessibilityPlaceholderValue),
    #selector(NSAccessibilityProtocol.isAccessibilityEnabled),
    #selector(NSAccessibilityProtocol.isAccessibilityFocused),
    #selector(NSAccessibilityProtocol.setAccessibilityFocused(_:)),
    NSSelectorFromString("accessibilityFrame"),
    #selector(NSAccessibilityProtocol.accessibilityActivationPoint),
    #selector(NSAccessibilityProtocol.accessibilityParent),
    #selector(NSAccessibilityProtocol.accessibilityWindow),
    #selector(NSAccessibilityProtocol.accessibilityTopLevelUIElement),
    #selector(NSAccessibilityProtocol.accessibilityPerformPress),
]

@MainActor
private class InputTextFieldCell: NSTextFieldCell {
    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        let editor = super.setUpFieldEditorAttributes(textObj)
        hardenFieldEditor(editor)
        return editor
    }
}

@MainActor
private class InputTextField: NSTextField {
    override class var cellClass: AnyClass? { get { InputTextFieldCell.self } set {} }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { bounds.fill() }
}

@MainActor
private final class SecureInputTextField: NSSecureTextField {
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { bounds.fill() }
}

@MainActor
private final class SecureInputTextFieldCell: NSSecureTextFieldCell {
    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        let editor = super.fieldEditor(for: controlView)
        // Keep the native secure editor. The field alone supplies accessibility metadata.
        editor?.setAccessibilityElement(false)
        return editor
    }
    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        let editor = super.setUpFieldEditorAttributes(textObj)
        hardenFieldEditor(editor)
        return editor
    }
}

// AppKit hands a text field's cell, not the field, to accessibility clients as the focused
// element and as the hit-test result. The cell reads the same text, so it carries the same
// restrictions as the field below.
@MainActor
private final class PrivateTextFieldCell: InputTextFieldCell {
    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        accessibleFieldMetadata.contains(selector) && super.isAccessibilitySelectorAllowed(selector)
    }
    override func accessibilityValue() -> Any? { nil }
    override func accessibilitySelectedText() -> String? { nil }
    override func accessibilityString(for range: NSRange) -> String? { nil }
    override func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? { nil }
    override func accessibilityRTF(for range: NSRange) -> Data? { nil }
    override func accessibilityAttributeValue(
        _ attribute: NSAccessibility.ParameterizedAttribute, forParameter parameter: Any?
    ) -> Any? { nil }
}

// Reveal changes the display, while accessibility clients still receive only field metadata.
@MainActor
private final class PrivateTextField: InputTextField {
    override class var cellClass: AnyClass? { get { PrivateTextFieldCell.self } set {} }
    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        accessibleFieldMetadata.contains(selector) && super.isAccessibilitySelectorAllowed(selector)
    }
    override func accessibilityValue() -> String? { nil }
    override func accessibilitySelectedText() -> String? { nil }
    override func accessibilityString(for range: NSRange) -> String? { nil }
    override func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? { nil }
    override func accessibilityRTF(for range: NSRange) -> Data? { nil }
    override func accessibilityAttributeValue(
        _ attribute: NSAccessibility.ParameterizedAttribute, forParameter parameter: Any?
    ) -> Any? { nil }
}

@MainActor
final class PrivateFieldEditor: NSTextView {
    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        accessibleFieldMetadata.contains(selector) && super.isAccessibilitySelectorAllowed(selector)
    }
    override func accessibilityValue() -> String? { nil }
    override func accessibilitySelectedText() -> String? { nil }
    override func accessibilityString(for range: NSRange) -> String? { nil }
    override func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? { nil }
    override func accessibilityRTF(for range: NSRange) -> Data? { nil }
    // AppKit's legacy parameterized dispatcher can read NSTextView storage directly.
    override func accessibilityAttributeValue(
        _ attribute: NSAccessibility.ParameterizedAttribute, forParameter parameter: Any?
    ) -> Any? { nil }

    // NSTextView has export paths that do not call copy(_:), including dragging
    // selections and Services. A revealed password must never become a pasteboard
    // provider through any of those paths.
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [] }
    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool { false }
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool { false }
    override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?,
        returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        guard sendType == nil else { return nil }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }
    override func dragSelection(with event: NSEvent, offset mouseOffset: NSSize, slideBack: Bool) -> Bool { false }

    override func copy(_ sender: Any?) {}
    override func cut(_ sender: Any?) {}
    override func startSpeaking(_ sender: Any?) {}
    override func performFindPanelAction(_ sender: Any?) {}
    override func quickLook(with event: NSEvent) {}
    override func quickLookPreviewItems(_ sender: Any?) {}
    override func menu(for event: NSEvent) -> NSMenu? { nil }
    // Only these menu commands apply to a revealed password. Everything else an NSTextView offers,
    // including items the system adds to the Edit menu in later releases, stays disabled.
    private static let allowedActions: Set<Selector> = [
        #selector(paste(_:)),
        #selector(pasteAsPlainText(_:)),
        #selector(selectAll(_:)),
        #selector(delete(_:))
    ]
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        guard let action = item.action, Self.allowedActions.contains(action) else { return false }
        return super.validateUserInterfaceItem(item)
    }
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action, Self.allowedActions.contains(action) else { return false }
        return super.validateMenuItem(menuItem)
    }
    // Input methods, Look Up and dictation read surrounding text through this call.
    override func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { SecureKeyboardEntry.hold() }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { SecureKeyboardEntry.release() }
        return resigned
    }
}

@MainActor
final class SecretField: NSView, NSTextFieldDelegate {
    let plain: NSTextField
    let secure: NSSecureTextField = SecureInputTextField()
    let eye = HoldButton()
    let isSecret: Bool
    private let editable: Bool
    private var revealed = false
    private var changing = false
    var onEdit: (() -> Void)?
    var onSubmit: (() -> Void)?

    private var active: NSTextField { isSecret && !revealed ? secure : plain }
    var value: String {
        get { active.currentEditor()?.string ?? active.stringValue }
        set {
            changing = true
            defer { changing = false }
            if let editor = active.currentEditor() {
                _ = window?.makeFirstResponder(nil)
                editor.string = ""; editor.undoManager?.removeAllActions()
            }
            plain.stringValue = ""; secure.stringValue = ""
            active.stringValue = newValue
        }
    }

    init(title: String, placeholder: String, identifier: String, secret: Bool, editable: Bool = true) {
        isSecret = secret; self.editable = editable
        plain = secret ? PrivateTextField() : InputTextField()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let background = CardView()
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        secure.cell = SecureInputTextFieldCell(textCell: "")
        for field in [plain, secure] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.placeholderString = placeholder
            field.isBordered = false; field.drawsBackground = false
            field.focusRingType = .exterior
            field.isEditable = editable; field.isSelectable = editable
            field.font = secret ? .monospacedSystemFont(ofSize: 18, weight: .regular) : .systemFont(ofSize: 18)
            field.isAutomaticTextCompletionEnabled = false
            field.cell?.isScrollable = true
            // AppKit copies this to the field editor each time editing starts.
            field.cell?.allowsUndo = false
            field.delegate = self
            field.identifier = NSUserInterfaceItemIdentifier(identifier + (field === secure ? ".secure" : ".plain"))
            field.setAccessibilityLabel(title)
            // The cell is the element AppKit gives to accessibility clients, so it carries the label too.
            field.cell?.setAccessibilityLabel(title)
            addSubview(field)
        }
        if secret {
            secure.setAccessibilityElement(true)
            secure.setAccessibilityRole(.textField)
            secure.setAccessibilitySubrole(.secureTextField)
        }
        secure.isHidden = !secret; plain.isHidden = secret
        eye.translatesAutoresizingMaskIntoConstraints = false
        eye.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Hold to show \(title.lowercased())")
        eye.bezelStyle = .rounded
        eye.setButtonType(.momentaryPushIn)
        eye.isBordered = false
        eye.identifier = NSUserInterfaceItemIdentifier(identifier + ".reveal")
        eye.setAccessibilityLabel("Hold to show \(title.lowercased())")
        eye.setAccessibilityHelp("Release to hide. The password stays editable while you hold.")
        eye.holding = { [weak self] show in self?.setRevealed(show) }
        eye.isHidden = !secret
        addSubview(eye)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor), background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor), background.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            plain.leadingAnchor.constraint(equalTo: label.leadingAnchor), secure.leadingAnchor.constraint(equalTo: plain.leadingAnchor),
            plain.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6), secure.topAnchor.constraint(equalTo: plain.topAnchor),
            plain.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12), secure.bottomAnchor.constraint(equalTo: plain.bottomAnchor),
            plain.heightAnchor.constraint(equalToConstant: 27), secure.heightAnchor.constraint(equalTo: plain.heightAnchor),
            eye.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            eye.centerYAnchor.constraint(equalTo: plain.centerYAnchor), eye.widthAnchor.constraint(equalToConstant: 40), eye.heightAnchor.constraint(equalToConstant: 36),
            plain.trailingAnchor.constraint(equalTo: secret ? eye.leadingAnchor : trailingAnchor, constant: -10),
            secure.trailingAnchor.constraint(equalTo: plain.trailingAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setRevealed(_ show: Bool) {
        guard isSecret, show != revealed else { return }
        changing = true
        defer { changing = false }
        let previous = active
        let text = value
        let editor = previous.currentEditor() as? NSTextView
        let selection = editor?.selectedRange()
        // Keyboard focus moves between the secure editor and the revealed one below. Holding
        // Secure Event Input across the move leaves no moment in which keystrokes are observable.
        let bridged = editor != nil && SecureKeyboardEntry.isAppActive()
        if bridged { SecureKeyboardEntry.enable() }
        defer { if bridged { SecureKeyboardEntry.disable() } }
        if editor != nil { _ = window?.makeFirstResponder(nil) }
        editor?.string = ""; editor?.undoManager?.removeAllActions()
        previous.stringValue = ""; previous.isHidden = true
        revealed = show
        active.stringValue = text; active.isHidden = false
        eye.image = NSImage(systemSymbolName: show ? "eye.slash" : "eye", accessibilityDescription: nil)
        if editor != nil && editable {
            _ = window?.makeFirstResponder(active)
            if let selection, let current = active.currentEditor() as? NSTextView {
                let count = (text as NSString).length
                let location = min(selection.location, count)
                current.setSelectedRange(NSRange(location: location, length: min(selection.length, count - location)))
            }
        }
    }
    func hide() { setRevealed(false) }
    func focus() { _ = window?.makeFirstResponder(active) }
    func wipe() { value = ""; hide(); plain.stringValue = ""; secure.stringValue = "" }

    func controlTextDidChange(_ notification: Notification) { if !changing { onEdit?() } }
    func controlTextDidBeginEditing(_ notification: Notification) {
        // The cells apply this when the editor is set up. Repeated here in case AppKit resets a trait.
        guard let editor = active.currentEditor() as? NSTextView else { return }
        hardenFieldEditor(editor)
        editor.undoManager?.removeAllActions()
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { onSubmit?(); return true }
        if let extendSelection = killCommands[selector] {
            // Remove the same text without placing it in AppKit's kill buffer.
            if textView.selectedRange().length == 0 { textView.doCommand(by: extendSelection) }
            let doomed = textView.selectedRange()
            if doomed.length > 0 { textView.insertText("", replacementRange: doomed) }
            return true
        }
        return false
    }
}
