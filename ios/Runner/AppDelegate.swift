import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // ── 1. Configure Firebase ────────────────────────────────────────────────
    FirebaseApp.configure()

    // ── 2. Set FCM delegate ──────────────────────────────────────────────────
    Messaging.messaging().delegate = self

    // ── 3. Request push-notification authorisation ───────────────────────────
    UNUserNotificationCenter.current().delegate = self
    let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
    UNUserNotificationCenter.current().requestAuthorization(
      options: authOptions,
      completionHandler: { _, _ in }
    )
    application.registerForRemoteNotifications()

    // ── 4. Register Flutter plugins ──────────────────────────────────────────
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ── APNs device token → FCM ──────────────────────────────────────────────
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("[APNs] Registration failed: \(error.localizedDescription)")
  }
}

// ── FCM token refresh ────────────────────────────────────────────────────────
extension AppDelegate: MessagingDelegate {
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("[FCM] Token: \(fcmToken ?? "nil")")
    // Forward to Flutter via EventChannel / shared preferences if needed.
    let dataDict: [String: String] = ["token": fcmToken ?? ""]
    NotificationCenter.default.post(
      name: Notification.Name("FCMToken"),
      object: nil,
      userInfo: dataDict
    )
  }
}

// ── Foreground notification display ─────────────────────────────────────────
extension AppDelegate {
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Show banner + sound even when app is in the foreground
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .badge, .sound])
    } else {
      completionHandler([.alert, .badge, .sound])
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }
}
