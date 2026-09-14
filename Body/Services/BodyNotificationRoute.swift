import SwiftUI
import UIKit
@preconcurrency import UserNotifications

@MainActor @Observable
final class BodyNotificationRoute {
    struct Workout: Equatable {
        var id: UUID
        var start: Date
        var requestID = UUID()
    }
    var sleepRequestID: UUID?
    var readinessRequestID: UUID?
    var workout: Workout?
    var selectedTab: BodyMainTab = .summary
    var ready = false

    func receive(_ info: [AnyHashable: Any]) {
        sleepRequestID = nil
        readinessRequestID = nil
        if info["metric"] as? String == "readiness" {
            workout = nil
            readinessRequestID = UUID()
            selectedTab = .summary
            return
        }
        if info["metric"] as? String == "sleep" {
            workout = nil
            sleepRequestID = UUID()
            selectedTab = .summary
            return
        }
        guard let rawID = info["workoutID"] as? String, let id = UUID(uuidString: rawID),
              let start = info["workoutStart"] as? Double, start.isFinite else {
            workout = nil
            selectedTab = .summary
            return
        }
        workout = Workout(id: id, start: Date(timeIntervalSince1970: start))
        selectedTab = .workouts
    }
}

final class BodyNotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        Task { @MainActor in
            BodyAppRuntime.shared.notificationRoute.receive(info)
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }
}
