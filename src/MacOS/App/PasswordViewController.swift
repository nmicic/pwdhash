import AppKit

@MainActor
final class FlippedView: NSView { override var isFlipped: Bool { true } }

@MainActor
final class BackgroundView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); bounds.fill() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

@MainActor
final class PasswordViewController: NSViewController, NSWindowDelegate {
    static let supportURL = "https://nmic.app/pwdhash/macos"
    static let privacyPolicyURL = "https://nmic.app/pwdhash/macos/privacy"

    enum ClearReason { case manual, idle, background, sleep, lock }
    static let domainRulesHint = "Uses the original website’s domain rules."
    let address = SecretField(title: "Site Address", placeholder: "example.com or full URL", identifier: "siteAddress", secret: false)
    let password = SecretField(title: "Site Password", placeholder: "Your original password", identifier: "sitePassword", secret: true)
    let output = SecretField(title: "Hashed Password", placeholder: "Generate to see your result", identifier: "hashedPassword", secret: true, editable: false)
    let generateButton = NSButton()
    let copyButton = NSButton()
    let clearButton = NSButton()
    let backgroundSwitch = NSButton(checkboxWithTitle: "Clear when leaving app", target: nil, action: nil)
    let aboutButton = NSButton()
    let status = NSTextField(wrappingLabelWithString: "Nothing saved. No history. No network.")
    private let domainLabel = NSTextField(wrappingLabelWithString: PasswordViewController.domainRulesHint)
    private var announcedCaution: String?
    private let backgroundDetail = NSTextField(wrappingLabelWithString: "")
    private let stack = NSStackView()
    private let aboutContainer = NSView()
    private let privacyCover = BackgroundView()
    private let privateEditor = PrivateFieldEditor()
    private var idle = IdleDeadline()
    private var timer: Timer?
    private var clipboardTimer: Timer?
    private var copiedChangeCount: Int?
    private var copyExpiry: ContinuousClock.Instant?
    private var sessionActivity: NSObjectProtocol?
    private var clipboardActivity: NSObjectProtocol?
    private let clipboard: NSPasteboard
    private let now: () -> ContinuousClock.Instant
    private let accent = NSColor(name: NSColor.Name("PwdHashAccent")) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.43, green: 0.84, blue: 0.70, alpha: 1)
            : NSColor(calibratedRed: 0.10, green: 0.36, blue: 0.28, alpha: 1)
    }

    init(clipboard: NSPasteboard = .general, now: @escaping () -> ContinuousClock.Instant = { .now }) {
        self.clipboard = clipboard; self.now = now
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() { view = BackgroundView(frame: NSRect(x: 0, y: 0, width: 470, height: 750)) }

    override func viewDidLoad() {
        super.viewDidLoad()
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        view.addSubview(scroll)
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -22)
        ])

        let title = NSTextField(labelWithString: "PwdHash")
        title.font = .systemFont(ofSize: 32, weight: .bold)
        configure(clearButton, title: "Clear", action: #selector(clearTapped(_:)), identifier: "clearAll")
        let header = NSStackView(views: [title, NSView(), clearButton])
        header.orientation = .horizontal; header.alignment = .centerY
        title.setContentHuggingPriority(.required, for: .horizontal)
        clearButton.setContentHuggingPriority(.required, for: .horizontal)
        add(header)
        let badge = label("OFFLINE · ORIGINAL PWDHASH", size: 11)
        badge.font = .systemFont(ofSize: 11, weight: .semibold); badge.textColor = accent
        add(badge)
        add(address); add(password); add(domainLabel); add(output)
        domainLabel.font = .systemFont(ofSize: 12); domainLabel.textColor = .secondaryLabelColor
        domainLabel.identifier = NSUserInterfaceItemIdentifier("domainHint")
        address.onEdit = { [weak self] in self?.inputsChanged() }
        password.onEdit = { [weak self] in self?.inputsChanged() }
        address.onSubmit = { [weak self] in self?.password.focus() }
        password.onSubmit = { [weak self] in self?.generate(nil) }

        configure(generateButton, title: "Generate", action: #selector(generate(_:)), identifier: "generate")
        generateButton.bezelColor = accent; generateButton.contentTintColor = accent; generateButton.keyEquivalent = "\r"
        configure(copyButton, title: "Copy", action: #selector(copyPassword(_:)), identifier: "copyPassword")
        copyButton.isEnabled = false
        let actions = NSStackView(views: [generateButton, copyButton])
        actions.orientation = .horizontal; actions.distribution = .fillEqually; actions.spacing = 10
        add(actions)
        add(label("Hold an eye to reveal. Release to hide.", size: 12))
        status.font = .systemFont(ofSize: 13); status.textColor = .secondaryLabelColor
        status.identifier = NSUserInterfaceItemIdentifier("status"); add(status)
        backgroundSwitch.state = .on
        backgroundSwitch.target = self; backgroundSwitch.action = #selector(backgroundSettingChanged(_:))
        backgroundSwitch.identifier = NSUserInterfaceItemIdentifier("clearOnBackground")
        add(backgroundSwitch)
        backgroundDetail.font = .systemFont(ofSize: 12); backgroundDetail.textColor = .secondaryLabelColor
        backgroundSettingChanged(nil); add(backgroundDetail)
        add(label("Copy stays on this Mac. PwdHash clears its current clipboard item after 60 seconds while running, but other apps and clipboard managers can read or retain a copy.", size: 12))
        configure(aboutButton, title: "About & credits", action: #selector(toggleAbout(_:)), identifier: "aboutCredits")
        add(aboutButton); configureAbout(); add(aboutContainer)
        privateEditor.isFieldEditor = true; privateEditor.allowsUndo = false
        configurePrivacyCover()
    }

    private func add(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func configure(_ button: NSButton, title: String, action: Selector, identifier: String) {
        button.title = title; button.target = self; button.action = action
        button.bezelStyle = .rounded; button.controlSize = .large
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
    }
    private func label(_ text: String, size: CGFloat = 13) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size); label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func configureAbout() {
        aboutContainer.isHidden = true
        let details = NSStackView()
        details.translatesAutoresizingMaskIntoConstraints = false
        details.orientation = .vertical; details.alignment = .leading; details.spacing = 12
        aboutContainer.addSubview(details)
        let author = label("macOS app developed by Nenad Micic as a personal hobby project, based on Stanford PwdHash.")
        author.textColor = .labelColor
        let legacyWarning = label("Legacy compatibility: if a generated password is exposed, guesses of a weak original password can be tested offline. Use a long, high-entropy original password.", size: 12)
        let support = NSButton(title: "Support & app information", target: self, action: #selector(openSupportWebsite(_:)))
        support.identifier = NSUserInterfaceItemIdentifier("supportWebsite")
        let privacy = NSButton(title: "Privacy policy", target: self, action: #selector(openPrivacyPolicy(_:)))
        privacy.identifier = NSUserInterfaceItemIdentifier("privacyPolicy")
        let contact = NSButton(title: "Contact: pwdhash@nmic.app", target: self, action: #selector(contactSupport(_:)))
        let source = NSButton(title: "pwdhash.github.io/website/", target: self, action: #selector(openOriginalProject(_:)))
        for button in [support, privacy, contact, source] { button.bezelStyle = .inline; button.contentTintColor = accent }
        let contributors = label("Original PwdHash contributors: Blake Ross, Collin Jackson, Nicholas Miyake, Dan Boneh, and John C. Mitchell.", size: 12)
        for item in [author, legacyWarning, support, privacy, contact, source, contributors] { details.addArrangedSubview(item); item.widthAnchor.constraint(equalTo: details.widthAnchor).isActive = true }
        if let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) {
            let notice = label(text, size: 11)
            details.addArrangedSubview(notice); notice.widthAnchor.constraint(equalTo: details.widthAnchor).isActive = true
        }
        let bottom = details.bottomAnchor.constraint(equalTo: aboutContainer.bottomAnchor, constant: -12)
        bottom.priority = NSLayoutConstraint.Priority(999)
        NSLayoutConstraint.activate([
            details.leadingAnchor.constraint(equalTo: aboutContainer.leadingAnchor), details.trailingAnchor.constraint(equalTo: aboutContainer.trailingAnchor),
            details.topAnchor.constraint(equalTo: aboutContainer.topAnchor, constant: 4), bottom
        ])
    }

    private func configurePrivacyCover() {
        privacyCover.translatesAutoresizingMaskIntoConstraints = false
        privacyCover.isHidden = true
        let icon = NSImageView(image: NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "Private session")!)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentTintColor = .secondaryLabelColor
        privacyCover.addSubview(icon); view.addSubview(privacyCover)
        NSLayoutConstraint.activate([
            privacyCover.leadingAnchor.constraint(equalTo: view.leadingAnchor), privacyCover.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            privacyCover.topAnchor.constraint(equalTo: view.topAnchor), privacyCover.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            icon.centerXAnchor.constraint(equalTo: privacyCover.centerXAnchor), icon.centerYAnchor.constraint(equalTo: privacyCover.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 48), icon.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    private var hasData: Bool { !address.value.isEmpty || !password.value.isEmpty || !output.value.isEmpty }
    func acceptInteraction() -> Bool {
        expireOwnClipboardIfNeeded()
        if idle.isExpired(at: now()) { clearSession(reason: .idle); return false }
        if hasData { touch() }
        return true
    }
    private func touch() {
        if sessionActivity == nil {
            sessionActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Clear the idle password session")
        }
        idle.touch(at: now()); timer?.invalidate()
        timer = Timer(timeInterval: 300, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.idle.isExpired(at: self.now()) { self.clearSession(reason: .idle) }
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    private func inputsChanged() {
        output.wipe(); copyButton.isEnabled = false
        showDomainHint(for: address.value)
        status.stringValue = "Ready when you are. Clears after 5 minutes idle."; touch()
    }
    /// Shows what will be hashed and, for an address a browser would read differently, a caution.
    /// The caution never blocks generating and never changes the result.
    private func showDomainHint(for value: String) {
        guard !value.isEmpty, let domain = try? LegacyPwdHash.domain(for: value) else {
            domainLabel.stringValue = Self.domainRulesHint; domainLabel.textColor = .secondaryLabelColor
            announcedCaution = nil
            return
        }
        let caution = AddressCaution.message(for: value)
        domainLabel.stringValue = caution.map { "Hashing domain: \(domain)\n\($0)" } ?? "Hashing domain: \(domain)"
        domainLabel.textColor = caution == nil ? .secondaryLabelColor : .labelColor
        guard caution != announcedCaution else { return }
        announcedCaution = caution
        if let caution {
            // VoiceOver does not read a label that changes on its own.
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
                .announcement: caution, .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ])
        }
    }
    @objc func generate(_ sender: Any?) {
        guard acceptInteraction() else { return }
        do {
            let result = try LegacyPwdHash.generate(address: address.value, password: password.value)
            output.hide(); output.value = result; copyButton.isEnabled = true
            _ = view.window?.makeFirstResponder(nil); touch()
            status.stringValue = result.utf8.contains(0)
                ? "The original algorithm includes invisible characters for this long password. The result is preserved exactly."
                : "Generated. Edit either input, then Generate again."
        } catch { output.wipe(); copyButton.isEnabled = false; status.stringValue = error.localizedDescription }
    }
    @objc func copyPassword(_ sender: Any?) {
        guard acceptInteraction(), !output.value.isEmpty else { return }
        let item = NSPasteboardItem()
        item.setString(output.value, forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        // Keep the count from the write we prepared. A later count can belong to another app.
        let changeCount = clipboard.prepareForNewContents(with: [.currentHostOnly])
        copiedChangeCount = changeCount
        guard clipboard.writeObjects([item]), clipboard.changeCount == changeCount else {
            clearOwnClipboard()
            status.stringValue = "Could not copy. Try again."
            return
        }
        copyExpiry = now().advanced(by: .seconds(60))
        if clipboardActivity == nil {
            clipboardActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Expire the copied password")
        }
        clipboardTimer?.invalidate()
        clipboardTimer = Timer(timeInterval: 60, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.clearOwnClipboard() } }
        RunLoop.main.add(clipboardTimer!, forMode: .common)
        hidePasswords(); status.stringValue = "Copied on this Mac. PwdHash clears its current item in 60 seconds while running."
    }
    private func expireOwnClipboardIfNeeded() { if let copyExpiry, now() >= copyExpiry { clearOwnClipboard() } }
    private func clearOwnClipboard() {
        if let count = copiedChangeCount, clipboard.changeCount == count { clipboard.clearContents() }
        copiedChangeCount = nil; copyExpiry = nil; clipboardTimer?.invalidate(); clipboardTimer = nil
        if let clipboardActivity { ProcessInfo.processInfo.endActivity(clipboardActivity); self.clipboardActivity = nil }
    }
    func hidePasswords() { password.hide(); output.hide() }
    func clearSession(reason: ClearReason) {
        address.wipe(); password.wipe(); output.wipe()
        privateEditor.string = ""; privateEditor.undoManager?.removeAllActions(); view.window?.undoManager?.removeAllActions()
        copyButton.isEnabled = false; showDomainHint(for: "")
        timer?.invalidate(); timer = nil; idle.reset()
        if let sessionActivity { ProcessInfo.processInfo.endActivity(sessionActivity); self.sessionActivity = nil }
        if reason != .background { clearOwnClipboard() }
        syncSecureKeyboardEntry()
        switch reason {
        case .manual: status.stringValue = "All fields cleared. Nothing saved."
        case .idle: status.stringValue = "Cleared after 5 minutes idle."
        case .background: status.stringValue = "Fields cleared when you left the app."
        case .sleep: status.stringValue = "Fields and copied password cleared before sleep."
        case .lock: status.stringValue = "Fields and copied password cleared when the screen locked."
        }
    }
    /// Secure keyboard entry is held only while the revealed editor has keyboard focus.
    private func syncSecureKeyboardEntry() {
        if view.window?.firstResponder === privateEditor { SecureKeyboardEntry.hold() } else { SecureKeyboardEntry.release() }
    }
    func enteredBackground() {
        hidePasswords(); _ = view.window?.makeFirstResponder(nil)
        // A hold kept while another app is in front would affect that app's keyboard handling.
        SecureKeyboardEntry.release()
        if backgroundSwitch.state == .on { clearSession(reason: .background) }
        else if idle.isExpired(at: now()) { clearSession(reason: .idle) }
        privacyCover.isHidden = false
    }
    func becameActive() {
        hidePasswords(); expireOwnClipboardIfNeeded()
        if idle.isExpired(at: now()) { clearSession(reason: .idle) }
        syncSecureKeyboardEntry()
        privacyCover.isHidden = true
    }
    func windowDidResignKey(_ notification: Notification) { hidePasswords() }
    @objc func clearTapped(_ sender: Any?) { clearSession(reason: .manual) }
    @objc func backgroundSettingChanged(_ sender: Any?) {
        backgroundDetail.stringValue = backgroundSwitch.state == .on
            ? "Clears after 5 minutes idle and immediately when the app becomes inactive."
            : "Keeps fields while switching apps. Clears after 5 minutes idle and before showing an expired session."
    }
    @objc func toggleAbout(_ sender: Any?) {
        guard acceptInteraction() else { return }
        hidePasswords(); _ = view.window?.makeFirstResponder(nil)
        aboutContainer.isHidden.toggle(); aboutButton.title = aboutContainer.isHidden ? "About & credits" : "Hide about & credits"
    }
    @objc func contactSupport(_ sender: Any?) { openURL("mailto:pwdhash@nmic.app") }
    @objc func openSupportWebsite(_ sender: Any?) { openURL(Self.supportURL) }
    @objc func openPrivacyPolicy(_ sender: Any?) { openURL(Self.privacyPolicyURL) }
    @objc func openOriginalProject(_ sender: Any?) { openURL("https://pwdhash.github.io/website/") }
    private func openURL(_ string: String) {
        guard acceptInteraction(), let url = URL(string: string) else { return }
        hidePasswords(); NSWorkspace.shared.open(url)
    }
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        guard let field = client as? NSTextField, field === password.plain else { return nil }
        privateEditor.setAccessibilityLabel(field.accessibilityLabel())
        return privateEditor
    }
}
