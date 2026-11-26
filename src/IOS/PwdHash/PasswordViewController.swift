import UIKit
import UniformTypeIdentifiers

@MainActor
final class PasswordViewController: UIViewController, UITextFieldDelegate {
    enum ClearReason { case manual, idle, background }

    private let address = SecretField(title: "Site Address", placeholder: "example.com or full URL", identifier: "siteAddress", secret: false)
    private let password = SecretField(title: "Site Password", placeholder: "Your original password", identifier: "sitePassword", secret: true)
    private let output = SecretField(title: "Hashed Password", placeholder: "Generate to see your result", identifier: "hashedPassword", secret: true, editable: false)
    private let generateButton = UIButton(type: .system)
    private let copyButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let backgroundSwitch = UISwitch()
    private let backgroundDetail = UILabel()
    private let status = UILabel()
    private let domainLabel = UILabel()
    private let aboutButton = UIButton(type: .system)
    private let aboutContainer = UIView()
    private let aboutDetails = UIStackView()
    private var idle = IdleDeadline()
    private var timer: Timer?
    private var copiedChangeCount: Int?

    private let accent = UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(red: 0.43, green: 0.84, blue: 0.70, alpha: 1) : UIColor(red: 0.10, green: 0.36, blue: 0.28, alpha: 1)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        view.tintColor = accent
        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.alwaysBounceVertical = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])

        let title = UILabel()
        title.text = "PwdHash"
        title.font = .preferredFont(forTextStyle: .largeTitle).withTraits(.traitBold)
        title.adjustsFontForContentSizeCategory = true
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var clearConfig = UIButton.Configuration.plain()
        clearConfig.title = "Clear"
        clearConfig.image = UIImage(systemName: "eraser")
        clearConfig.imagePadding = 6
        clearButton.configuration = clearConfig
        clearButton.accessibilityLabel = "Clear all fields and copied password"
        clearButton.accessibilityIdentifier = "clearAll"
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        clearButton.setContentHuggingPriority(.required, for: .horizontal)
        clearButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let header = UIStackView(arrangedSubviews: [title, clearButton])
        header.alignment = .center

        let badge = makeLabel("OFFLINE  ·  ORIGINAL PWDHASH", style: .caption1)
        badge.font = .preferredFont(forTextStyle: .caption1).withTraits(.traitBold)
        badge.textColor = accent

        address.field.delegate = self
        password.field.delegate = self
        address.onEdit = { [weak self] in self?.inputsChanged() }
        password.onEdit = { [weak self] in self?.inputsChanged() }
        domainLabel.text = "Uses the same domain rules as the original website."
        domainLabel.font = .preferredFont(forTextStyle: .caption1)
        domainLabel.adjustsFontForContentSizeCategory = true
        domainLabel.textColor = .secondaryLabel
        domainLabel.numberOfLines = 0
        domainLabel.accessibilityIdentifier = "domainHint"

        var generateConfig = UIButton.Configuration.filled()
        generateConfig.title = "Generate"
        generateConfig.image = UIImage(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
        generateConfig.imagePadding = 10
        generateConfig.cornerStyle = .large
        generateConfig.baseBackgroundColor = accent
        generateConfig.baseForegroundColor = .systemBackground
        generateConfig.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        generateButton.configuration = generateConfig
        generateButton.accessibilityIdentifier = "generate"
        generateButton.addTarget(self, action: #selector(generate), for: .touchUpInside)

        var copyConfig = UIButton.Configuration.tinted()
        copyConfig.title = "Copy"
        copyConfig.image = UIImage(systemName: "doc.on.doc")
        copyConfig.imagePadding = 8
        copyConfig.cornerStyle = .large
        copyConfig.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        copyButton.configuration = copyConfig
        copyButton.isEnabled = false
        copyButton.accessibilityLabel = "Copy hashed password"
        copyButton.accessibilityIdentifier = "copyPassword"
        copyButton.addTarget(self, action: #selector(copyPassword), for: .touchUpInside)

        let holdHint = makeLabel("Hold an eye to reveal. Release to hide.", style: .caption1)
        status.font = .preferredFont(forTextStyle: .footnote)
        status.adjustsFontForContentSizeCategory = true
        status.numberOfLines = 0
        status.textColor = .secondaryLabel
        status.accessibilityIdentifier = "status"
        status.text = "Nothing saved. No history. No network."

        backgroundSwitch.isOn = true
        backgroundSwitch.onTintColor = accent
        backgroundSwitch.accessibilityIdentifier = "clearOnBackground"
        backgroundSwitch.accessibilityLabel = "Clear when leaving app"
        backgroundSwitch.addTarget(self, action: #selector(backgroundSettingChanged), for: .valueChanged)
        let backgroundTitle = makeLabel("Clear when leaving app", style: .subheadline)
        backgroundTitle.textColor = .label
        let backgroundRow = UIStackView(arrangedSubviews: [backgroundTitle, backgroundSwitch])
        backgroundRow.alignment = .center
        backgroundRow.spacing = 10
        backgroundDetail.font = .preferredFont(forTextStyle: .caption1)
        backgroundDetail.adjustsFontForContentSizeCategory = true
        backgroundDetail.textColor = .secondaryLabel
        backgroundDetail.numberOfLines = 0
        backgroundSettingChanged()

        configureAbout()

        let actions = UIStackView(arrangedSubviews: [generateButton, copyButton])
        actions.distribution = .fillEqually
        actions.spacing = 10
        let stack = UIStackView(arrangedSubviews: [header, badge, address, password, domainLabel, output, actions, holdHint, status, backgroundRow, backgroundDetail, aboutButton, aboutContainer])
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(4, after: header)
        stack.setCustomSpacing(14, after: badge)
        stack.setCustomSpacing(4, after: password)
        stack.setCustomSpacing(6, after: actions)
        stack.setCustomSpacing(8, after: holdHint)
        stack.setCustomSpacing(14, after: status)
        stack.setCustomSpacing(4, after: backgroundRow)
        stack.setCustomSpacing(4, after: aboutButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -22),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -44)
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        scroll.addGestureRecognizer(tap)
        NotificationCenter.default.addObserver(self, selector: #selector(memoryWarning), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }

    private func makeLabel(_ text: String, style: UIFont.TextStyle) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }

    private func configureAbout() {
        var config = UIButton.Configuration.plain()
        config.title = "About & credits"
        config.image = UIImage(systemName: "info.circle")
        config.imagePadding = 8
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)
        aboutButton.configuration = config
        aboutButton.contentHorizontalAlignment = .leading
        aboutButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        aboutButton.accessibilityIdentifier = "aboutCredits"
        aboutButton.accessibilityLabel = "About and credits"
        aboutButton.accessibilityValue = "Collapsed"
        aboutButton.accessibilityHint = "Shows support, the privacy policy, credits, and license on this screen."
        aboutButton.addTarget(self, action: #selector(toggleAbout), for: .touchUpInside)

        aboutDetails.axis = .vertical
        aboutDetails.spacing = 12
        aboutContainer.isHidden = true
        aboutContainer.clipsToBounds = true
        aboutContainer.backgroundColor = .secondarySystemGroupedBackground
        aboutContainer.layer.cornerRadius = 16
        aboutContainer.layer.cornerCurve = .continuous
        let author = makeLabel("iOS app developed by Nenad Micic as a personal hobby project, based on Stanford PwdHash.", style: .footnote)
        author.textColor = .label
        author.accessibilityIdentifier = "aboutAuthor"
        aboutDetails.addArrangedSubview(author)

        let links: [(title: String, symbol: String, identifier: String, action: Selector)] = [
            ("Support & app information", "questionmark.circle", "supportWebsite", #selector(openSupportWebsite)),
            ("Privacy policy", "hand.raised", "privacyPolicy", #selector(openPrivacyPolicy))
        ]
        for link in links {
            let button = UIButton(type: .system)
            var linkConfig = UIButton.Configuration.plain()
            linkConfig.title = link.title
            linkConfig.image = UIImage(systemName: link.symbol)
            linkConfig.imagePadding = 8
            linkConfig.titleLineBreakMode = .byWordWrapping
            linkConfig.contentInsets = .zero
            button.configuration = linkConfig
            button.contentHorizontalAlignment = .leading
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.accessibilityIdentifier = link.identifier
            button.accessibilityLabel = link.title
            button.accessibilityHint = "Opens in your web browser."
            button.addTarget(self, action: link.action, for: .touchUpInside)
            aboutDetails.addArrangedSubview(button)
        }

        let contact = UIButton(type: .system)
        var contactConfig = UIButton.Configuration.plain()
        contactConfig.title = "Contact: pwdhash@nmic.app"
        contactConfig.image = UIImage(systemName: "envelope")
        contactConfig.imagePadding = 8
        contactConfig.titleLineBreakMode = .byCharWrapping
        contactConfig.contentInsets = .zero
        contact.configuration = contactConfig
        contact.contentHorizontalAlignment = .leading
        contact.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        contact.accessibilityIdentifier = "contactSupport"
        contact.accessibilityLabel = "Contact support at pwdhash@nmic.app"
        contact.accessibilityHint = "Opens your email app."
        contact.addTarget(self, action: #selector(contactSupport), for: .touchUpInside)
        aboutDetails.addArrangedSubview(contact)

        let source = UIButton(type: .system)
        var sourceConfig = UIButton.Configuration.plain()
        sourceConfig.title = "pwdhash.github.io/website/"
        sourceConfig.image = UIImage(systemName: "arrow.up.right")
        sourceConfig.imagePlacement = .trailing
        sourceConfig.imagePadding = 6
        sourceConfig.titleLineBreakMode = .byCharWrapping
        sourceConfig.contentInsets = .zero
        source.configuration = sourceConfig
        source.contentHorizontalAlignment = .leading
        source.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        source.accessibilityIdentifier = "originalProject"
        source.accessibilityLabel = "Stanford PwdHash original project website"
        source.accessibilityHint = "Opens in your web browser."
        source.addTarget(self, action: #selector(openOriginalProject), for: .touchUpInside)
        aboutDetails.addArrangedSubview(source)
        aboutDetails.addArrangedSubview(makeLabel("Original PwdHash contributors: Blake Ross, Collin Jackson, Nicholas Miyake, Dan Boneh, and John C. Mitchell.", style: .caption1))

        if let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
           let license = try? String(contentsOf: url, encoding: .utf8) {
            let heading = makeLabel("Original BSD license", style: .subheadline)
            heading.font = heading.font.withTraits(.traitBold)
            heading.textColor = .label
            aboutDetails.addArrangedSubview(heading)
            let notice = makeLabel(license, style: .caption2)
            notice.accessibilityIdentifier = "originalLicense"
            aboutDetails.addArrangedSubview(notice)
        }
        aboutDetails.translatesAutoresizingMaskIntoConstraints = false
        aboutContainer.addSubview(aboutDetails)
        // A hidden arranged view has zero height. Let its content extend while
        // hidden without conflicting with the stack's internal spacing/heights.
        let bottom = aboutDetails.bottomAnchor.constraint(equalTo: aboutContainer.bottomAnchor, constant: -16)
        bottom.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            aboutDetails.leadingAnchor.constraint(equalTo: aboutContainer.leadingAnchor, constant: 16),
            aboutDetails.trailingAnchor.constraint(equalTo: aboutContainer.trailingAnchor, constant: -16),
            aboutDetails.topAnchor.constraint(equalTo: aboutContainer.topAnchor, constant: 16),
            bottom
        ])
    }

    @objc private func toggleAbout() {
        guard acceptInteraction() else { return }
        hidePasswords()
        view.endEditing(true)
        aboutContainer.isHidden.toggle()
        let expanded = !aboutContainer.isHidden
        aboutButton.configuration?.title = expanded ? "Hide about & credits" : "About & credits"
        aboutButton.accessibilityValue = expanded ? "Expanded" : "Collapsed"
    }

    @objc private func openOriginalProject() {
        openWebsite("https://pwdhash.github.io/website/")
    }

    @objc private func openSupportWebsite() {
        openWebsite("https://nmic.app/pwdhash/ios")
    }

    @objc private func openPrivacyPolicy() {
        openWebsite("https://nmic.app/pwdhash/ios/privacy")
    }

    private func openWebsite(_ address: String) {
        guard acceptInteraction(), let url = URL(string: address) else { return }
        hidePasswords()
        view.endEditing(true)
        UIApplication.shared.open(url)
    }

    @objc private func contactSupport() {
        guard acceptInteraction(), let url = URL(string: "mailto:pwdhash@nmic.app") else { return }
        hidePasswords()
        view.endEditing(true)
        UIApplication.shared.open(url)
    }

    func acceptInteraction() -> Bool {
        if idle.isExpired() {
            clearSession(reason: .idle)
            return false
        }
        if hasData { idle.touch(); scheduleIdleTimer() }
        return true
    }

    private var hasData: Bool {
        !(address.field.text ?? "").isEmpty || !(password.field.text ?? "").isEmpty || !(output.field.text ?? "").isEmpty
    }

    private func scheduleIdleTimer() {
        timer?.invalidate()
        timer = Timer(timeInterval: 300, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.idle.isExpired() { self.clearSession(reason: .idle) }
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func inputsChanged() {
        output.wipe()
        copyButton.isEnabled = false
        if let text = address.field.text, !text.isEmpty, let domain = try? LegacyPwdHash.domain(for: text) {
            domainLabel.text = "Hashing domain: \(domain)"
        } else {
            domainLabel.text = "Uses the same domain rules as the original website."
        }
        status.text = "Ready when you are. Clears after 5 minutes idle."
        idle.touch()
        scheduleIdleTimer()
    }

    @objc private func generate() {
        guard acceptInteraction() else { return }
        do {
            let result = try LegacyPwdHash.generate(address: address.field.text ?? "", password: password.field.text ?? "")
            output.hide()
            output.field.text = result
            copyButton.isEnabled = true
            view.endEditing(true)
            idle.touch()
            scheduleIdleTimer()
            status.text = result.utf8.contains(0)
                ? "The original algorithm includes invisible characters for this long password. The result is preserved exactly."
                : "Generated. Edit either input, then Generate again."
        } catch {
            output.wipe()
            copyButton.isEnabled = false
            status.text = error.localizedDescription
        }
    }

    @objc private func copyPassword() {
        guard acceptInteraction(), let text = output.field.text, !text.isEmpty else { return }
        let clipboard = UIPasteboard.general
        clipboard.setItems([[UTType.utf8PlainText.identifier: text]], options: [
            .localOnly: true,
            .expirationDate: Date().addingTimeInterval(60)
        ])
        copiedChangeCount = clipboard.changeCount
        hidePasswords()
        status.text = "Copied on this iPhone. Clipboard clears in 60 seconds."
        UIAccessibility.post(notification: .announcement, argument: "Password copied. Expires in one minute.")
    }

    private func clearOwnClipboard() {
        guard let count = copiedChangeCount else { return }
        let clipboard = UIPasteboard.general
        if clipboard.changeCount == count { clipboard.items = [] }
        copiedChangeCount = nil
    }

    func hidePasswords() { password.hide(); output.hide() }

    func clearSession(reason: ClearReason) {
        view.endEditing(true)
        address.wipe()
        password.wipe()
        output.wipe()
        undoManager?.removeAllActions()
        copyButton.isEnabled = false
        domainLabel.text = "Uses the same domain rules as the original website."
        timer?.invalidate()
        timer = nil
        idle.reset()
        // Preserve an intentional copy long enough to paste after app switching.
        // iOS owns its 60-second expiration even while this app is suspended.
        if reason != .background { clearOwnClipboard() }
        switch reason {
        case .manual: status.text = "All fields cleared. Nothing saved."
        case .idle: status.text = "Cleared after 5 minutes idle."
        case .background: status.text = "Fields cleared when you left the app."
        }
    }

    func enteredBackground() {
        hidePasswords()
        view.endEditing(true)
        if backgroundSwitch.isOn { clearSession(reason: .background) }
        else if idle.isExpired() { clearSession(reason: .idle) }
    }

    func becameActive() {
        hidePasswords()
        if idle.isExpired() { clearSession(reason: .idle) }
    }

    @objc private func backgroundSettingChanged() {
        backgroundDetail.text = backgroundSwitch.isOn
            ? "Always clears after 5 minutes idle. Also clears immediately in the background. Copy expires in 60 seconds."
            : "Keeps fields while switching apps. After 5 minutes idle, clears when iOS next runs the app. Copy expires in 60 seconds."
    }

    @objc private func clearTapped() { clearSession(reason: .manual) }
    @objc private func dismissKeyboard() { view.endEditing(true) }
    @objc private func memoryWarning() { clearSession(reason: .manual) }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === address.field { password.field.becomeFirstResponder() }
        else { generate() }
        return false
    }
}

extension PasswordViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var candidate = touch.view
        while let current = candidate {
            if current is UIControl { return false }
            candidate = current.superview
        }
        return true
    }
}
