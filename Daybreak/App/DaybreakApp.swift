import SwiftUI
import UIKit

/// The app starts in UIKit so its root can be a hosting controller of our own: SwiftUI has no way to choose the
/// status bar's style per tab, and Home and Weather need light text on their sky while the other tabs need the
/// default (as Android toggles `isAppearanceLightStatusBars` per tab).
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // The pull-to-refresh spinner sits on the sky, so it's white like everything else there.
        UIRefreshControl.appearance().tintColor = .white
        ClockFormat.use24Hour = ClockFormat.systemUses24Hour
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let controller = RootHostingController(statusBar: StatusBarStyle())
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        ClockFormat.use24Hour = ClockFormat.systemUses24Hour
    }
}

/// Whether the status bar's text is light (on the sky) or the system default, set by the tab showing.
@MainActor
@Observable
final class StatusBarStyle {
    var light = true {
        didSet { if light != oldValue { controller?.setNeedsStatusBarAppearanceUpdate() } }
    }
    @ObservationIgnored weak var controller: UIViewController?
}

final class RootHostingController: UIHostingController<AnyView> {
    let statusBar: StatusBarStyle

    init(statusBar: StatusBarStyle) {
        self.statusBar = statusBar
        super.init(rootView: AnyView(RootView().environment(statusBar)))
        statusBar.controller = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    override var preferredStatusBarStyle: UIStatusBarStyle { statusBar.light ? .lightContent : .default }
}
