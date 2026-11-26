import UIKit

@MainActor
final class PrivateTextField: UITextField {
    var allowsEditing = true

    override var textInputContextIdentifier: String? { nil }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // All copying goes through the expiring, local-only Copy button.
        if action == #selector(copy(_:)) || action == #selector(cut(_:)) { return false }
        let permitted = [#selector(paste(_:)), #selector(select(_:)), #selector(selectAll(_:)), #selector(delete(_:))]
        if !allowsEditing || !permitted.contains(action) { return false }
        return super.canPerformAction(action, withSender: sender)
    }

    override func copy(_ sender: Any?) {}
    override func cut(_ sender: Any?) {}
}

@MainActor
final class SecretField: UIView {
    let field = PrivateTextField()
    let eye = UIButton(type: .custom)
    private var changingVisibility = false
    var onEdit: (() -> Void)?
    let isSecret: Bool

    init(title: String, placeholder: String, identifier: String, secret: Bool, editable: Bool = true) {
        isSecret = secret
        super.init(frame: .zero)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .subheadline).withTraits(.traitBold)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        field.placeholder = placeholder
        field.accessibilityLabel = title
        field.accessibilityIdentifier = identifier
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.isSecureTextEntry = secret
        field.allowsEditing = editable
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.textContentType = UITextContentType(rawValue: "")
        field.keyboardType = secret ? .asciiCapable : .URL
        field.returnKeyType = secret ? .go : .next
        field.clearsOnBeginEditing = false
        field.inputAssistantItem.leadingBarButtonGroups = []
        field.inputAssistantItem.trailingBarButtonGroups = []
        field.addTarget(self, action: #selector(edited), for: .editingChanged)
        if !editable { field.isUserInteractionEnabled = false }

        let row = UIStackView(arrangedSubviews: [field])
        row.alignment = .center
        row.spacing = 8
        if secret {
            eye.setImage(UIImage(systemName: "eye"), for: .normal)
            eye.tintColor = .secondaryLabel
            eye.accessibilityLabel = "Hold to show \(title.lowercased())"
            eye.accessibilityHint = "Keep your finger down to reveal. Release to hide."
            eye.accessibilityIdentifier = "\(identifier).reveal"
            eye.addTarget(self, action: #selector(reveal), for: [.touchDown, .touchDragEnter])
            eye.addTarget(self, action: #selector(hide), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
            eye.widthAnchor.constraint(equalToConstant: 48).isActive = true
            eye.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            row.addArrangedSubview(eye)
        }
        let stack = UIStackView(arrangedSubviews: [label, row])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func edited() { if !changingVisibility { onEdit?() } }
    @objc private func reveal() { setRevealed(true) }
    @objc func hide() { setRevealed(false) }

    private func setRevealed(_ revealed: Bool) {
        guard isSecret, field.isSecureTextEntry == revealed else { return }
        changingVisibility = true
        defer { changingVisibility = false }
        let value = field.text ?? ""
        let selected = field.selectedTextRange.map {
            (field.offset(from: field.beginningOfDocument, to: $0.start), field.offset(from: field.beginningOfDocument, to: $0.end))
        }
        field.isSecureTextEntry = !revealed
        // Reinserting prevents UIKit's secure/plain toggle from replacing the
        // whole value on the next keystroke. Preserve the actual field/caret.
        if field.isFirstResponder {
            field.text = ""
            field.insertText(value)
            if let selected,
               let start = field.position(from: field.beginningOfDocument, offset: selected.0),
               let end = field.position(from: field.beginningOfDocument, offset: selected.1) {
                field.selectedTextRange = field.textRange(from: start, to: end)
            }
        } else {
            field.text = value
        }
        field.undoManager?.removeAllActions()
        eye.setImage(UIImage(systemName: revealed ? "eye.slash" : "eye"), for: .normal)
    }

    func wipe() {
        field.resignFirstResponder()
        field.undoManager?.removeAllActions()
        field.text = nil
        hide()
    }
}

extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
