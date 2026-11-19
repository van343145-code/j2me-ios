//
//  AppDelegate.swift
//  J2MEEmulator
//
//  Created by Alexander Goremykin on 19.03.2026.
//

import UIKit
import UserNotifications
import MediaPlayer

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Yêu cầu quyền thông báo để hiển thị thẻ trạng thái trên thanh thông báo / màn hình khóa
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        // Dọn sạch mọi thông báo cũ từ phiên trước khi khởi động app
        DecadeBackgroundKeeper.shared.clearLockScreenNotification()

        // Xin quyền vị trí nền (Always) để dự phòng giữ app & mạng liên tục khi tắt màn hình
        DecadeLocationKeeper.shared.requestPermissionIfNeeded()

        // Khởi động Audio Keep-Alive ngay ở Foreground khi mở app để iOS cấp quyền chạy nền liên tục
        if DecadeBackgroundKeeper.shared.isTreoActive {
            DecadeBackgroundKeeper.shared.startKeepalive()
        }
        return true
    }

    // Khi app đang mở (Foreground), KHÔNG hiển thị banner để tránh làm phiền khi đang chơi game
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }

    // Khi người dùng tắt/thoát app (Swipe up kill app), lập tức xóa sạch mọi thông báo chạy ngầm
    func applicationWillTerminate(_ application: UIApplication) {
        DecadeBackgroundKeeper.shared.clearLockScreenNotification()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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
