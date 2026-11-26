import AVFAudio
import SwiftUI
import UIKit

@main
struct jarNO1App: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: [.mixWithOthers]
        )
    }

    var body: some Scene {
        WindowGroup {
            RootNavigationHost()
                .ignoresSafeArea()
                .preferredColorScheme(.light)
                .tint(Color(red: 0.788, green: 0.329, blue: 0.122))
                .onOpenURL { url in
                    Task { @MainActor in
                        RootNavigationCoordinator.shared.homeController.handleExternalImport([url])
                    }
                }
        }
        .onChange(of: scenePhase) { newPhase in
            Task { @MainActor in
                switch newPhase {
                case .background:
                    MicroController.activeInstance?.appDidEnterBackground()
                case .active:
                    MicroController.activeInstance?.appWillEnterForeground()
                default:
                    break
                }
            }
        }
    }
}

@MainActor
private final class RootNavigationCoordinator {
    static let shared = RootNavigationCoordinator()

    let homeController: AppListController
    let navigationController: UINavigationController

    private init() {
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

        let home = AppListController()
        let nav = UINavigationController(rootViewController: home)
        nav.overrideUserInterfaceStyle = .light
        nav.view.backgroundColor = NstTheme.Apk.background
        self.homeController = home
        self.navigationController = nav
    }
}

private struct RootNavigationHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        RootNavigationCoordinator.shared.navigationController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        uiViewController.overrideUserInterfaceStyle = .light
    }
}
