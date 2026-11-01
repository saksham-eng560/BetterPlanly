//
//  AppDelegate.swift
//  Planly
//
//  Notification actions: "Mark done" completes the task in the background, "Snooze 10 min" re-posts it.
//

import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Reminders.registerCategories()
        Sync.scheduleBackgroundRefresh()
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        switch response.actionIdentifier {
        case Reminders.markDoneAction:
            guard let taskId = content.userInfo["taskId"] as? Int, let client = SharedStore.client else { return }
            _ = try? await client.complete(taskId)
            await Sync.backgroundRefresh()
        case Reminders.snoozeAction:
            await Reminders.snooze(content)
        default:
            break
        }
    }
}
