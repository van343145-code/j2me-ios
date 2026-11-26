import UIKit

@main
@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var homeController: AppListController?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureNavigationAppearance()

        let home = AppListController()
        self.homeController = home

        let nav = UINavigationController(rootViewController: home)
        nav.overrideUserInterfaceStyle = .light

        let win = UIWindow(frame: UIScreen.main.bounds)
        win.overrideUserInterfaceStyle = .light
        win.backgroundColor = NstTheme.Apk.background
        win.rootViewController = nav
        win.makeKeyAndVisible()
        self.window = win

        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        Task { @MainActor [weak self] in
            self?.homeController?.handleExternalImport([url])
        }
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Task { @MainActor in
            MicroController.activeInstance?.appDidEnterBackground()
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        Task { @MainActor in
            MicroController.activeInstance?.appWillEnterForeground()
        }
    }

    private func configureNavigationAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = NstTheme.Apk.background
        appearance.shadowColor = NstTheme.Apk.divider
        appearance.titleTextAttributes = [
            .foregroundColor: NstTheme.Apk.text,
            .font: UIFont.boldSystemFont(ofSize: 18),
        ]

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactAppearance = appearance
        bar.tintColor = NstTheme.Lic.accent
    }
}
