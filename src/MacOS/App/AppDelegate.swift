import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Posted by the system when the screen locks. The name is not in Apple's documentation.
    static let screenLockedNotification = Notification.Name("com.apple.screenIsLocked")

    private var window: NSWindow?
    private let screen: PasswordViewController
    private var eventMonitor: Any?

    init(screen: PasswordViewController = PasswordViewController()) {
        self.screen = screen
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 750), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "PwdHash"; window.minSize = NSSize(width: 420, height: 590)
        window.isRestorable = false; window.tabbingMode = .disallowed
        window.contentViewController = screen; window.delegate = screen
        self.window = window
        buildMenu()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .keyDown, .keyUp, .scrollWheel]) { [weak self] event in
            let accept = MainActor.assumeIsolated { self?.screen.acceptInteraction() ?? true }
            return accept ? event : nil
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(willSleep(_:)), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(willSleep(_:)), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(willSleep(_:)), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        observeScreenLock()
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    /// A locked screen can stay lit, so display sleep alone does not cover it.
    func observeScreenLock(on center: NotificationCenter = DistributedNotificationCenter.default()) {
        center.addObserver(self, selector: #selector(screenLocked(_:)), name: Self.screenLockedNotification, object: nil)
    }
    func applicationDidResignActive(_ notification: Notification) { screen.enteredBackground() }
    func applicationDidBecomeActive(_ notification: Notification) { screen.becameActive() }
    func applicationWillTerminate(_ notification: Notification) {
        screen.clearSession(reason: .manual)
        SecureKeyboardEntry.release()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window?.makeKeyAndOrderFront(nil); return true }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    @objc private func willSleep(_ notification: Notification) { screen.clearSession(reason: .sleep) }
    @objc private func screenLocked(_ notification: Notification) { screen.clearSession(reason: .lock) }

    private func buildMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); bar.addItem(appItem)
        let appMenu = NSMenu(title: "PwdHash")
        let about = NSMenuItem(title: "About PwdHash", action: #selector(PasswordViewController.toggleAbout(_:)), keyEquivalent: "")
        about.target = screen; appMenu.addItem(about); appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide PwdHash", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit PwdHash", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); bar.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let copyPassword = editMenu.addItem(withTitle: "Copy Hashed Password", action: #selector(PasswordViewController.copyPassword(_:)), keyEquivalent: "c")
        copyPassword.keyEquivalentModifierMask = [.command, .shift]; copyPassword.target = screen
        editItem.submenu = editMenu
        let windowItem = NSMenuItem(); bar.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu; NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = bar
    }
}
