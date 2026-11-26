import UIKit

@MainActor
final class PrivateApplication: UIApplication {
    /// Returning false drops the first event after expiry, so it cannot copy
    /// or reveal the previous session before the idle timer gets CPU time.
    var acceptInteraction: (() -> Bool)?

    override func sendEvent(_ event: UIEvent) {
        let isInteraction = event.type == .touches || event.type == .presses
        if isInteraction, acceptInteraction?() == false { return }
        super.sendEvent(event)
    }
}

@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool { true }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Private session", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    // Keep secret input out of third-party keyboard extensions.
    func application(_ application: UIApplication, shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier) -> Bool {
        extensionPointIdentifier != .keyboard
    }

    func application(_ application: UIApplication, shouldSaveSecureApplicationState coder: NSCoder) -> Bool { false }
    func application(_ application: UIApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool { false }
}

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var screen: PasswordViewController?
    private var cover: UIView?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let screen = PasswordViewController()
        self.screen = screen
        let window = UIWindow(windowScene: scene)
        window.rootViewController = screen
        self.window = window
        (UIApplication.shared as? PrivateApplication)?.acceptInteraction = { [weak screen] in
            screen?.acceptInteraction() ?? true
        }
        window.makeKeyAndVisible()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        screen?.hidePasswords()
        guard let window, cover == nil else { return }
        let cover = UIView(frame: window.bounds)
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.backgroundColor = .systemBackground
        let icon = UIImageView(image: UIImage(systemName: "lock.shield"))
        icon.tintColor = .secondaryLabel
        icon.translatesAutoresizingMaskIntoConstraints = false
        cover.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalToConstant: 56)
        ])
        window.addSubview(cover)
        self.cover = cover
    }

    func sceneDidEnterBackground(_ scene: UIScene) { screen?.enteredBackground() }

    func sceneDidBecomeActive(_ scene: UIScene) {
        screen?.becameActive()
        cover?.removeFromSuperview()
        cover = nil
    }

    func sceneDidDisconnect(_ scene: UIScene) { screen?.clearSession(reason: .manual) }
}
