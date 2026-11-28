//
//  AppDelegate.swift
//  J2MEEmulator
//
//  Clean lifecycle management:
//  - No automatic GPS / CLLocationManager wakeups on launch
//  - No background audio / network keepalive spinning while idle on the home screen
//  - Keeps all Decade UI notifications & orientation forwarding intact
//

import UIKit
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Dọn sạch thông báo cũ từ phiên trước nếu còn tồn đọng
        DecadeBackgroundKeeper.shared.clearLockScreenNotification()
        return true
    }

    // Khi app đang mở (Foreground), KHÔNG hiển thị banner để tránh làm phiền khi đang chơi game
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }

    // Khi người dùng tắt/thoát app, lập tức dừng audio nền và xóa sạch thông báo
    func applicationWillTerminate(_ application: UIApplication) {
        DecadeBackgroundKeeper.shared.stopKeepalive()
        DecadeBackgroundKeeper.shared.clearLockScreenNotification()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // Allow GameViewController to rotate freely while keeping list/config screens portrait
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        var topVC = window?.rootViewController
        while let presented = topVC?.presentedViewController {
            if presented is UIAlertController { break }
            topVC = presented
        }
        return topVC?.supportedInterfaceOrientations ?? .portrait
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }
}
